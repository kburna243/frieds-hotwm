# Hotwm P0 device capability matrix

This is a bounded assessment of `gui/HotwmDashboard.ps1` and the read-only Windows PnP helper in `src/HotwmDevices.ps1`. It does not establish behavior for every Wiimote, Bluetooth stack, or DolphinBar combination.

| Capability | Evidence and behavior | Status |
|---|---|---|
| Existing GUI presence check | `Get-WiimoteDevicesStatus` calls `Get-PnpDevice`, matches friendly names containing DolphinBar/Wiimote/RVL-CNT-01/Nintendo, and reports CONNECTED for any status-OK match. | Presence only; cannot identify a controller or prove it works. |
| Individual Bluetooth identity | `ConvertTo-HotwmBluetoothMac` accepts a per-device address in a Bluetooth PnP `BTHENUM`/`BTHLEDEVICE` `DEV_<12 hex>` instance identifier, or in a PnP property explicitly named as a Bluetooth/device address. It never derives an address from a friendly name, adapter address, enumeration order, or USB identifier. | Conditional on the actual Windows Bluetooth driver exposing the per-device address through these fields. Actual hardware backend and property behavior remain unknown pending a hardware survey. |
| Stable player assignment | `Resolve-HotwmPlayerMappings` matches normalized MAC mappings independent of enumeration order and rejects duplicate identities/assignments or slots outside players 1 and 2. | Data helper only; no pairing or profile persistence. |
| DolphinBar | A PnP friendly name can establish that a bar is detected. A USB DolphinBar identifier is excluded as a Wiimote MAC source. | Individual controller MAC is not inferred from bar presence. |
| Pairing | The completion plan calls for semi-automatic guided pairing, potentially with physical steps. The reviewed hotwm GUI contains no demonstrated per-controller pairing API. | Not implemented or claimed by this P0 slice. |
| Calibration and operation | PnP status does not establish calibration, aim/trigger function, or haptic output. Discovery initializes `ManuallyCalibrated`, `Tested`, and `Ready` to false. | Requires later guided manual calibration and target testing with actual hardware. |
| Gunmote integration | The reviewed GUI searches for a Gunmote process. That does not establish a supported identity, pairing, or calibration API. | No Gunmote API is asserted. |

Next evidence needed: capture actual PnP instance IDs and per-device properties for the supported Windows/Bluetooth combinations, then verify identity stability through disconnect and reconnect. Device readiness must remain false until the later calibration and per-player target test explicitly succeed.
