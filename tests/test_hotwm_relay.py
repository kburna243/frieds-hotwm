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
        with tempfile.NamedTemporaryFile("w+", delete=False, suffix=".json") as f:
            cfg = {
                "global": {"hold_ms": 150, "ammo_drop_shot": True},
                "games": {
                    "DisabledRumble": {"rumble": False, "leds": True},
                    "DisabledLeds": {"rumble": True, "leds": False},
                },
            }
            json.dump(cfg, f)
            temp_path = f.name

        try:
            cm = hr.ConfigManager(temp_path)
            self.assertEqual(cm.hold_ms, 150)
            self.assertFalse(cm.game_settings("DisabledRumble")["rumble"])
            self.assertTrue(cm.game_settings("DisabledRumble")["leds"])
            self.assertTrue(cm.game_settings("DisabledLeds")["rumble"])
            self.assertFalse(cm.game_settings("DisabledLeds")["leds"])
            self.assertTrue(cm.game_settings("UnknownGame")["rumble"])
        finally:
            os.remove(temp_path)

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


if __name__ == "__main__":
    unittest.main()
