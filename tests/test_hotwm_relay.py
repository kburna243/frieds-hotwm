"""Automated tests for hotwm_relay engine."""

import asyncio
import json
import os
import sys
import tempfile
import time
import unittest
from pathlib import Path

# Add src directory to path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

import hotwm_relay as hr


class TestHotwmRelay(unittest.IsolatedAsyncioTestCase):
    async def test_led_bar_scaling(self):
        # 4 lives: exact 1:1 match
        self.assertEqual(hr.led_bar("P1", 4, b"\n", top=4).count(b"= 1"), 4)
        self.assertEqual(hr.led_bar("P1", 3, b"\n", top=4).count(b"= 1"), 3)
        self.assertEqual(hr.led_bar("P1", 2, b"\n", top=4).count(b"= 1"), 2)
        self.assertEqual(hr.led_bar("P1", 1, b"\n", top=4).count(b"= 1"), 1)
        self.assertEqual(hr.led_bar("P1", 0, b"\n", top=4).count(b"= 1"), 0)

        # 100 percentage points: scaled to 4 LEDs
        self.assertEqual(hr.led_bar("P2", 100, b"\n", top=100).count(b"= 1"), 4)
        self.assertEqual(hr.led_bar("P2", 75, b"\n", top=100).count(b"= 1"), 3)
        self.assertEqual(hr.led_bar("P2", 50, b"\n", top=100).count(b"= 1"), 2)
        self.assertEqual(hr.led_bar("P2", 25, b"\n", top=100).count(b"= 1"), 1)
        self.assertEqual(hr.led_bar("P2", 0, b"\n", top=100).count(b"= 1"), 0)

    async def test_recoil_pulse_stretching(self):
        out = []
        relay = hr.Relay(out.append, hold_ms=100)
        t0 = time.monotonic()

        # Instant 0 after 1 (e.g. 10ms later)
        relay.feed(b"1pRecoil = 1\r\n")
        await asyncio.sleep(0.01)
        relay.feed(b"1pRecoil = 0\r\n")

        # Must not be in out immediately
        self.assertNotIn(b"1pRecoil = 0\r\n", out)

        # Wait remaining time
        await asyncio.sleep(0.12)
        self.assertIn(b"1pRecoil = 0\r\n", out)
        duration = time.monotonic() - t0
        self.assertGreaterEqual(duration, 0.09)
        relay.close()

    async def test_ammo_drop_triggers_shot(self):
        out = []
        relay = hr.Relay(out.append, hold_ms=80)

        relay.feed(b"Ammo1pA = 10\r\n")
        self.assertNotIn(b"P1_Shot = 1\r\n", out)

        relay.feed(b"Ammo1pA = 9\r\n")
        self.assertIn(b"P1_Shot = 1\r\n", out)
        self.assertNotIn(b"P1_Shot = 0\r\n", out)

        await asyncio.sleep(0.1)
        self.assertIn(b"P1_Shot = 0\r\n", out)
        relay.close()

    async def test_config_manager_game_filters(self):
        with tempfile.NamedTemporaryFile("w+", delete=False, suffix=".json", encoding="utf-8") as f:
            cfg = {
                "global": {"hold_ms": 150, "ammo_drop_shot": True},
                "games": {
                    "DisabledRumble": {"rumble": False, "leds": True},
                    "DisabledLeds": {"rumble": True, "leds": False},
                    "GameHold": {"hold_ms": 275},
                },
            }
            f.write("\ufeff" + json.dumps(cfg))
            temp_path = f.name

        try:
            cm = hr.ConfigManager(temp_path)
            self.assertEqual(cm.hold_ms, 150)
            self.assertFalse(cm.game_settings("DisabledRumble")["rumble"])
            self.assertTrue(cm.game_settings("DisabledRumble")["leds"])
            self.assertTrue(cm.game_settings("DisabledLeds")["rumble"])
            self.assertFalse(cm.game_settings("DisabledLeds")["leds"])
            self.assertTrue(cm.game_settings("UnknownGame")["rumble"])
            self.assertEqual(cm.game_settings("GameHold")["hold_ms"], 275)
        finally:
            os.remove(temp_path)

    async def test_relay_uses_hot_reloaded_global_hold_and_game_override(self):
        f = tempfile.NamedTemporaryFile("w+", delete=False, suffix=".json", encoding="utf-8")
        try:
            f.write(json.dumps({"global": {"hold_ms": 90}, "games": {"LongGame": {"hold_ms": 260}}}))
            f.flush()
            path = Path(f.name)
            config = hr.ConfigManager(path)
            out = []
            relay = hr.Relay(out.append, hold_ms=60, config_manager=config)

            relay.feed(b"1pRecoil = 1\r\n")
            await asyncio.sleep(0.01)
            f.seek(0)
            f.truncate()
            f.write(json.dumps({"global": {"hold_ms": 220}, "games": {"LongGame": {"hold_ms": 260}}}))
            f.flush()
            relay.feed(b"1pRecoil = 0\r\n")
            await asyncio.sleep(0.14)
            self.assertNotIn(b"1pRecoil = 0\r\n", out)
            await asyncio.sleep(0.12)
            self.assertIn(b"1pRecoil = 0\r\n", out)

            relay.feed(b"mame_start = LongGame\r\n")
            relay.feed(b"2pRecoil = 1\r\n")
            await asyncio.sleep(0.01)
            relay.feed(b"2pRecoil = 0\r\n")
            await asyncio.sleep(0.14)
            self.assertNotIn(b"2pRecoil = 0\r\n", out)
            await asyncio.sleep(0.15)
            self.assertIn(b"2pRecoil = 0\r\n", out)
            relay.close()
        finally:
            f.close()
            os.remove(f.name)

    async def test_explicit_relay_hold_is_fallback_when_injected_config_omits_hold(self):
        f = tempfile.NamedTemporaryFile("w+", delete=False, suffix=".json", encoding="utf-8")
        try:
            f.write(json.dumps({"global": {}, "games": {}}))
            f.flush()
            config = hr.ConfigManager(f.name)
            out = []
            relay = hr.Relay(out.append, hold_ms=60, config_manager=config)
            relay.feed(b"1pRecoil = 1\r\n")
            await asyncio.sleep(0.01)
            relay.feed(b"1pRecoil = 0\r\n")
            self.assertNotIn(b"1pRecoil = 0\r\n", out)
            await asyncio.sleep(0.07)
            self.assertIn(b"1pRecoil = 0\r\n", out)
            relay.close()
        finally:
            f.close()
            os.remove(f.name)

    async def test_led_mode_none_suppresses_health_mapping_but_not_manual_test(self):
        f = tempfile.NamedTemporaryFile("w+", delete=False, suffix=".json", encoding="utf-8")
        try:
            f.write(json.dumps({"global": {"led_mode": "none"}, "games": {}}))
            f.flush()
            path = Path(f.name)
            config = hr.ConfigManager(path)
            out = []
            relay = hr.Relay(out.append, config_manager=config)
            relay.feed(b"P1_Health = 50\r\n")
            self.assertEqual(out, [b"P1_Health = 50\r\n"])

            sink = type("Sink", (), {"write": lambda self, data: out.append(data)})()
            hr.CLIENTS.add(sink)
            try:
                await hr.trigger_test_leds(player=1)
            finally:
                hr.CLIENTS.discard(sink)
            self.assertTrue(any(b"P1_Led" in item for item in out))
            relay.close()

            f.seek(0)
            f.truncate()
            f.write(json.dumps({"global": {"led_mode": "life_bar"}, "games": {}}))
            f.flush()
            relay2 = hr.Relay(out.append, config_manager=config)
            before = len(out)
            relay2.feed(b"P1_Health = 50\r\n")
            self.assertEqual(len(out), before + 2)
            self.assertIn(b"P1_Led1", out[-1])
            relay2.close()
        finally:
            f.close()
            os.remove(f.name)

    async def test_invalid_hot_reload_retains_last_valid_configuration(self):
        f = tempfile.NamedTemporaryFile("w+", delete=False, suffix=".json", encoding="utf-8")
        try:
            f.write(json.dumps({"global": {"hold_ms": 180}, "games": {}}))
            f.flush()
            path = Path(f.name)
            config = hr.ConfigManager(path)
            self.assertEqual(config.hold_ms, 180)
            f.seek(0)
            f.truncate()
            f.write("{ invalid")
            f.flush()
            self.assertEqual(config.hold_ms, 180)
            f.seek(0)
            f.truncate()
            f.write(json.dumps({"global": {"hold_ms": "fast"}, "games": {}}))
            f.flush()
            self.assertEqual(config.hold_ms, 180)
        finally:
            f.close()
            os.remove(f.name)

    async def test_socket_control_ping_and_triggers(self):
        server = await hr.serve(listen_port=18001, upstream_port=18003, hold_ms=100)
        try:
            resp = await hr.send_socket_command("PING", port=18001)
            self.assertEqual(resp, "PONG")

            cmd_resp = await hr.send_socket_command("TEST_P1_RUMBLE", port=18001)
            self.assertEqual(cmd_resp, "OK")
        finally:
            server.close()
            await server.wait_closed()

    def test_parse_show_players(self):
        self.assertEqual(hr.parse_show_players("SHOW_PLAYERS 1=2 2=1"), [(1, 2), (2, 1)])
        self.assertIsNone(hr.parse_show_players("SHOW_PLAYERS 1=x"))
        self.assertIsNone(hr.parse_show_players("SHOW_PLAYERS 5=1"))
        self.assertIsNone(hr.parse_show_players("SHOW_PLAYERS"))

    async def test_show_players_rumbles_and_blinks_the_player_each_wiimote_should_be(self):
        class Sink:
            def __init__(self): self.data = b""
            def write(self, d): self.data += d
        sink = Sink()
        hr.CLIENTS.add(sink)
        try:
            await hr.trigger_show_players([(1, 2), (2, 1)], cycles=2, on_s=0, off_s=0)
        finally:
            hr.CLIENTS.discard(sink)
        lines = sink.data.decode().split("\r\n")
        self.assertEqual(lines[0], "mame_start = TeknoParrot FFB")
        self.assertIn("1pRecoil = 1", lines)
        self.assertIn("P1_Led2 = 1", lines)   # Gunmote's Wiimote 1 should be player 2
        self.assertIn("P2_Led1 = 1", lines)
        self.assertEqual(lines.count("1pRecoil = 1"), 2)
        self.assertEqual([l for l in lines if l][-1], "mame_stop = 1")


if __name__ == "__main__":
    unittest.main()
