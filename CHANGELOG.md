# Changelog

All notable changes to Fried's Hotwm (Hook of the Wiimote). The version lives in [`VERSION`](VERSION); a tag
`vX.Y.Z` that matches it publishes the portable zip as a GitHub release.

## [0.10.0] - 2026-10-11

Guided setup: from the emulator folder to Wiimotes assigned per player, with every change reviewed first.

### Added

- Guided setup with Quick, Custom and Expert modes on one shared session: folder check (read-only), device
  discovery, player assignment, manual calibration, aim and trigger checks the person confirms.
- Wiimotes identified by their Bluetooth address (Bluetooth and Nintendo HID parent entries); the desired player is
  stored by address, separate from the slot Gunmote assigns at run time.
- "Zuordnung ins Kit übernehmen": the confirmed address → player mapping is saved in Fried's Retrogaming Kit
  (Kit API 1.8, `controllers.wiimote_bind` with `Binding`). Hotwm shows the Kit's plan and applies only with its
  `PlanId`; a Kit without plan ids is never applied.
- Editors for effect profiles, semantic button intents and real Gunmote button layouts; every file change is a
  proposal with backup, conflict check and its own confirmation.
- Read-only Cabinet diagnostics from the Kit with masked Bluetooth addresses.
- Fried's design: Night/Cream theme and four local mascot images (SVG + PNG).
- Release workflow (this zip) and a project website on GitHub Pages.

### Fixed

- The relay honours live effect settings and keeps a valid configuration.
- The Kit is found next to Hotwm without machine-specific paths.

### Not covered

- Pairing stays semi-automatic and calibration manual; a physical test with two Wiimotes (reconnect, swapped
  switch-on order, aim, trigger, rumble) is still open. See `docs/verification.md`.