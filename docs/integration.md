# HOTWM integration snapshot v1

`Get-HotwmIntegrationSnapshot` in `src/HotwmIntegration.ps1` is a read-only
diagnostic contract for the HOTWM GUI and future trusted integrations. It asks
the RetroCabinetKit API for its `operations` catalog, then queries the
available `controllers.wiimote_order` and `outputs.wiimote_hook` operations.
The Wiimote-order operation was introduced in Kit API 1.6 / Kit 1.4.0; clients
use the returned catalog to discover support instead of assuming a version.
The current Kit API can report a newer version while retaining that operation.

The snapshot keeps two different facts separate:

- `Runtime.WiimoteOrder.ReportedRuntimeOrder` is the order the Kit currently
  reports from connected devices and Windows arrival data.
- `Desired.WiimoteBinding` is the saved player mapping returned by the Kit's
  `Expected` field. It is not inferred from the current order.

The Kit's Wiimote ledger is stored in the current user's
`%USERPROFILE%\RetroCabinet\wiimotes.json`. It is global to that Kit/user
profile; it is not scoped to a selected RetroBat installation. The optional
`RetroBatRoot` parameter is sent only to `outputs.wiimote_hook`, which accepts
that root. The v1 snapshot retains Kit states such as `NoGunmote`, `Unclear`,
`NoWiimote`, `Unbound`, `Ok`, and `Swapped` without promoting them into a HOTWM
readiness verdict.

The hook result is exposed as the Kit's observed status and data. Any Kit
`Recommendation` value is named `KitRecommendation` to make its origin clear;
HOTWM does not assert that a system is ready based on it. A successful
`Kit.Success` means the catalog and Wiimote-order read succeeded. Hook failure
is reported on `Runtime.OutputHook` and in `Kit.Errors` without hiding an
otherwise valid order snapshot.

Bluetooth MAC addresses are replaced with `[REDACTED-MAC]` in ordinary
diagnostics, including dictionary/property keys, nested strings such as
Windows device `InstanceId` values, and error text. If multiple keys redact to
the same label, the keys are processed in sorted order and receive stable
`[2]`, `[3]` suffixes so no entry is silently dropped. `-IncludeSensitive`
opts into the raw Kit details and should be reserved for an explicit local
diagnostic workflow.

The optional `-KitInvoker` scriptblock is a test seam called with an operation
name and a plain parameter hashtable. Production calls go through
`Invoke-HotwmKitApi`. The snapshot requests read operations only and does not
pass `-Apply`, an approval flag, or arbitrary script content. The seam is not a
security boundary against arbitrary code running as the same Windows user.

This snapshot does not implement apply/rollback or a consent flow and never
invokes `controllers.wiimote_bind`. Writing the binding is a separate path:
`Publish-HotwmKitWiimoteBinding` in `src/HotwmKitBinding.ps1` sends the
session's confirmed MAC mappings as `Binding` (Kit API 1.8), shows the Kit's
plan through the trusted GUI confirmation, and applies only with that plan's
`PlanId`; a Kit without plan ids is never applied. The RetroGamingAgent
(`frieds-retrogaming-agent`) uses the same Kit operation through its own
policy gate and passes the `PlanId` from its own dry run; a model cannot set it. The GUI's existing canned Agent success
messages are not evidence that an Agent has queried this contract or changed
the cabinet. These legacy placeholders belong to the separate RetroGamingAgent
project; Hotwm does not treat them as a successful integration.

## Verification

The deterministic Pester fixtures in `tests/HotwmIntegration.Tests.ps1` inject
Kit API responses. They verify capability discovery, root scoping, order vs.
binding separation, privacy masking, explicit sensitive output, failure
handling, and the `NoGunmote` / `Unclear` states. They do not call real Kit
operations or inspect physical devices.
