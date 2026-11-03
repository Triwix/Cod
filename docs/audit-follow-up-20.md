# Audit follow-up · Cod Test 1.0 (20)

October 30, 2026. Fixes the image-float request lifecycle identified in the
external audit. Public privacy/support hosting and publishing identity remain
deferred at the owner's request. The existing privacy policy URL is deliberately
blank; this candidate is not ready for App Store submission.

## Change

`CaptureCoordinator.startFloating` begins observing the outcome before calling
`PiPPinController.float`. A fresh external-image pipeline previously called the
ordinary teardown, which synchronously published `idle`. The coordinator treated
that as a terminal stop, marked a pending share retryable and stopped handling
the actual preparation's success or failure.

Fresh playback now uses `teardown(keepStatus: true)`, like the existing tool/video
replacement paths. It releases the old playback resources without publishing a
request-ending status. The next event is `preparing`. An actual stop still emits
`idle`, and unsupported playback still emits `unsupported`.

The controller's capability check is injectable for lifecycle tests; normal app
initialization always uses AVKit's documented capability query. The tests inspect
synchronous state and cancel before the encoding task runs. They do not fake a
native PiP success or establish visible playback on a device.

## Verification

Artifacts: `/private/tmp/cod-audit20.uaIlvX`.

- Initial native-capability-only tests skipped on this simulator, which reports
  no PiP support. They were replaced with deterministic lifecycle tests.
- Before the fix, four lifecycle tests failed and the unsupported-path test
  passed (`race-reproduced.xcresult`). This reproduced the extra `idle` event,
  the lost working state and the incorrectly released pending-share claim.
- After the fix, all five lifecycle tests passed in the first full suite. That
  unsigned run also exposed missing simulator signing entitlements in existing
  shared-Keychain/container tests; signing is required for those tests.
- All 218 signed unit tests passed, including the five lifecycle tests
  (`unit20-signed.xcresult`). No skips or failures.
- Cod / Debug signed device build passed (`device20.log`); its signature passed
  `codesign --verify --deep --strict`. Bundle ID is `com.josh.cod.store`, build
  20, display name Cod Test. Device installation is recorded below.
- Cod / Release archive passed (`archive20.log`). The unsigned local archive's
  app and both extensions passed `Tools/verify-store-build.sh`
  (`archive-audit20.log`). Display name is Cod and build is 20.
- The source guard and whitespace checks passed. The optional `--submission`
  audit correctly fails on the still-blank policy URL (`submission-gate20.log`).
  This is a known deferred release gate, not a submission-ready archive.
- Four signed iPhone simulator sharing-flow UI tests passed, with no skips
  (`entry20.xcresult`): automatic Share preparation followed by manual app
  activation; the system document menu; cold notification launch; and the
  installed signed Shortcut delivering two distinct images on cold/warm launch.
  The document menu did not directly foreground Cod on this runtime, so that
  test exercised its permitted Share/manual-open fallback. It is not evidence
  of a direct document launch. Simulator native PiP is unavailable; these are
  input/handoff checks, not visible-picture acceptance.

Local verification is complete. The signed development app is ready at
`/private/tmp/cod-audit20.uaIlvX/DeviceData/Build/Products/Debug-iphoneos/Cod.app`.
The local unsigned Release archive is
`/private/tmp/cod-audit20.uaIlvX/Cod20.xcarchive`.

## Device installation · November 1, 2026

Installed build 20 (`com.josh.cod.store`) on Jay, the paired iPhone 16 Pro Max.
The original Cod installation and data were not targeted. The public Wi-Fi
router explicitly rejected direct Mac-to-phone traffic; connecting the Mac to
the iPhone's Personal Hotspot restored Apple's paired developer connection.
Tailscale remained enabled with no exit node selected.

Installation succeeded. The first launch was denied with iOS's signature,
entitlement or developer-trust security error. The local signature verifies;
all three provisioning profiles are current and include this phone. The owner
completed developer verification and confirmed that Cod Test opens. This resolves
the initial launch block. Feature checks, including actual PiP playback and
share-request completion, remain open; successful launch alone is not physical
feature acceptance.

## Scope and remaining gates

No Share-extension direct launch, private selectors, automatic app return,
experimental scheme, entitlement or Shortcut identity change was added. The
original installed Cod app/data are untouched. Build 20 uses
`com.josh.cod.store` / Cod Test for development, and Cod for public Release.

The final distribution-signed archive, physical-device PiP/alarms, approved
metadata and hosted privacy/support URLs remain release gates. The reviewer
notes already disclose the generated still-image video and sample-buffer tools.
Use of documented APIs and a passing local archive scan do not establish App
Review acceptance.
