# MVP checklist

Current candidate **Cod Test 1.0 (26)**. Debug/Release builds, local artifact
checks and all 248 signed iOS unit tests pass with Xcode 27.2. The owner confirmed
that double-tapping a drawn crop floats the correct selection on the iPhone.
Complete the remaining device checks on Cod Test.

Use only documented Apple APIs. The Share extension cannot launch Cod directly;
fast floating uses the installed Shortcut or system controls. Automatic return
to the previous app is not supported. Public APIs do not guarantee approval.

Details: [release gates](APP_STORE_RELEASE.md),
[latest UI refinement](docs/redesign-21.md),
[latest reliability pass](docs/release-hardening-22.md),
[verifier/rendering evidence](docs/verifier-rendering-23.md),
[crop/audit evidence](docs/crop-audit-24.md),
[crop interaction follow-up](docs/crop-follow-up-25.md),
[drag lifecycle follow-up](docs/crop-lifecycle-26.md),
[phone/toolchain evidence](docs/device-toolchain-26.md),
[submission draft](docs/app-store-draft.md).

Research: [feature candidates](docs/feature-candidates.md). Selected items
1, 2, 3, 4, 6, 10, 11 and 12 are implemented; the others remain unapproved ideas.

## Open items

1. Finish build-26 crop gesture acceptance on the phone. Collapse and redraw
   passed in the simulator. Check off-screen drags, resize boundaries and
   interruption by the system or a pinch without a stuck magnifier.
2. Continue reviewing the installed build-26 candidate on the phone and confirm the
   Share/Shortcut/document request-lifecycle fix carried forward from build 20.
   Refresh the expired development provisioning before the next install.
   Complete iPhone PiP reliability checks: cold/warm launch, image replacement,
   early taps/restore, close/reopen, resizing, rotation, lock/unlock, music mixing
   and another app already using PiP. Verify prompter smoothness, native rewind,
   pause, countdown and replay. Simulator PiP is unavailable or shows black tool
   pictures; use the phone for actual floating-picture acceptance.
   Include rotated, transparent and wide-color still images after the temporary
   PiP-rendering change; confirm originals/crops retain their existing behavior.
3. Confirm physical-device setup and use of Back Tap, Control Center, Lock Screen,
   Action Button and notification handoff, including permission denial and Focus.
   Check the new saved-card/favorite Shortcut, Home Screen widget and configurable
   control, including changed/deleted references and a locked phone.
4. Investigate delayed timer-alarm sound on the phone. Verify short and longer
   timers with music, Cod foreground/background and the screen locked; check
   alarm permission, pause/resume/restart, cancellation and both PiP-close settings.
5. Verify video sound, repeat boundaries, Repeat Off, pause/seek, restore and
   replacement on the phone, plus GIF motion/timing and video-region crop/reset.
6. Finish phone acceptance of text/teleprompter, PDF cropping, time tools, numeric
   entry, Preview labels, live colors and Library favorites/clear-history behavior.
   Include image-to-text accuracy/original comparison, named-card/preset editing,
   finite image/PDF scrolling, and timed prompter guide/margins/line spacing.
   Check the unified Text/photo/Teleprompter flow, inline PDF toggle and optional
   first-run introduction on the phone.
   Retest end-of-script seeking and Library save/reopen behavior after build 19.
7. Finish real-provider import recovery checks: denied/limited Photos access,
   cloud-only/slow media and interrupted downloads. Local corrupt/unsupported
   media, cancelled pickers and stale-result rejection have automated coverage.
8. Finish iPad window-resizing and assistive-technology acceptance before making
   full-app accessibility claims. iPad landscape/dark, PDF and largest-text
   introduction checks have passed in the simulator.
   Launch on iOS 17/18 when a compatible runtime/device is available. Xcode did
   not offer the 17.5 or 18.5 runtimes. The Release binaries pass AlarmKit
   weak-linking and minimum OS checks.
9. Set up Apple Developer Program membership and distribution signing. Confirm
   the publishing team, bundle IDs and App Groups; regenerate signed Shortcuts
   if their app/team identity changes.
10. Owner: supply the publishing identity and support contact, host the privacy
    and support pages, configure `COD_PRIVACY_POLICY_URL` and verify the link in
    the built app. Deferred at the owner's request; it remains a submission gate.
11. Approve the final name and App Store listing; select the screenshot drafts,
    capture a physical-device PiP example and provide the support URL, privacy
    answers, age rating, export compliance and reviewer instructions. Explain generated
    still-image/live-tool PiP honestly.
12. Validate a signed Release archive/TestFlight build, embedded entitlements and
    installed Shortcuts; rerun unit/UI tests and the submission-mode artifact audit.
13. Submit for App Review and address any review feedback before publishing.

## Completed items

- Installed/launched Cod Test 1.0 (26) on Jay (iPhone 16 Pro Max); the owner
  confirmed double-tapping a drawn crop floats the correct crop.
- Verified Xcode 27.2 restores the test runner. Passed 248 signed unit tests,
  19 iPhone and five iPad UI checks across reruns, and 16 verifier tests. Debug
  and the unsigned Release archive pass local checks.
  See [test evidence](docs/device-toolchain-26.md).
- Moved drag ownership from the conditional selection layer to the stable canvas;
  added automatic drag/pinch cancellation cleanup and recovery from collapsed or
  invalid crops. The dedicated collapse and redraw UI regression passes. See
  [build 26](docs/crop-lifecycle-26.md).
- Aligned double-tap/VoiceOver Float with the visible action list, removed the
  double-tap wait from outside single taps and shared the eight-pixel crop minimum
  across dragging/edge controls, preserving genuinely thin images. Nine host
  geometry/settings tests pass; simulator interaction evidence and limits are
  recorded in [build 25](docs/crop-follow-up-25.md).
- Added double-tap inside a selected image/PDF crop to perform Float through the
  existing action; the video editor retains Apply Crop. Added native pixel-edge
  steppers and VoiceOver actions, and explicit immediate/crop-first Back Tap
  setup guidance. Interactive gesture/phone acceptance remains open above.
- Added contrasting temporary PiP mattes for transparent artwork, enabled targeted
  concurrency and resolved exposed GIF/Live Text warnings, extended the source
  guard and added the OS-only non-exempt-encryption declaration/artifact gate.
  Seven host geometry and sixteen verifier tests pass; iOS execution is open.
- Removed the artifact verifier's ripgrep dependency, made scan errors/missing
  executables/malformed binaries fail explicitly and verified raw-byte marker
  scanning across the app and extensions. The source guard also rejects missing
  tooling and scan errors. Fourteen host-side regression tests pass.
- Added a single bounded standard-range PiP render and explicit standard-range
  thumbnails, preserving original-image normalization/cropping policy. Debug and
  Release builds plus the hardened artifact audit pass; six new rendering tests
  compile but execution remains blocked above. See [build 23](docs/verifier-rendering-23.md).
- Implemented bounded/cancellable image-video encoding, a completion-race fix,
  stale-safe background image preparation, background share encoding and
  asynchronous Settings storage calculation. Added 15 regression/decode tests;
  execution is the open gate above. Disabled routine Release logging and extended
  the binary audit to check logging markers and AlarmKit weak-linking.
- Prepared four unmodified, visually inspected 2064 × 2752 iPad screenshot drafts
  using authored sample content. Debug/Release builds and local source/artifact
  checks pass; these are not device playback or distribution acceptance.
- Applied the approved native UI refinement to Home, Library, Settings, the
  preview/editor headers, setup and launch confirmation: clearer Float actions,
  aligned neutral icons, consistent shapes/touch targets, shorter guidance and
  fitted pinned previews. Native typography, content settings and features remain.
  Verification and screenshots are in [redesign notes](docs/redesign-21.md).
  Passed all 218 unit tests and 16 relevant simulator UI checks across iPhone
  and iPad, plus signed Debug, Release archive and local source/artifact checks.
- Fixed fresh image-playback cleanup ending the new request before its result.
  Reproduced the bug before the fix and passed five deterministic lifecycle
  checks plus all 218 signed unit tests and four sharing-flow UI tests. Signed
  Debug, Release archive and local source/artifact checks passed. The document
  menu used its permitted Share/manual-open fallback in this simulator run;
  actual phone PiP and submission-mode validation remain open above.
- Removed private APIs, direct Share-extension app launching, automatic app
  return and hidden PiP-control experiments; retained the Cod Debug/Release scheme.
- Implemented supported Share/Back Tap Shortcuts, App Intents, system controls,
  optional tapped notifications and manual-open fallback.
- Confirmed basic Choose Photo and Share Shortcut image floating on the phone.
- Combined floating choices into one sectioned Float tab with compact image and
  screenshot actions, clipboard paste and image/video/PDF file imports.
- Added text references, scrolling and word-group teleprompter modes, sample
  placeholders, Clear actions, readability controls and PDF crop zoom/pan.
- Added Current Time, pausable stopwatch with optional hundredths, remembered
  hour/minute/second timer wheels and directly editable Pomodoro values.
- Implemented optional AlarmKit alarms, timer-close behavior and smooth circular
  progress; audible timing remains an open acceptance issue above.
- Added native video PiP with sound control and default-on repeat.
- Added local animated-GIF video conversion and non-destructive video-region
  cropping/reset, retaining sound and repeat controls.
- Added editable image-to-text cards with original comparison, named saved cards
  and source/settings presets independent of History.
- Added saved-card/favorite App Intents, a configurable Home Screen widget and
  iOS 18+ system control; no direct Share-extension app launching.
- Added finite image/PDF-page-range auto-scroll and teleprompter reading guides,
  margins, line spacing and target-duration pacing separate from countdown.
- Added configurable prompter countdown and finite seekable script playback,
  Current Time line/size options, typed PDF pages and supported-route explanations.
- Added visible time-zone search, a ticking clock preview, conditional size reset,
  default System appearance and smoother cached-layout scrolling with 60-fps pacing.
- Added stable Library favorites, direct history enabling and explicit choices
  for clearing recent history or deleting everything; removed in-app pins.
- Kept dedicated-album saving off by default while preserving saved preferences.
- Added pinned rounded previews, Preview labels and undimmed live color selection;
  clarified sample text and removed duplicate Home recents.
- Consolidated text, photo recognition and teleprompter into one editor with
  optional playback settings. Made PDF page controls one row and scrolling an
  inline toggle with automatic preparation and conditional crop controls.
- Added an optional first-run introduction, with Skip/Not now, replay in Settings,
  the ready-made Share Shortcut installer and clear explanations of notification
  and system-control routes. It never gates an incoming image or requires setup.
- Added visible, cancellable import progress and persistent Home import errors;
  cancelled pickers are not failures. Nil Photos results and corrupt images get
  recovery messages, and cancelled/older loads cannot replace newer input.
- Enlarged color-selector touch targets, clarified text-editor accessibility
  guidance and removed an unused Home row helper. Added import/setup regression tests.
- Prepared updated listing copy, concise reviewer notes, privacy wording and an
  owner-approval/screenshot plan in [submission-package-18](docs/submission-package-18.md).
  No account answers, public hosting or submission has been performed.
- Passed 193 unit tests on iPhone and iPad simulators, relevant setup/import/editor
  UI checks, cold/warm Share Shortcut delivery, signed Debug and Release builds,
  signature verification and source/Release artifact audits for build 18.
- Hardened saved-reference updates and failed saves, protected damaged indexes,
  added non-destructive Library reload and visible storage warnings, and cleaned
  recognized orphaned media only on explicit full deletion or process-start
  temporary cleanup. Originals and unknown files are not swept.
- Bounded thumbnail fallback and image decoding, aligned the 50 MB import limit,
  streamed PDF page preparation, avoided unnecessary favorite-widget reloads,
  and bounded/excluded local diagnostic logs from backups.
- Fixed an end-of-script clock-positioning race. Passed 213 unit tests plus relevant
  media, saved-card update, PDF, Library and cold/warm Share Shortcut UI checks.
  Debug/Release builds, signature and source/artifact audits passed for build 19.
  PDF memory/time measurements and remaining device limits are recorded in
  [hardening notes](docs/hardening-19.md), not counted as phone playback acceptance.
- Passed 182 unit tests, relevant simulator UI checks, Debug/Release builds and
  local source/Release artifact audits for build 17. Build 16's features received
  positive owner feedback; build 17's phone check remains open. Original Cod
  app/data remain untouched.
- Researched competing apps, user requests and documented Apple capabilities;
  recorded 14 feature candidates with selected implementation scope separated
  from unapproved ideas and the remaining MVP release gates.
