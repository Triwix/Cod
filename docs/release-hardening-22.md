# Reliability and release preparation · 1.0 (22)

November 3, 2026. Working branch: `codex/release-hardening-22`.
The code pass preserves supported sharing routes and does not publish a site
or submit an app. At the owner's subsequent request, Cod Test 1.0 (22) was
installed and launched on Jay (iPhone 16 Pro Max) on November 3. Apple's device
tool confirmed both the installed version and successful launch. Only
`com.josh.cod.store` was targeted; the original Cod app and data remain untouched.
This confirms installation/launch, not physical feature acceptance.

## Changes

- Replaced the still-image encoder's unbounded callback continuation with a
  cancellable asynchronous readiness/finalization wait and a 15-second deadline.
  Failed writers, rejected frames, stalled completion and cancellation release
  the request; incomplete output files are removed. Successful completion is
  accepted from one status snapshot, avoiding a completion-between-reads race.
- Added deterministic encoder failure/cancellation/deadline tests, an actual
  generated-video decode check, and asynchronous storage/orientation regressions
  in `Release22Tests`. These are tests added, not a claim of passing execution.
- Moved actual orientation redraws and final PiP image resizing off the main
  actor. Already normalized images retain synchronous request bookkeeping.
  Cancelled or replaced normalization cannot present stale content.
- Share handoff PNG encoding and coordinated writes now run off the main actor.
  The extension still only prepares the request; notifications, manual opening,
  Shortcuts and system controls remain the supported activation routes.
- Settings loads Library byte counts asynchronously behind pending saves and
  removals, rather than enumerating its directory during each body evaluation.
- Routine app, PiP stdout and extension diagnostics are Debug-only. Release
  logging doesn't evaluate diagnostic message expressions. The release artifact
  guard rejects the known log-file/stdout markers.
- Removed retired Imgur action wording, retaining the raw saved-preference case
  so older preferences still decode. No uploader is present.
- Reviewed the privacy resources. UserDefaults declarations remain; the timer
  reason remains for ContinuousClock-backed elapsed timers/deadlines. Updated
  the draft policy to distinguish Release from development logging. No hosted
  policy URL, publishing identity or support contact has been invented.

## Build and compatibility evidence

Artifacts: `/private/tmp/cod-release22.9vui24j5`.

- Cod / Debug simulator compilation passed, including the unit-test bundle and
  UI-test runner. The signed Debug device build and deep/strict signature check
  passed (`device22.log`): `com.josh.cod.store`, Cod Test, 1.0 (22). Cod / Release
  device archive passed (`archive22-final.log`); it is unsigned local validation,
  not a distribution/TestFlight archive.
  The development profiles include Jay and expire November 5 at approximately
  06:33 UTC (November 4, 10:33 PM Pacific); renew development signing for later
  installs/tests. This time limit is not an App Store distribution result.
- `Tools/verify-supported-source.sh` and the Release artifact audit passed.
  The audit checks the app and both extensions, including privacy resources,
  removed implementation markers, Release logging and AlarmKit weak-linking.
- The Release app and Share extension have minimum iOS 17.0; Controls has minimum
  iOS 18.0. AlarmKit is `LC_LOAD_WEAK_DYLIB` in app and Controls. ActivityKit's
  strong link in the app is expected: it predates the app's iOS 17 minimum.
  These are binary checks, not a substitute for launching on the minimum OS.
- Only iOS 26.3.1/26.5 simulator runtimes are installed. Xcode's official iOS
  18.5 download reported unavailable for both arm64-only and universal assets.
  iOS 17/18 launch acceptance remains open; no deployment target was raised.
- Xcode's first-launch component installation was incomplete. Its existing
  license check passed; installing its bundled components succeeded, and the
  setup check now passes. Its simulator testing service still failed to connect
  on existing and fresh simulators, before any test case ran.
- Developer-tools authorization was disabled. The owner approved enabling it;
  administrator authentication completed and `DevToolsSecurity -status` confirms
  enabled. Retrying after this change, including a fresh simulator and reboot,
  still produced the same pre-test service-connection failure.
- The installed toolchain reports Xcode 26.6 (17F113), on macOS 27.2. A normal
  attempt to open Xcode was rejected by LaunchServices with
  `kLSIncompatibleApplicationVersionErr` (-10664). This is an additional concrete
  toolchain compatibility failure; its precise relationship to the test-service
  error isn't proven. A working compatible Xcode/test-service installation is
  needed to finish unit/UI execution. No test case from this pass is counted as
  passed. Earlier build-21 results remain historical evidence only.

## iPad screenshot drafts

Four unmodified app-only PNGs were captured manually through the real simulator
at **2064 × 2752**, then visually inspected. They use authored sample text and
normal app settings; no personal images, accounts or permission grants were used.

- [Float list](screenshots/release-22/ipad-01-float.png)
- [Text reference](screenshots/release-22/ipad-02-text.png)
- [Timer](screenshots/release-22/ipad-03-timer.png)
- [Current Time](screenshots/release-22/ipad-04-current-time.png)

These are correctly sized screenshot candidates, not an uploaded listing or
proof of actual PiP picture quality. Final branding, screenshot selection and
a real-device floating example remain owner/release tasks. The separate
`SubmissionScreenshotTests` allows automated regeneration once XCTest runs.

## Remaining gates

Run the complete unit suite and affected sharing/layout UI flows. Check actual
image playback, replacement/cancellation and alarm sound timing on the phone.
Complete older-OS launch and physical accessibility/window-resizing checks.
Publish the owner-approved support/policy pages, validate distribution signing,
and run the submission-mode audit. App Review acceptance remains Apple's decision.
