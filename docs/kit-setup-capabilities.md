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

For the five change steps above, the current public API response is not a concrete, reviewable file/task plan. `Invoke-StepOperation` in `api/RetroCabinetKit.Api.psm1` captures only `RetroCabinetKit.StepResult` objects, and reduces each `Data.Steps` entry to `Name`, `Status`, `WhatIf`, `Message`, and `Duration`. It copies `Changes`, `Backups`, and `Approvals` from the step result/context. In dry-run mode, `core/modules/Step.ps1` skips the step's Invoke block, so those arrays do not describe proposed writes. Steps 06 and 07 compute detailed plans and send them to `Write-KitLog` before calling `Invoke-KitStep`; those lines are outside the step context and are filtered out by the API's isolated operation runner. They do not appear in the JSON response. This is specific to these step operations; it is not a claim that every Kit API operation lacks structured plans.

A representative dry-run response for step 06 is shaped like this (message, version, and duration are runtime values):

```json
{
  "ApiVersion": "1.7",
  "KitVersion": "<installed version>",
  "Operation": "step.lightgun.06-gunmotelayouts",
  "Kind": "Change",
  "Success": true,
  "Status": "WhatIf",
  "Applied": false,
  "Changes": [],
  "Backups": [],
  "Approvals": [],
  "Data": {
    "Steps": [{
      "Name": "lightgun-6-layouts",
      "Status": "Skipped",
      "WhatIf": true,
      "Message": "<generic dry-run status>",
      "Duration": 0.0
    }]
  }
}
```

`Success` is true for the `WhatIf` status by design; it means the dry run completed, not that the cabinet is configured. On apply, the outer `Applied` value is copied from the requested `-Apply` switch in `Invoke-StepOperation`, even if the step later fails or declines. It is therefore an intent flag, not evidence of completed writes. Inspect `Status`, `Data.Steps`, `Errors`, `Changes`, and `Backups` after an apply, and still do not infer hardware readiness from them.

API `Approved` is a separate operation switch, not a step parameter. `Invoke-StepOperation` stores the supplied boolean and wires a callback for steps that declare `Approve`; the callback records the Kit's approval text but returns that boolean without comparing the text to a previously displayed plan. The callback is used by steps 03, 04, and 08. Steps 06 and 07 have no such internal callback. In dry-run mode, the Invoke block is skipped, so the approval text for 03, 04, and 08 is not returned. Step 03's signed-installer file/hash details are generated inside `Install-LightgunViGEm` during Invoke, not in the step dry-run response. `src/KitClient.ps1` currently exposes `-Apply` but not `-Approved`.

Consequently, a wrapper using only the current dry-run response cannot truthfully present an exact action proposal or bind a user's yes to the exact file/task plan that will be applied. It must not claim exact-file-preimage protection: the API does not expose original file bytes or hashes for these step plans. Re-running the dry run after confirmation and comparing its generic response reduces staleness but cannot close this gap; step 06/07 previews remain absent, and the Kit's boolean callback does not bind the apply-time approval text to the reviewed plan.

Before enabling a safe all-in-one HOTWM apply flow for these steps, the Kit API needs to return structured per-step plans and relevant live preconditions, then verify during apply that a freshly reconstructed plan still matches the one the wrapper presented. The wrapper should keep its plan record private and one-shot, bind it to an allowlisted operation, normalized parameters, canonical selected root, Kit/API version, and the returned plan/preconditions, and expose only a synchronous confirmation callback—not a public `Approved` field or reusable imported grant. On acceptance it should recheck root, required files, closed-process conditions, administrator status, user SID, and ACL prerequisites immediately before applying; it should stop on any plan mismatch. `Approved` should be forwarded only after that callback and only for steps with a real Kit approval callback. Do not auto-apply the sequence or reinterpret a successful dry run as completion.

## Manual gaps and unregistered functions

The API catalog contains no operation for HOTWM relay installation/task registration, writing HOTWM `hotw.json`, or configuring the HOTWM relay through Kit. Related functions exist in Kit output modules (`output/modules/HookOfTheWiimote.ps1`, `output/modules/WiimoteHook.ps1`) but are not registered API operations. Do not call them through a setup wrapper without a reviewed plan/approval contract.

Bluetooth pairing and per-controller calibration remain manual. PnP/hardware checks do not verify aim, trigger, recoil, or Gunmote runtime player identity. The API's current-order Wiimote save must not be presented as persistent desired-player mapping or reconnect-safe runtime association.

Kit cabinet `profile.export` writes a ZIP (and may create directories); `profile.import` validates/reads an archive in plan mode and changes destination files only when applied. These are migration operations, not HOTWM profile/template import and export.

## Source reviewed

- `retro-cabinet-kit/api/RetroCabinetKit.Api.psm1` — public catalog, parameter filtering, step dispatch, Apply/Approved handling, and step-result reduction.
- `retro-cabinet-kit/api/modules/Isolation.ps1` and `api/modules/Result.ps1` — isolated API return filtering and OperationResult `Success`/`Applied` semantics.
- `retro-cabinet-kit/lightgun/steps/03-ViGEmBus.ps1`, `04-Gunmote.ps1`, `06-GunmoteLayouts.ps1`, `07-RetroBatSettings.ps1`, `08-ProfileAutomation.ps1`, `09-Verify.ps1`, and `15-Adapter.ps1` — step parameters, previews, prerequisites, and effects.
- `retro-cabinet-kit/core/modules/Step.ps1` — WhatIf and step-context behavior.
- `frieds-hotwm/src/KitClient.ps1` — HOTWM API client surface (`-Apply`, no `-Approved`).
- `retro-cabinet-kit/output/modules/HookOfTheWiimote.ps1` and `WiimoteHook.ps1` — existing functions that are not API-registered.
- `retro-cabinet-kit/core/modules/CabinetProfile.ps1` — cabinet archive import/export behavior.
- `retro-cabinet-kit/emulators/modules/Adapters.ps1` and `frontends/modules/Adapters.ps1` — adapter install/configuration behavior.
