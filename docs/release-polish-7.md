# Cod 1.0 (7) — release-polish handoff

October 18, 2026. Local development candidate, not submitted to Apple.

## What changed

The Float tab now puts Choose Photo and a ready-made, preconfigured Share
Shortcut installer first. Users confirm adding the Shortcut in Apple's UI;
Cod cannot silently install it. Hiding the setup tip does not remove the guide
or installer. No private app-opening or automatic-return behavior was restored.

The guide prioritizes the Share Shortcut, then Back Tap and system controls,
with the native Share-app-icon notification/manual flow clearly marked as a
fallback. Settings distinguish system PiP from pins and the in-app action bar.
Library images have a direct Float action.

Home/setup and the floating launch screen handle scrolling and larger text.
Filled buttons use a darker blue with white text, while dark-mode links retain
the brighter accent. Relevant labels, touch targets, errors and toast timing
were improved. This is not a claim of full-app accessibility conformance; the
gesture crop editor and pin controls still need dedicated assistive-tech QA.

In-app pin close/resize controls now sit inside their hit area, with 44pt
targets and distinct accessible labels. Closing a pin must not activate the
setting underneath it. The resize handle also supports accessibility adjustment.
These changes do not alter native PiP controls.

Clearing history and reducing retention now ask for confirmation. Cancelling
must preserve history. These controls do not delete Photos, pending shares or
pins. Existing preferences and legacy inbox images remain intact.

Unused routes, store methods, view dependencies and Share-extension source
memberships were removed. Legacy decoding for retired action preferences and
the old inbox reader remain intentionally, so an update does not discard data.
Final-nil Photos requests now finish with an actionable error instead of leaving
a loading state pending. Idle prewarm playback stops on backgrounding without
an active float.

History image caching now accounts for decoded pixel memory on both reads and
new saves, rather than counting compressed files or zero-cost new entries.
A count cap supplements the cache's memory budget. This reduces memory pressure;
it is not a hard bound on all live views or the app's total memory use.

Shortcut package metadata guards against offering a workflow tied to the wrong
app/team after a future signing-identity change. The existing signed workflows
were not modified, re-signed or uploaded during this pass.

## Verification and artifacts

- Xcode 26.6 / iOS 26.5 SDK; deployment target iOS 17, controls iOS 18.
- All 70 unit tests passed on the iPad mini simulator. Coverage includes real
  encoded image frames, request ownership/expiry, preferences, image input and
  Shortcut identity. These checks do not establish visible PiP on an iPhone.
- The complete iPhone native UI suite passed all 14 tests with no failures or
  skips: Control Center launch, document opening, manual Share preparation,
  crop/cancel without replay, action-bar scope, history-confirmation cancellation
  and Library Float, three notification cases, Home/setup appearance checks,
  and both signed Shortcut installers. The Share Shortcut delivered the actual
  300×200 cold and 148×92 warm fixtures without manual Cod activation.
- A stricter follow-up also passed the iPhone landscape check using actual
  main-window geometry, not just a requested device orientation. Debug-only
  simulator layout hooks are excluded from Release and checked by the audit.
- The iPad simulator delivered both cold/warm Share Shortcut images correctly
  and passed history cancellation/Library Float and Home/large-text checks.
  Final tablet run: four passed, one skipped, zero failures.
  Its current windowing mode rejects programmatic interface-orientation changes
  and retains a portrait viewport. The landscape test explicitly skips that
  configuration; landscape/window-resize acceptance on iPad remains open rather
  than being counted as verified.
- Debug simulator builds and Release device/archive builds succeeded.
- Source regression scan and Release artifact scan passed for the app and both
  extensions. Development signature passed deep/strict verification.
- Public Release archive has display name Cod, version 1.0 (7), matching bundle
  metadata, privacy manifests, signed workflow resources and a 1024px opaque
  app icon. The phone build deliberately retains the Cod Test display name.
- The stricter submission audit fails as intended because the real hosted
  privacy-policy URL is still blank. Distribution signing and App Store Connect
  validation have not been performed.
- Cod Test 1.0 (7) was installed on the paired iPhone. The installed app record
  confirms that version. The original Cod app was not installed over or removed;
  no user-installed phone Shortcuts were changed.
- The user confirmed both **Choose Photo** and **Photos → Share → the existing
  Float with Cod Shortcut** show the correct image and keep it floating after
  switching apps on this final build.

Local build/test artifacts are under `/private/tmp/cod-release-polish7.znFOCg`:
`units-candidate7.xcresult`, `phone-suite-ready7.xcresult`, `Cod-final-source7.xcarchive`,
and their logs. These are temporary development artifacts, not distribution
packages. Simulator screenshots were visually reviewed for normal, dark and
accessibility text appearances. Simulator workflow tests use disposable
fixtures and Allow Once for system image-sharing permission.

Additional results: `phone-landscape-final.xcresult`,
`ipad-share-verified.xcresult` and `ipad-final-qa.xcresult`. The simulator-only
geometry request uses Apple's documented
[own-scene layout API](https://developer.apple.com/documentation/uikit/uiwindowscene/requestgeometryupdate(_:errorhandler:));
it is not a production rotation setting, private API or launch workaround.

## Final iPhone acceptance

Choose Photo and the existing Share Shortcut are confirmed by the user on
Cod Test 1.0 (7). Extended acceptance still includes replacement of an active
float, restoring/closing PiP, and music continuing.
Also check One tap float off → crop → Float and actual native resize gestures.
Confirm hardware-specific Back Tap / Action Button / Lock Screen configuration
on the intended devices. Include iPad window resizing/landscape before shipping
universal tablet support. A simulator cannot complete hardware acceptance.

## Owner/submission gates

1. Choose the public publishing identity, support contact/URL, price and
   storefronts; approve the policy and listing drafts.
2. Host the policy and configure its HTTPS URL in `project.yml`.
3. Enroll in the Developer Program when ready, confirm team, identifiers and
   App Group provisioning, then validate a distribution archive/TestFlight build.
   Regenerate/sign the Shortcuts if the publishing team or bundle changes.
4. Complete App Privacy, age-rating and export-compliance answers, and capture
   final screenshots using owned content and actual physical-device PiP.
5. Submit with honest reviewer instructions describing still-image-to-looping-
   video PiP. Public APIs do not preapprove that use case; Apple decides.

See [release gates](../APP_STORE_RELEASE.md),
[submission draft](app-store-draft.md) and [policy draft](../PRIVACY_POLICY.md).
No enrollment, payment, remote policy publication, GitHub push or App Store
upload was performed as part of this pass.
