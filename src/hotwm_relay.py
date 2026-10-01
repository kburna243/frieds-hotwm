"""Hook of the Wiimote (hotwm) — Output Relay Server.

Translates arcade output signals from FFBBlaster, DemulShooter, and MAME into
stretched rumble pulses and dynamic LED health displays for Wiimotes behind Gunmote.

Sources:
  * FFBBlaster (TeknoParrot, OutputsSystem=1, NetOutputsTCPPort=8002): TCP client connection.
  * MAME output window messages ("MAMEOutput" window): DemulShooter (WM_OutputsEnabled) & MAME.
Sink:
  * Gunmote ArcadeHook (TCP client on localhost:8000).

Features:
  * Recoil pulse stretching: 16ms pulses stretched to 150ms (or hotw.json hold_ms).
  * Ammo drop to shot pulse generation: automatic rumble when ammo decreases.
  * Health scaling: scales player health to 4 player LEDs on the Wiimote.
  * Dynamic hotw.json configuration with per-game rumble/LED toggles and hot-reload.
  * Test trigger socket API: instant rumble/LED verification without starting games.
"""

import asyncio
import ctypes
import json
import os
import re
import sys
import threading
import time
from pathlib import Path

DEFAULT_LISTEN_PORT = 8000
DEFAULT_UPSTREAM_PORT = 8002
DEFAULT_HOLD_MS = 150

STRETCH_P1 = {"1pRecoil", "P1_CtmRecoil"}
STRETCH_P2 = {"2pRecoil", "P2_CtmRecoil"}
ALL_STRETCH = STRETCH_P1 | STRETCH_P2

HEALTH = {"P1_Health": "P1", "P2_Health": "P2", "P1_Life": "P1", "P2_Life": "P2"}
AMMO = {"Ammo1pA": "P1", "Ammo2pA": "P2", "P1_Ammo": "P1", "P2_Ammo": "P2"}

LINE = re.compile(rb"^\s*(.+?)\s*=\s*(-?\d+)\s*$")
MAME_START = re.compile(rb"^(\s*mame_start\s*=\s*)(.*?)(\s*)$", re.S)
SHARED_FFB, SHARED_DS = b"TeknoParrot FFB", b"DemulShooter"

DEFAULT_CONFIG_PATH = Path(__file__).resolve().parent.parent / "config" / "hotw.json"
TRACE_LOG = Path(__file__).resolve().parent.parent / "recoil-stretch-trace.log"
TRACE_ON_FILE = Path(__file__).resolve().parent.parent / "recoil-stretch.trace"

CLIENTS = set()
WM_START = [None]


class ConfigManager:
    """Manages hotw.json with automatic hot-reload on file modification."""

    def __init__(self, config_path=None):
        self.path = Path(config_path) if config_path else DEFAULT_CONFIG_PATH
        self.last_mtime = 0
        self.config = {
            "global": {
                "hold_ms": DEFAULT_HOLD_MS,
                "ammo_drop_shot": True,
                "led_mode": "life_bar",
                "trace_enabled": False,
            },
            "games": {},
        }
        self.reload()

    def reload(self):
        if not self.path.exists():
            return
        try:
            mtime = self.path.stat().st_mtime
            if mtime > self.last_mtime:
                with self.path.open("r", encoding="utf-8") as f:
                    data = json.load(f)
                if isinstance(data, dict):
                    self.config = data
                    self.last_mtime = mtime
        except Exception:
            pass

    @property
    def hold_ms(self):
        self.reload()
        return self.config.get("global", {}).get("hold_ms", DEFAULT_HOLD_MS)

    @property
    def ammo_drop_shot(self):
        self.reload()
        return self.config.get("global", {}).get("ammo_drop_shot", True)

    @property
    def trace_enabled(self):
        self.reload()
        return self.config.get("global", {}).get("trace_enabled", False) or TRACE_ON_FILE.exists()

    def game_settings(self, game_name, default_hold=None):
        self.reload()
        fallback_hold = default_hold if default_hold is not None else self.hold_ms
        if not game_name:
            return {"rumble": True, "leds": True, "hold_ms": fallback_hold}
        games = self.config.get("games", {})
        gn_lower = game_name.strip().lower()
        for k, v in games.items():
            if k.lower() == gn_lower and isinstance(v, dict):
                return {
                    "rumble": v.get("rumble", True),
                    "leds": v.get("leds", True),
                    "hold_ms": v.get("hold_ms", fallback_hold),
                }
        return {"rumble": True, "leds": True, "hold_ms": fallback_hold}


GLOBAL_CONFIG = ConfigManager()


def trace(msg):
    if GLOBAL_CONFIG.trace_enabled:
        try:
            with TRACE_LOG.open("ab") as f:
                f.write(time.strftime("%H:%M:%S").encode() + b" %.3f " % (time.monotonic() % 1000) + msg.strip() + b"\n")
        except Exception:
            pass


def led_bar(player, value, eol, top=100):
    lit = value if top <= 4 else -(-value * 4 // top)
    return b"".join(b"%s_Led%d = %d%s" % (player.encode(), k, int(k <= lit), eol) for k in range(1, 5))


class Relay:
    """Core message processing engine for recoil stretching, ammo drops, and LED health."""

    def __init__(self, sink, hold_ms=DEFAULT_HOLD_MS, shared=None):
        self.sink = sink
        self.hold = hold_ms / 1000
        self.shared = shared
        self.loop = asyncio.get_running_loop()
        self.on_since = {}
        self.pending = {}
        self.ammo = {}
        self.shot_off = {}
        self.top = {}
        self.current_game = ""

    def feed(self, msg):
        trace(msg)
        eol = msg[len(msg.rstrip(b"\r\n")):] or b"\r\n"

        if s := MAME_START.match(msg):
            self.ammo.clear()
            self.top.clear()
            raw_name = s.group(2).decode(errors="replace").strip()
            self.current_game = raw_name
            if self.shared:
                msg = s.group(1) + self.shared + s.group(3)

        if msg.strip().startswith(b"mame_stop"):
            self.current_game = ""

        m = LINE.match(msg.strip())
        name = m and m.group(1).decode(errors="replace")
        settings = GLOBAL_CONFIG.game_settings(self.current_game, default_hold=self.hold * 1000)

        if name in ALL_STRETCH:
            if not settings.get("rumble", True):
                return
            current_hold = settings.get("hold_ms", self.hold * 1000) / 1000
            if m.group(2) != b"0":
                if t := self.pending.pop(name, None):
                    t.cancel()
                self.on_since[name] = time.monotonic()
            else:
                wait = current_hold - (time.monotonic() - self.on_since.get(name, 0))
                if wait > 0:
                    self.pending[name] = self.loop.call_later(wait, self.sink, msg)
                    return

        self.sink(msg)

        if name in AMMO and GLOBAL_CONFIG.ammo_drop_shot and settings.get("rumble", True):
            value, player = int(m.group(2)), AMMO[name]
            current_hold = settings.get("hold_ms", self.hold * 1000) / 1000
            if value < self.ammo.get(name, -1):
                if t := self.shot_off.pop(player, None):
                    t.cancel()
                self.sink(b"%s_Shot = 1%s" % (player.encode(), eol))
                self.shot_off[player] = self.loop.call_later(current_hold, self.sink, b"%s_Shot = 0%s" % (player.encode(), eol))
            self.ammo[name] = value

        if name in HEALTH and settings.get("leds", True):
            value = int(m.group(2))
            self.top[name] = max(self.top.get(name, 0), value)
            self.sink(led_bar(HEALTH[name], value, eol, self.top[name]))

    def close(self):
        for t in (*self.pending.values(), *self.shot_off.values()):
            t.cancel()


def lines(buf):
    out = []
    while (i := min((p for p in (buf.find(b"\r"), buf.find(b"\n")) if p >= 0), default=-1)) >= 0:
        j = i + 1
        while j < len(buf) and buf[j:j + 1] in (b"\r", b"\n"):
            j += 1
        out.append(buf[:j])
        buf = buf[j:]
    return out, buf


def broadcast(data):
    for w in list(CLIENTS):
        try:
            w.write(data)
        except Exception:
            pass


async def trigger_test_pulse(player=1, hold_ms=DEFAULT_HOLD_MS):
    """Triggers an immediate test pulse on Wiimote rumble."""
    hold_sec = hold_ms / 1000
    if player == 1:
        broadcast(b"1pRecoil = 1\r\nP1_CtmRecoil = 1\r\n")
        await asyncio.sleep(hold_sec)
        broadcast(b"1pRecoil = 0\r\nP1_CtmRecoil = 0\r\n")
    else:
        broadcast(b"2pRecoil = 1\r\nP2_CtmRecoil = 1\r\n")
        await asyncio.sleep(hold_sec)
        broadcast(b"2pRecoil = 0\r\nP2_CtmRecoil = 0\r\n")


async def trigger_test_leds(player=1):
    """Cycles Wiimote LEDs from 4 down to 0."""
    p_tag = ("P%d" % player).encode()
    for count in (4, 3, 2, 1, 0):
        bar = b"".join(b"%s_Led%d = %d\r\n" % (p_tag, k, int(k <= count)) for k in range(1, 5))
        broadcast(bar)
        await asyncio.sleep(0.3)


async def pump_up(reader, writer, relay):
    buf = b""
    while data := await reader.read(4096):
        done, buf = lines(buf + data)
        for msg in done:
            relay.feed(msg)
        await writer.drain()


async def client_reader_loop(c_reader, c_writer, hold_ms):
    """Reads incoming commands from connected clients (Gunmote or test triggers)."""
    buf = b""
    while data := await c_reader.read(4096):
        done, buf = lines(buf + data)
        for line in done:
            cmd = line.strip().decode(errors="ignore").upper()
            if cmd in ("CMD_TEST_P1_RUMBLE", "TEST_P1_RUMBLE"):
                asyncio.create_task(trigger_test_pulse(player=1, hold_ms=hold_ms))
            elif cmd in ("CMD_TEST_P2_RUMBLE", "TEST_P2_RUMBLE"):
                asyncio.create_task(trigger_test_pulse(player=2, hold_ms=hold_ms))
            elif cmd in ("CMD_TEST_P1_LEDS", "TEST_P1_LEDS"):
                asyncio.create_task(trigger_test_leds(player=1))
            elif cmd in ("CMD_TEST_P2_LEDS", "TEST_P2_LEDS"):
                asyncio.create_task(trigger_test_leds(player=2))
            elif cmd == "PING":
                c_writer.write(b"PONG\r\n")
                await c_writer.drain()


async def handle(c_reader, c_writer, upstream_port, hold_ms):
    """Handles one Gunmote connection and maintains FFBBlaster upstream connection."""
    CLIENTS.add(c_writer)
    if WM_START[0]:
        c_writer.write(WM_START[0])
    closed = asyncio.create_task(client_reader_loop(c_reader, c_writer, hold_ms))
    try:
        while not closed.done():
            try:
                u_reader, u_writer = await asyncio.open_connection("127.0.0.1", upstream_port)
            except OSError:
                await asyncio.wait([closed], timeout=1)
                continue
            relay = Relay(c_writer.write, hold_ms, SHARED_FFB)
            up = asyncio.create_task(pump_up(u_reader, c_writer, relay))
            await asyncio.wait([up, closed], return_when=asyncio.FIRST_COMPLETED)
            up.cancel()
            relay.close()
            u_writer.close()
    except (ConnectionError, OSError):
        pass
    finally:
        closed.cancel()
        CLIENTS.discard(c_writer)
        c_writer.close()


def wm_source(loop, feed):
    """MAME output protocol Win32 window message receiver (DemulShooter / MAME)."""
    import ctypes
    from ctypes import wintypes as W

    u32, k32 = ctypes.WinDLL("user32"), ctypes.WinDLL("kernel32")
    LRESULT = ctypes.c_ssize_t
    WNDPROC = ctypes.WINFUNCTYPE(LRESULT, W.HWND, W.UINT, W.WPARAM, W.LPARAM)
    u32.DefWindowProcW.argtypes = [W.HWND, W.UINT, W.WPARAM, W.LPARAM]
    u32.DefWindowProcW.restype = LRESULT
    u32.PostMessageW.argtypes = [W.HWND, W.UINT, W.WPARAM, W.LPARAM]
    u32.FindWindowW.argtypes = [W.LPCWSTR, W.LPCWSTR]
    u32.FindWindowW.restype = W.HWND
    u32.CreateWindowExW.argtypes = [
        W.DWORD, W.LPCWSTR, W.LPCWSTR, W.DWORD, ctypes.c_int, ctypes.c_int, ctypes.c_int,
        ctypes.c_int, W.HWND, W.HMENU, W.HINSTANCE, W.LPVOID
    ]
    u32.CreateWindowExW.restype = W.HWND
    k32.OpenProcess.restype = W.HANDLE

    class WNDCLASSW(ctypes.Structure):
        _fields_ = [
            ("style", W.UINT), ("lpfnWndProc", WNDPROC), ("cbClsExtra", ctypes.c_int), ("cbWndExtra", ctypes.c_int),
            ("hInstance", W.HINSTANCE), ("hIcon", W.HICON), ("hCursor", W.HANDLE), ("hbrBackground", W.HBRUSH),
            ("lpszMenuName", W.LPCWSTR), ("lpszClassName", W.LPCWSTR)
        ]

    class COPYDATASTRUCT(ctypes.Structure):
        _fields_ = [("dwData", ctypes.c_size_t), ("cbData", W.DWORD), ("lpData", ctypes.c_void_p)]

    reg = {
        n: u32.RegisterWindowMessageW(n)
        for n in ("MAMEOutputStart", "MAMEOutputStop", "MAMEOutputUpdateState", "MAMEOutputRegister", "MAMEOutputGetIDString")
    }
    st = {"server": None, "hwnd": None, "names": {}, "wait": {}, "shared": None}

    def emit(line):
        loop.call_soon_threadsafe(feed, line)

    def owner_exe(hwnd):
        pid = W.DWORD()
        u32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        h = k32.OpenProcess(0x1000, False, pid.value)
        buf, n = ctypes.create_unicode_buffer(260), W.DWORD(260)
        ok = h and k32.QueryFullProcessImageNameW(h, 0, buf, ctypes.byref(n))
        if h:
            k32.CloseHandle(h)
        return buf.value.lower() if ok else ""

    def attach(server):
        st.update(server=server, names={}, wait={})
        st["shared"] = SHARED_DS if "demulshooter" in owner_exe(server) else None
        u32.PostMessageW(server, reg["MAMEOutputRegister"], st["hwnd"], 4711)
        u32.PostMessageW(server, reg["MAMEOutputGetIDString"], st["hwnd"], 0)

    def wndproc(hwnd, msg, wp, lp):
        if msg == reg["MAMEOutputStart"]:
            attach(wp)
        elif msg == reg["MAMEOutputStop"]:
            if st["server"]:
                emit(b"mame_stop = 1\r\n")
            st["server"] = None
        elif msg == reg["MAMEOutputUpdateState"] and st["server"]:
            oid, value = wp, ctypes.c_int32(lp & 0xFFFFFFFF).value
            if oid in st["names"]:
                emit(b"%s = %d\r\n" % (st["names"][oid], value))
            else:
                if oid not in st["wait"]:
                    u32.PostMessageW(st["server"], reg["MAMEOutputGetIDString"], hwnd, oid)
                st["wait"][oid] = value
        elif msg == 0x004A:
            cds = ctypes.cast(lp, ctypes.POINTER(COPYDATASTRUCT)).contents
            if cds.cbData >= 4 and cds.lpData:
                oid = ctypes.c_uint32.from_address(cds.lpData).value
                name = ctypes.string_at(cds.lpData + 4).strip()
                if oid == 0:
                    emit(b"mame_start = %s\r\n" % (st["shared"] or name))
                else:
                    st["names"][oid] = name
                    if oid in st["wait"]:
                        emit(b"%s = %d\r\n" % (name, st["wait"].pop(oid)))
            return 1
        elif msg == 0x0113 and not st["server"]:
            if server := u32.FindWindowW("MAMEOutput", None):
                attach(server)
        return u32.DefWindowProcW(hwnd, msg, wp, lp)

    proc = WNDPROC(wndproc)
    wc = WNDCLASSW(lpfnWndProc=proc, hInstance=k32.GetModuleHandleW(None), lpszClassName="HotwmMameClient")
    u32.RegisterClassW(ctypes.byref(wc))
    st["hwnd"] = u32.CreateWindowExW(0, wc.lpszClassName, "hotwm-recoil", 0x80000000, 0, 0, 0, 0, None, None, wc.hInstance, None)
    u32.SetTimer(st["hwnd"], 1, 2000, None)
    msg = W.MSG()
    while u32.GetMessageW(ctypes.byref(msg), None, 0, 0) > 0:
        u32.TranslateMessage(ctypes.byref(msg))
        u32.DispatchMessageW(ctypes.byref(msg))


async def serve(listen_port=DEFAULT_LISTEN_PORT, upstream_port=DEFAULT_UPSTREAM_PORT, hold_ms=DEFAULT_HOLD_MS):
    return await asyncio.start_server(lambda r, w: handle(r, w, upstream_port, hold_ms), "127.0.0.1", listen_port)


async def send_socket_command(cmd, port=DEFAULT_LISTEN_PORT):
    """Utility to send a control command to a running relay instance."""
    try:
        r, w = await asyncio.open_connection("127.0.0.1", port)
        w.write(cmd.encode() + b"\r\n")
        await w.drain()
        if cmd == "PING":
            resp = await asyncio.wait_for(r.readline(), timeout=1.0)
            w.close()
            await w.wait_closed()
            return resp.strip().decode()
        await asyncio.sleep(0.1)
        w.close()
        await w.wait_closed()
        return "OK"
    except Exception as e:
        return f"Error connecting to relay on port {port}: {e}"


async def selftest():
    """Validates pulse stretching, ammo drop shot creation, life scaling and game filters."""
    got = []

    async def fake_ffbblaster(r, w):
        for line in (
            b"mame_start = rambo\r\n",
            b"1pRecoil = 1\r\n",
            b"1pRecoil = 0\r\n",
            b"P1_Health = 2\r\n",
            b"Ammo1pA = 8\r\n",
            b"Ammo1pA = 7\r\n",
        ):
            w.write(line)
        await w.drain()
        await asyncio.sleep(0.4)
        w.close()

    up = await asyncio.start_server(fake_ffbblaster, "127.0.0.1", 18002)
    proxy = await serve(18000, 18002, 150)
    r, cw = await asyncio.open_connection("127.0.0.1", 18000)
    t0 = time.monotonic()
    while len(got) < 13:
        got.append((await r.readuntil(b"\n"), time.monotonic() - t0))
    cw.close()
    up.close()
    proxy.close()

    names = [g[0] for g in got]
    assert names[0] == b"mame_start = TeknoParrot FFB\r\n", f"Expected TeknoParrot FFB start, got {names[0]}"
    assert names[1] == b"1pRecoil = 1\r\n", f"Expected 1pRecoil = 1, got {names[1]}"
    assert names[2] == b"P1_Health = 2\r\n", f"Expected P1_Health = 2, got {names[2]}"
    assert names[3] == b"P1_Led1 = 1\r\n", f"Expected P1_Led1 = 1, got {names[3]}"
    assert names[4] == b"P1_Led2 = 1\r\n", f"Expected P1_Led2 = 1, got {names[4]}"
    assert names[5] == b"P1_Led3 = 0\r\n", f"Expected P1_Led3 = 0, got {names[5]}"
    assert names[6] == b"P1_Led4 = 0\r\n", f"Expected P1_Led4 = 0, got {names[6]}"
    assert names[7] == b"Ammo1pA = 8\r\n", f"Expected Ammo1pA = 8, got {names[7]}"
    assert names[8] == b"Ammo1pA = 7\r\n", f"Expected Ammo1pA = 7, got {names[8]}"
    assert names[9] == b"P1_Shot = 1\r\n", f"Expected P1_Shot = 1, got {names[9]}"
    assert set(names[10:12]) == {b"1pRecoil = 0\r\n", b"P1_Shot = 0\r\n"}, f"Expected 1pRecoil=0 and P1_Shot=0, got {names[10:12]}"
    assert min(got[10][1], got[11][1]) >= 0.14, "Recoil pulse was not stretched properly"

    # Test DemulShooter path
    out = []
    ds = Relay(out.append, 150, SHARED_DS)
    for line in (
        b"mame_start = hotd2\r\n",
        b"P1_Life = 5\r\n",
        b"P1_CtmRecoil = 1\r\n",
        b"P1_CtmRecoil = 0\r\n",
        b"P1_Life = 3\r\n",
    ):
        ds.feed(line)
    assert out[0] == b"mame_start = DemulShooter\r\n"
    assert b"P1_Led1 = 1\r\nP1_Led2 = 1\r\nP1_Led3 = 1\r\nP1_Led4 = 1\r\n" in out[2]
    assert b"P1_CtmRecoil = 0\r\n" not in out
    await asyncio.sleep(0.2)
    assert out[-1] == b"P1_CtmRecoil = 0\r\n"
    ds.close()

    print("Selftest PASSED: recoil pulse stretched (>=140ms), ammo drop -> P1_Shot, LED life bar scaled, shared INIs ok.")


async def main():
    if "--selftest" in sys.argv:
        await selftest()
        return

    if "--test-p1-rumble" in sys.argv:
        res = await send_socket_command("TEST_P1_RUMBLE")
        print(f"P1 Rumble test command: {res}")
        return

    if "--test-p2-rumble" in sys.argv:
        res = await send_socket_command("TEST_P2_RUMBLE")
        print(f"P2 Rumble test command: {res}")
        return

    if "--test-p1-leds" in sys.argv:
        res = await send_socket_command("TEST_P1_LEDS")
        print(f"P1 LEDs test command: {res}")
        return

    if "--test-p2-leds" in sys.argv:
        res = await send_socket_command("TEST_P2_LEDS")
        print(f"P2 LEDs test command: {res}")
        return

    if "--status" in sys.argv:
        res = await send_socket_command("PING")
        if res == "PONG":
            print("hotwm relay is RUNNING and responding on port 8000.")
        else:
            print(f"hotwm relay is NOT active: {res}")
        return

    # Normal server start
    print(f"Starting hotwm relay server on port {DEFAULT_LISTEN_PORT} (upstream {DEFAULT_UPSTREAM_PORT})...")
    loop = asyncio.get_running_loop()
    wm = Relay(broadcast, GLOBAL_CONFIG.hold_ms)

    def wm_feed(line):
        if MAME_START.match(line):
            WM_START[0] = line
        elif line.strip().startswith(b"mame_stop"):
            WM_START[0] = None
        wm.feed(line)

    # Start Win32 message loop in background thread
    threading.Thread(target=wm_source, args=(loop, wm_feed), daemon=True).start()
    server = await serve(DEFAULT_LISTEN_PORT, DEFAULT_UPSTREAM_PORT, GLOBAL_CONFIG.hold_ms)
    print("hotwm relay is active and ready for Gunmote connections.")

    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
