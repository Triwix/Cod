# App Store release gates

Current candidate: **1.0 (23)**, Cod scheme, Debug/Release only. Public Release
display name is **Cod**; development device builds explicitly use **Cod Test**
and keep the separate `com.josh.cod.store` installation identity.
Unsupported automatic extension launch, private return/navigation, hidden
PiP controls, origin probes, and extension-side PiP experiments are removed.
There is no separate experimental/personal scheme or opt-in audit bypass.

## Remaining before submission

- Build 23 removes the verifier's ripgrep dependency, checks failed scans and
  missing/malformed binaries explicitly. The source guard also rejects missing
  tooling and scan errors; fourteen host-side audit regression tests pass.
  PiP rendering now makes one bounded standard-range frame;
  thumbnails explicitly use standard range. Source normalization/crop color
  policy is preserved. Debug/Release compilation and the hardened artifact audit
  pass. Six focused rendering tests compile, but the existing Apple test-service
  failure prevents execution. Build 23 was installed and launched on Jay
  (iPhone 16 Pro Max) on November 3; physical feature acceptance is open. See
  [evidence and limits](docs/verifier-rendering-23.md).
- Build 22 hardens image encoding and cancellation, moves image/share preparation
  and Settings storage enumeration off the UI thread, and disables routine
  Release diagnostics. Debug compilation, the Release archive and artifact checks
  pass, including a signed Debug device build. Unit/UI execution is blocked by
  Apple's simulator test service, even after repaired setup and approved developer
  authorization. LaunchServices also refuses Xcode as OS-incompatible. No new test
  run is counted as passed. Build 22 was installed and launched on Jay (iPhone
  16 Pro Max) on November 3; actual feature acceptance remains open. The original
  Cod app and data were not targeted.
  Four 2064 × 2752 iPad screenshot candidates are captured and visually inspected.
  See [reliability evidence and limits](docs/release-hardening-22.md).
- Build 21 refines the native UI while preserving features and supported entry
  points. Check the Home action hierarchy, short-card pinned previews, Library,
  optional Settings guidance and system-appearance launch confirmation on the
  phone. See the [redesign report](docs/redesign-21.md) for simulator evidence.
  All 218 unit tests and 16 relevant iPhone/iPad UI cases have passing results;
  Debug/Release packaging checks pass. Build 21 was installed and launched on the
  iPhone on November 2; owner review and physical feature acceptance remain open.
- Build 20 fixes fresh external-image playback cleanup ending its own request.
  Retest image Share/Shortcut/explicit document input on the phone, including
  cold/warm launches, cancellation and retry. The signed unit suite passes all
  218 tests; four relevant sharing-flow UI tests, the signed Debug build and
  local Release archive audit passed. These do not establish visible phone PiP
  or distribution readiness. See the [audit follow-up](docs/audit-follow-up-20.md).
- Privacy/support hosting, publishing identity and contact details are deferred
  to the owner. `COD_PRIVACY_POLICY_URL` remains blank and the submission-mode
  audit correctly blocks submission until a real hosted policy is configured.
- Build 19 hardens storage and media preparation and fixes finite-playback
  end-seek positioning. Confirm saved-card updates, Library recovery and actual
  PiP seeking on the phone. [Hardening notes](docs/hardening-19.md) record 213
  unit tests, affected UI checks and simulator-only performance measurements;
  they do not establish device memory/energy or App Review acceptance.
- Build 18 adds optional first-run guidance and import recovery. The introduction
  can be skipped, reopened in Settings and used to add the existing signed Share
  Shortcut. It doesn't block incoming content or request permissions up front.
  Confirm it and cloud-only import cancellation on the phone. See
  [release polish](docs/release-polish-18.md) and
  [submission preparation](docs/submission-package-18.md); metadata still needs
  owner approval, approved branding, hosted contacts/policy and actual screenshots.
- Build 17 consolidates Text/photo recognition/Teleprompter into one editor and
  makes PDF scrolling an inline toggle with one-row page selection. Confirm
  mode switching, photo layout and saved-script editing on the phone. See
  [layout notes](docs/layout-17.md) for verification and compatibility.
- Build 16 adds editable recognized-text cards, named source/preset saving,
  reference-specific Shortcuts/widgets/controls, finite image/PDF scrolling,
  spatial video cropping, GIF video conversion and timed prompter layout.
  Complete the physical checks in the [MVP checklist](MVP_CHECKLIST.md);
  [feature notes](docs/features-16.md) separate automated evidence from pending
  phone acceptance. The Widget extension now shares the app's provisioned App
  Group; validate it again in the final distribution archive.
- Basic Choose Photo and Share Shortcut floating were confirmed by the user on
  Cod Test 1.0 (7), including switching apps. Complete extended physical-device
  checks for repeat/replacement, early restore, resizing, and background playback.
  Back Tap, Lock Screen and Action Button setup must be confirmed by the user.
- Build 8's text/PDF and live tools were exercised by the owner on an iPhone.
  Build 9 merges all choices into Float, adds custom color selectors, sample
  script text, direct stopwatch pause, Current Time controls and crop zoom/pan.
  Retest native resize, restore, early close and replacement with an image.
- Build 10 adds compact explicit Float/Crop actions, sample placeholders and Clear,
  top-of-editor controls, centered words mode, video imports and library favorites.
  Verify the new video sound/seek/restore path and favorites on the phone.
- Build 11 combines Photos/video selection and visual-file importing, pins rounded
  previews above settings, adds smooth circular progress, stopwatch hundredths,
  the timer close-policy switch, stable Favorites ordering and explicit clear-all.
  Test both timer-close choices and audible alarm timing on the phone. Native
  countdown deadline reconciliation improves display synchronization, but doesn't
  establish or guarantee acoustic delivery latency.
- Build 12 adds default-on video repeat (changeable during playback), direct
  numeric Pomodoro entry and fitted-image text-preview clipping. Test native
  video repeat boundaries, pause, seeking, repeat Off and replacement on the
  phone. Dedicated-album saving still defaults off; existing choices are preserved.
- Build 13 labels all tool/document previews, clarifies the text sample, removes
  duplicate Home recents, and presents native colors without dimming the exposed
  preview. Check live color changes and dismissal on the phone. No entry-point,
  media-playback, permission or library-retention behavior was changed.
- Build 14 adds a default-on configurable prompter countdown and genuine finite
  seekable playback, Current Time line/abbreviation/font-size options, and typed
  PDF page entry. Confirm native prompter rewind, replay, countdown and replacement
  on the phone. Manual opening also receives queued shares when notification
  handoff is configured; unavailable notification delivery gets an explicit
  saved-image/manual-open message. Retest cropped/whole-image notifications and
  manual recovery with system notifications disabled. Optional first-run guidance
  was added in build 18.
- Build 15 makes time-zone search visible immediately, adds an updating setup
  clock preview and a conditional reset for all three clock sizes. System is
  the default appearance preset; fixed/custom colors are still available. Check
  live device appearance changes and prompter scrolling on the phone: scrolling
  now targets 60 fps with cached visible-glyph layout and deadline-based pacing.
  The finite timeline, initial countdown and native rewind remain intact.
- Build 9 adds optional timer alarms on iOS 26+ using AlarmKit. Confirm the
  permission allow/deny paths, actual sound while locked/under Focus, native
  alarm dismissal, pause/resume/restart and cancellation after relaunch on a
  physical phone. No alarm is scheduled by default. Keep alarm running when PiP closes
  defaults on; Off cancels the timer/alarm on close. Float exposes cancel actions. Build 10 changes
  alarms to native duration countdowns with a widget, delays counting until PiP
  opens, and guards completion/interruption from cancelling the sound. Specifically
  retest 2-second and longer timers while music plays and while Cod is foreground.
- Confirm wide-window/landscape behavior on an iPad before universal release.
  The simulator's windowed mode retained a portrait viewport, so that specific
  geometry check is explicitly skipped, not counted as passed. The iPhone's
  stricter landscape check passed.
- Confirm notification behavior on the target OS; Focus, banners, summaries,
  and permission changes can affect delivery. Manual opening remains fallback.
- Obtain Apple Developer Program membership and the required distribution/App
  Group provisioning, create the App Store Connect record, and validate a signed
  Release archive/TestFlight build. Development installation is not submission.
- Host the privacy policy, configure `COD_PRIVACY_POLICY_URL` in project.yml,
  and verify it inside the built app. Run the artifact audit with `--submission`.
- Complete App Store privacy answers, support URL, age/content rating, export
  compliance, listing text and device screenshots. Review the prepared
  [submission draft](docs/app-store-draft.md); replace owner placeholders.
- Confirm the final publishing team/bundle/App Group before signing. Bundled
  signed Shortcuts refer to an exact app/team; if either changes, regenerate
  and sign matching workflows with approval. The installer and release audit
  reject mismatched package metadata instead of offering a broken workflow.
- Provide clear reviewer instructions for Shortcuts/controls and actual PiP.
  Explain the still-image video implementation honestly. Only Apple can decide
  whether its use fits review requirements; public APIs are not preapproval.
  Also disclose the non-video reference/time/prompt content rendered as live
  video frames. The known history of timer-PiP review disputes still applies.

## Scope completed in the polish pass

- Float-first Home, ready-made Share Shortcut installer, dismissible setup tip,
  clearer guide and fallback instructions, and direct floating from Library.
- Large-text/landscape support for the home and launch views, clearer accessible
  labels, higher-contrast filled buttons and readable error toasts.
- Confirmation before clearing the library or reducing retention. Clear Recent
  History and retention preserve favorites; Delete Everything, Including Favorites
  explicitly removes them and saved cards/presets. Originals, preferences and
  pending shares aren't removed.
- Corrected decoded-image cache accounting. In-app pins were retired in build 10.
- Removed unused routes, store methods and Share-extension source memberships;
  retained legacy decoding/inbox data for compatibility, not new features.
- Idle PiP prewarm is released on backgrounding without an active float.
- Explicit privacy manifests and local source/Release packaging checks. These
  are not a substitute for distribution validation or App Review.

Local video imports are included in build 10, with native video playback separate
from generated still-image/live-tool frames. Photos and Files sources are copied;
Cod never deletes the original media. Imports are limited to 500 MB per video.
Latest refinements are in [build-10 notes](docs/floating-polish-10.md);
[build-9 notes](docs/floating-polish-9.md) and build-8 details are in
[floating-tools notes](docs/floating-tools-8.md).
See the [build-7 handoff](docs/release-polish-7.md) for verification evidence,
development artifacts and the final phone acceptance list.

## Verification commands

Generate with `xcodegen generate`; test the **Cod** and **Cod Launch Tests**
schemes against an installed simulator. Build **Cod / Release** for the device
or archive, then run:

```sh
zsh Tools/verify-supported-source.sh
zsh Tools/verify-store-build.sh /absolute/path/to/Cod.app
zsh Tools/verify-store-build.sh /absolute/path/to/Cod.app --submission
```

The final command intentionally fails until a real HTTPS privacy-policy URL
is configured. Verify distribution signing and all three embedded bundle
entitlements separately. These checks do not establish review acceptance.

Older release/test narratives live in Git history. Research documents kept in
the repository are historical and must not be used to restore removed tricks.
