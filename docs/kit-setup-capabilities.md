# Retro Cabinet Kit setup capabilities

Read-only source audit of sibling project `retro-cabinet-kit`, performed 2026-10-11. No Kit API operation or change operation was invoked. This note records what the current API can plan or change; it is not evidence that a machine has these components installed or that a Wiimote is working.

## Useful existing operations

| Operation | Current public parameters | Plan/apply behavior and limits |
|---|---|---|
| `outputs.verify_safety` | `RetroBatRoot?` | Read-only output safety check. |
| `outputs.wiimote_hook` | `RetroBatRoot?` | Read-only diagnostics for the existing hook/Gunmote context; not relay installation or device readiness. |
| `step.lightgun.01-detect` | `RetroBatRoot` | Checks the selected RetroBat root. Apply can update Kit state with the detected root/version. |
| `step.lightgun.02-hardware` | none | Read-only hardware/monitor assessment. It does not pair, calibrate, or prove aim/trigger behavior. |
| `step.lightgun.03-vigembus` | `AllowInstall?` | Can install the ViGEmBus prerequisite only with `-Apply -Approved`, administrator rights, and the step's signer/hash checks. Without `AllowInstall`, it only reports status. |
| `step.lightgun.04-gunmote` | `GunmotePath?` | Can register the task for an already-installed Gunmote with Apply and required administrator/user-SID conditions. It does not download or install Gunmote. |
| `step.lightgun.06-gunmotelayouts` | `GunmotePath?`, `RetroBatRoot?`, `Mode?` (`Keep`/`Replace`), `Connection?` | Plans layout/Keymaps changes. Apply writes the generated layout files and Keymaps, with backups; requires valid paths and relevant processes closed. `Replace` is an explicit destructive choice. |
| `step.lightgun.07-retrobatsettings` | `RetroBatRoot?` | Plans RetroBat settings changes; Apply can edit settings and back up files. Requires the root and relevant processes to be available. |
| `step.lightgun.08-profileautomation` | `RetroBatRoot?`, `Connection?` | Installs profile automation, scheduled tasks, and hooks with Apply plus Approved, administrator/user-SID and ACL prerequisites. `AutomationDir`, `TrustedOwner`, and `TaskPrefix` are real step parameters but are explicitly denied by the API's public-parameter filter; defaults are used. |
| `step.lightgun.09-verify` | Interactive step is unavailable through the API | Source describes interactive XInput/profile/launcher checks. It is not Wiimote aim/trigger calibration. |

The API also has generic RetroBat/frontend operations. `emulators.install(Emulator, RetroBatRoot?, PackagePath?)` and `frontends.install(Frontend, RetroBatRoot?, PackagePath?)` show official-source links in their no-Apply plan; installation requires a user-supplied package and both Apply and Approved. They do not download packages. Emulator/frontend configuration, theme/routing, shader presets, setup mode, and named presets generally use Apply without a separate Approved gate and return summary plans rather than a complete file-by-file preview. They can modify files or Kit state, so they are not suitable for blanket automatic application.

`controllers.wiimote_bind` takes no parameters and saves current connection order to `wiimotes.json` when applied (backing up an existing file). It cannot persist a chosen MAC-to-player assignment or establish that Gunmote runtime slots match that assignment. `controllers.input_apply` is a MAME cabinet-panel profile operation, not Wiimote association.

## Dry-run and approval boundaries

For step operations, the API sets WhatIf when Apply is absent. The Kit step runner skips its Invoke block and Kit-state writes, but preflight checks and planning may still read live devices, files, processes, or paths. A plan is therefore not a pure in-memory simulation. Apply is a separate user decision. API-level Approved is forwarded only to steps that declare the internal approval callback; do not assume that every operation's parameter named `Approved` is safely wired through the API.

For any future all-in-one setup wrapper, keep operations staged: validate the selected root; show the concrete plan; require explicit Apply for each file/task change; require Approved only where the operation has a real approval callback; and recheck root, required files, closed-process conditions, administrator status, user SID, and ACL prerequisites immediately before applying. Do not silently treat a dry-run as success or auto-apply a whole sequence. The existing Kit API does not currently provide a single safe all-in-one setup operation.

## Manual gaps and unregistered functions

The API catalog contains no operation for HOTWM relay installation/task registration, writing HOTWM `hotw.json`, or configuring the HOTWM relay through Kit. Related functions exist in Kit output modules (`output/modules/HookOfTheWiimote.ps1`, `output/modules/WiimoteHook.ps1`) but are not registered API operations. Do not call them through a setup wrapper without a reviewed plan/approval contract.

Bluetooth pairing and per-controller calibration remain manual. PnP/hardware checks do not verify aim, trigger, recoil, or Gunmote runtime player identity. The API's current-order Wiimote save must not be presented as persistent desired-player mapping or reconnect-safe runtime association.

Kit cabinet `profile.export` writes a ZIP (and may create directories); `profile.import` validates/reads an archive in plan mode and changes destination files only when applied. These are migration operations, not HOTWM profile/template import and export.

## Source reviewed

- `retro-cabinet-kit/api/RetroCabinetKit.Api.psm1` — public catalog, parameter filtering, step dispatch, Apply/Approved handling and result shape.
- `retro-cabinet-kit/lightgun/steps/03-ViGEmBus.ps1`, `04-Gunmote.ps1`, `06-GunmoteLayouts.ps1`, `08-ProfileAutomation.ps1`, `09-Verify.ps1`, and `15-Adapter.ps1` — step parameters, prerequisites, and effects.
- `retro-cabinet-kit/core/modules/Step.ps1` — WhatIf behavior.
- `retro-cabinet-kit/output/modules/HookOfTheWiimote.ps1` and `WiimoteHook.ps1` — existing functions that are not API-registered.
- `retro-cabinet-kit/core/modules/CabinetProfile.ps1` — cabinet archive import/export behavior.
- `retro-cabinet-kit/emulators/modules/Adapters.ps1` and `frontends/modules/Adapters.ps1` — adapter install/configuration behavior.
