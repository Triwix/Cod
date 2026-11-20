# MVP checklist

Current candidate **Cod Test 1.0 (36)**, iPhone-only. On November 13, 2026 the
Debug build, all 294 unit tests (3 StoreKit tests skip on the simulator), the
Build31/Build32/Release18 UI tests, the unsigned Release build, both verifiers
and the verifier's own 17 tests passed with Xcode 27.2. The
full UI suite last ran on build 30; native PiP checks skip on these simulators
and need the phone. The owner confirmed on build 26 that double-tapping a drawn
crop floats the correct selection on the iPhone.

Use only documented Apple APIs. The Share extension cannot launch Cod directly;
fast floating uses the installed Shortcuts or system controls. Automatic return
to the previous app is not supported. Public APIs do not guarantee approval.

Details: [release gates](APP_STORE_RELEASE.md),
[build 34 audit fixes](docs/audit-fixes-34.md),
[build 33 audit fixes](docs/audit-fixes-33.md),
[Cod Pro](docs/pro-32.md),
[Recents, shapes and System Monitor](docs/recents-shapes-31.md),
[UI test repair](docs/ui-tests-30.md),
[tools and Float tab](docs/floathing-parity-29.md),
[crop Shortcut and iPhone-only](docs/crop-shortcut-28.md),
[share resolution](docs/share-resolution-27.md),
[phone/toolchain evidence](docs/device-toolchain-26.md),
[submission draft](docs/app-store-draft.md).

Research: [feature candidates](docs/feature-candidates.md). Selected items
1, 2, 3, 4, 6, 10, 11 and 12 are implemented; the others remain unapproved ideas.

## Audit fixes for build 34 (done)

From the November 13, 2026 audit of build 33. These are code tasks for a
Claude Opus 5.5 session. Follow [AGENTS.md](AGENTS.md): edit `project.yml`, not
the Xcode project; bump `CURRENT_PROJECT_VERSION` to 34; add a
`docs/<topic>-34.md` report and the README/APP_STORE_RELEASE.md entries; then
run the unit tests, the relevant UI tests and both verifiers on a Release build.
Tick each box when it is done and verified.

Fix before submitting:

- [x] **A1. Paywall selects the wrong plan for a subscriber.**
  `ProView` starts with `plan = .yearly` and only changes it on a tap
  ([ProView.swift:13](Cod/Views/Pro/ProView.swift)). A subscriber who taps
  Upgrade to Lifetime in Settings sees only the Lifetime row, unselected, while
  the button says Subscribe, shows the yearly disclosure and would buy Yearly.
  Select Lifetime whenever a subscription is active, and never let the button
  act on a plan that isn't in `availablePlans`. Move the selection rule into a
  testable function and add a unit test. Found by reading the code; StoreKit
  tests skip on the simulator, so confirm on the phone with the local StoreKit
  file.
  Done: `ProPlan.offered` and `ProPlan.selection` decide the plan; a subscriber starts on Lifetime and the button can only buy a shown plan. Unit-tested; confirm on the phone.
- [x] **A2. Text shared from the Share sheet floats without Pro.**
  Text cards are Pro, and the Float Text Shortcut and the in-app editor are
  gated. The Share extension renders shared text to an image
  ([ShareViewController.swift:107](CodShare/ShareViewController.swift)) and
  hands it over as an ordinary image, which `receiveQuickShare` floats with no
  check. Ask the owner which way to go before coding: gate it (mark the
  handoff as text and call `unlocks(.textCards)` in the app; the extension
  can't read StoreKit state), or keep it free and add it to the "Always free"
  copy in ProView, Settings and the listing.
  Done: the owner chose Pro. The handoff marks shared text (`isText`), and the app asks for Pro before floating or cropping it. Shared images stay free.

Should fix:

- [x] **A3. `verify-supported-source.sh` needs ripgrep, which isn't installed.**
  Switch it to `/usr/bin/grep` like the store verifier, keeping the
  distinction between "no match" and a failed scan. Update
  `Tools/test-verify-store-build.py` if it covers this script.
  Done: `/usr/bin/grep -rnIE`, still failing on unreadable input. The verifier tests now check it runs with stock tools only.
- [x] **A4. Neither verifier covers the Safari extension.** Add `CodSafari` to
  the source scan and `CodSafari.appex` (bundle ID
  `com.josh.cod.store.safari`) to the binary and privacy-manifest loop in
  `verify-store-build.sh`. It has no `CodShareLaunchPolicy` key, so exempt it
  from that check as CodControls is.
  Done: CodSafari is in the source scan (both rules) and the binary/privacy loop, with its own manifest and content-script check.
- [x] **A5. In-app Privacy screen is behind the policy.**
  [PrivacyView.swift](Cod/Views/Settings/PrivacyView.swift) doesn't mention
  the Speedometer's location use, System Monitor readings, Cod Pro purchases
  or the Safari extension. Bring it in line with `PRIVACY_POLICY.md`.
  Done: the Privacy screen covers the Speedometer, System Monitor, the Safari extension and Cod Pro purchases; the policy gained a purchases paragraph.
- [x] **A6. "7 days free" is hard-coded** in ProView (badge, button,
  disclosure) and Settings. Derive the length from the product's
  `subscription.introductoryOffer.period` so it follows App Store Connect.
  Done: `TrialLength` comes from the product's introductory offer (weeks read as days).
- [x] **A7. Trial eligibility is computed before products load.**
  `ProStore.refresh()` runs at launch with no products, so Settings shows
  "Try it free for 7 days" only after the paywall has been opened once. Load
  products at start, or recompute eligibility when they arrive.
  Done: `ProStore.start()` loads products after the entitlement refresh.

Lower priority:

- [x] **A8. Main-thread file reads.** `VisualFileImport.open` is `@MainActor`
  and reads and decodes PDFs (up to 40 MB) and images (up to 50 MB) there. Move
  the read and decode off the main actor; keep the cancellation and
  stale-input checks.
  Done: `VisualFileImport.open` is no longer main-actor isolated, and picked photos decode off the main thread.
- [x] **A9. Safari content script cost.** It runs on every page and frame with
  a whole-document `MutationObserver` and a 1.5-second timer
  ([content.js](CodSafari/Resources/content.js)). Stop the timer and observer
  work when the page has no video or the button is switched off. Ask the owner
  whether to keep overriding a site's `disablePictureInPicture`.
  Done: no timer, observer or scan work when Float is off or the page has no videos. The owner chose to keep overriding `disablePictureInPicture` on an explicit tap.
- [x] **A10. CodControls carries the keychain access group** it never uses.
  Give it its own entitlements file with only the App Group.
  Done: `CodControls/CodControls.entitlements` has only the App Group. Check it in the signed build.
- [x] **A11. Compiler warning** at
  [PiPPinController.swift:371](Cod/Pins/PiPPinController.swift): implicit
  strong capture of `self` in the video float task. Don't change the
  still-image `AVPlayerLayer` path.
  Done: the video task captures `self` weakly; the still-image path is unchanged.
- [x] **A12. `docs/launch-plan-1.0.md` is untracked but not ignored**, and
  the repository is public. Add it to `.gitignore` so `git add -A` can't
  publish it.
  Done: added to `.gitignore`.

Owner decisions raised by the audit (not for Opus):

- Shared text from the Share sheet is Pro, and the Safari extension keeps
  overriding a site's Picture in Picture opt-out on an explicit tap (both
  decided November 13).
- Lifetime's "works with Family Sharing" text is only true if Family Sharing
  is turned on for that product in App Store Connect.
- The public repository's history and `RETURN_RESEARCH.md` / `FAST_SHARE.md`
  still show the removed private-API experiments. Decide whether to keep them
  public.

## Open items

1. Finish crop gesture acceptance on the phone (open since build 26). Collapse
   and redraw passed in the simulator. Check off-screen drags, resize
   boundaries and interruption by the system or a pinch without a stuck
   magnifier. Check a sharp Back Tap crop at native resolution and the
   Screenshot and Crop Shortcut (builds 27 and 28).
2. Install build 33 or later on the phone and complete iPhone PiP reliability
   checks: cold/warm launch, image replacement, early taps/restore,
   close/reopen, resizing, rotation, lock/unlock, music mixing and another app
   already using PiP. Verify prompter smoothness, native rewind, pause,
   countdown and replay. The four UI tests that skip on the simulator are
   native PiP checks (Current Time controls, keep-running timer close, video
   repeat, teleprompter rewind); run them here. Include rotated, transparent
   and wide-color still images.
3. Confirm physical-device setup and use of Back Tap, Control Center, Lock
   Screen, Action Button and notification handoff, including permission denial
   and Focus. Check the "open Cod" ready screen after sharing to the Cod icon,
   the saved-card/starred Shortcut, Home Screen widget and configurable
   control, including changed/deleted references and a locked phone.
4. Investigate delayed timer-alarm sound on the phone. Verify short and longer
   timers with music, Cod foreground/background and the screen locked; check
   alarm permission, pause/resume/restart, cancellation and both PiP-close
   settings.
5. Verify video sound, repeat boundaries, Repeat Off, pause/seek, restore and
   replacement on the phone, plus GIF motion/timing and video-region crop/reset.
6. Finish phone acceptance of text/teleprompter (Scroll, Words and Lines),
   PDF cropping and Flip Pages, time tools, numeric entry, Preview labels, live
   colors and Recents stars/clear behavior. Include image-to-text accuracy and
   original comparison, named-card/preset editing, finite image/PDF scrolling,
   and timed prompter guide/margins/line spacing.
7. Phone acceptance of the build 29–31 tools: Countdown To, World Clock, Image
   Set skipping, window shapes, System Monitor readings (battery, thermal
   state, network rates, CPU, memory, storage), the Speedometer with its
   location prompt and background indicator, and the Safari video extension.
   Measure battery cost for System Monitor and Speedometer.
8. Cod Pro on the phone: buy, restore, trial, pending and refund with the
   local StoreKit file from Xcode, then in the sandbox. Check every gate on the
   free tier, including widgets, controls and Shortcuts, and the Lifetime
   upgrade from an active subscription (after A1).
9. Finish real-provider import recovery checks: denied/limited Photos access,
   cloud-only/slow media and interrupted downloads. Local corrupt/unsupported
   media, cancelled pickers and stale-result rejection have automated coverage.
10. Compatibility: 1.0 is iPhone-only, but App Review may run it on an iPad in
    compatibility mode, so launch it there once and float an image. Launch on
    iOS 17/18 when a runtime or device is available (Xcode 27.2 doesn't offer
    them), or raise the minimum. Do a VoiceOver pass on the crop editor before
    making accessibility claims.
11. Owner: decide the App Store name before creating the App Store Connect
    record. Decided 2026-11-20: the Speedometer keeps background location in
    1.0 (if App Review rejects it under 2.5.4, pull the Speedometer to 1.1
    rather than ship one that freezes), and Cod accepts a 16+ rating to keep
    the in-app browser for Video from a Link.
12. Confirm distribution signing for the publishing team, bundle IDs and App
    Groups; regenerate the three signed Shortcuts if the app/team identity
    changes.
13. Owner: supply the support contact, host the privacy and support pages,
    configure `COD_PRIVACY_POLICY_URL` and verify the link in the built app.
    Until then the paywall has no Privacy Policy link and
    `verify-store-build.sh --submission` fails. Deferred at the owner's
    request; it remains a submission gate.
14. App Store Connect: create `cod.pro.yearly`, `cod.pro.monthly` (7-day
    trial) and `cod.pro.lifetime` with Family Sharing, set prices, and submit
    them with the app. Add the Terms of Use link to the description.
15. Approve the App Store listing; capture real phone screenshots including a
    PiP example (the earlier drafts were iPad), and provide the support URL,
    privacy answers (including location), age rating, export compliance and
    reviewer instructions. Explain generated still-image/live-tool PiP, the
    PiP host view, background location and the Safari extension's
    all-websites access honestly.
16. Validate a signed Release archive/TestFlight build, embedded entitlements
    and installed Shortcuts; rerun unit/UI tests and the submission-mode
    artifact audit.
17. Submit for App Review and address any review feedback before publishing.

## Completed items

- Build 36: Recents fixes (no light/dark duplicates; image sets, PDF pages and
  documents listed), video speed and sections, Video from a Link, Office/iWork
  and text documents. 307 unit tests; full UI suite 83 tests (4 PiP skips, the
  expected iPad failure). See [build 36](docs/features-36.md).

- Build 35: swipeable shape preview in the tool, teleprompter and PDF Flip
  Pages editors (the Window row stays), and no screenshot error when Cod checks
  on its own. Build 34's design is unchanged. See [build 35](docs/shape-preview-35.md).
- Build 34: fixed the build-33 audit items A1–A12: the Pro screen's plan
  choice for subscribers, Pro for shared text, the trial length from the App
  Store offer, stock-tool and Safari coverage in both verifiers, the Privacy
  screen, off-main file reads, a lighter Safari script and controls-only
  entitlements. 294 unit tests pass. See [build 34](docs/audit-fixes-34.md).

- Build 33: OCR follows the device's languages, "Temperature" became "Thermal
  State", Speedometer GPS accuracy was lowered, and the reviewer notes explain
  the PiP host view and background location. 289 unit tests pass. See
  [build 33](docs/audit-fixes-33.md).
- Build 32: added Cod Pro with StoreKit 2 (yearly and monthly with a 7-day
  trial, and lifetime), the Pro screen, restore and the float-time gate. See
  [build 32](docs/pro-32.md).
- Build 31: added window shapes for tools, a switch per System Monitor reading
  with new readings, Speedometer as its own tool, and Recents with stars in
  place of Library. See [build 31](docs/recents-shapes-31.md).
- Build 30: repaired eight tool UI tests and fitted editors in phone
  landscape; first full UI run on Xcode 27.2 (74 tests, 4 PiP skips, a few
  flaky Launch Lab tests). See [build 30](docs/ui-tests-30.md).
- Build 29: added Countdown To, World Clock, System Monitor, Lines
  teleprompter, Image Sets, the Float Video with Cod Safari extension and the
  category-card Float tab. See [build 29](docs/floathing-parity-29.md).
- Build 28: added the signed Screenshot and Crop Shortcut, made 1.0
  iPhone-only, turned Translate on by default and committed the new icon. See
  [build 28](docs/crop-shortcut-28.md).
- Build 27: Shortcut and Share images keep native resolution, and sharing to
  the Cod icon ends on an "open Cod" screen. See
  [build 27](docs/share-resolution-27.md).
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
