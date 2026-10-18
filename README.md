# Cod

## Optional fast entry points — build 4

New Control Center / Lock Screen / Action Button control, Back Tap and share
Shortcut installers, and a selectable Share → notification → Cod handoff.
See [setup and verification](docs/float-entry-points.md).
Existing direct-share behavior is preserved. Apple-signed Shortcut files are
included for both Cod Test and the original Cod; users approve installation
and assign Back Tap themselves.

## Fast-share test candidate — October 15

The **Cod Fast** scheme restores **Share → Cod Test → automatic PiP attempt**,
without a separate app-open step or required Shortcut. **One tap float off**
keeps cropping in the share sheet before Float. It uses shared image storage
and an isolated unsupported launch workaround, **not** the private return or
control-hiding code. The original Cod app stays separate. This is a usability
candidate with explicit App Review risk, not an approved distribution solution.
See [implementation, tests and risk assessment](FAST_SHARE.md).

## Documented-only comparison (Cod scheme)

The **Cod** scheme builds the public-API fast-flow test candidate. Its share
extension automatically prepares the image and dismisses; opening Cod then
attempts PiP automatically, without Save, Done or another Float button. Choosing
an image inside Cod also floats immediately. Turning off **One tap float**
opens cropping instead. This is a fallback, **not a completed one-tap native
Share → Cod → PiP flow**. It doesn't launch the app from the share sheet,
automatically return to another app, hide system controls, or upload to Imgur.
See [release setup and remaining gates](APP_STORE_RELEASE.md) and
[fast-launch experiment results](FAST_LAUNCH_TESTS.md).

The **Cod Personal** scheme preserves the original sideloaded workflow below.
It uses distinct PersonalDebug/PersonalRelease configurations with `COD_PERSONAL`;
**never submit that scheme**. The store candidate has a separate bundle ID and
requires App Groups provisioning with a paid developer account. Its local
checks do not establish App Store acceptance.

The following historical feature notes describe the personal version where
they differ from the store candidate.

Latest screenshot-return investigation:
[physical test results and platform limits](RETURN_RESEARCH.md).

A Snapper 3-style snipping and screenshot toolbox for **non-jailbroken** iPhones.
Draw a rectangle on a screenshot, then instantly copy, OCR, scan, save, share or
float it above everything else.

## Build

```bash
xcodegen generate && open Cod.xcodeproj
```

Then set your team under **Signing & Capabilities** for both targets (`Cod` and
`CodShare`), configure their shared App Group for the store scheme, and run.
Deployment target remains iOS 17.0. Current toolchain: Xcode 26.6.

The project is generated from `project.yml` — edit that, not the `.xcodeproj`.
The shared `Cod` scheme includes the `CodTests` unit-test bundle; choose an
installed iOS Simulator and use **Product → Test**.

## Signing constraints

Built for a **free Apple ID (personal team)**, which means:

- No App Groups, so the share extension can't write into the app's history.
  Cropping stays in the extension; Float hands the chosen image to Cod.
- The One tap float switch uses a narrowly scoped shared keychain group,
  supported by the current personal provisioning profiles. Only the preference
  is stored there, not credentials or images; it does not depend on the clipboard.
- No ReplayKit broadcast-extension ring buffer (that needs a shared container).
- Re-sign every 7 days.

These constraints describe the personal configuration. The store configuration
uses a shared App Group and a different image-transfer/navigation workflow.

## How close is this to Snapper 3?

| Snapper 3 | Cod | Notes |
|---|---|---|
| Crop a region instead of the full screen | ✅ | Drag, 8 handles, magnifier loupe, exact pixel readout |
| Frozen screen while selecting | ✅ | Inherent — you're always working on a still |
| Pin snippets over other apps | ⚠️ | One snippet, via Picture in Picture. Device only — verified working on an iPhone 12 Pro Max, iOS 26.6. |
| Multiple simultaneous pins | ⚠️ | Unlimited *inside Cod*; iOS allows only one PiP window system-wide |
| Move and resize pins | ✅ | Drag, pinch, corner grip |
| Instant action menu | ✅ | Copy, Copy Text, Save, Share, Pin, Scan, Translate, Edit, Upload |
| Reorder / disable actions | ✅ | Settings → Action bar |
| OCR + copy recognized text | ✅ | Vision, on-device |
| OCR language selection | ✅ | Every language Vision reports on the device |
| OCR accuracy vs speed | ✅ | Fast / Accurate |
| QR + barcode scanning from screen | ✅ | Doesn't work in the Simulator (Vision can't load the model there) |
| Screenshot history | ✅ | Searchable by recognized text |
| History length none/10/20/50/∞ | ✅ | |
| Dedicated Photos album | ✅ | Configurable name; requires Full Photos Access, otherwise saves to Recents |
| Imgur upload | ✅ | Bring your own Client ID; always confirms before uploading |
| Share sheet integration | ✅ | Crop then Float by default; optional One tap float for the whole image |
| Screenshot delay | ✅ | 0–2s |
| Black / white pin shadow | ✅ | Plus opacity and corner radius |
| One-tap close on a pin | ✅ | Snapper 3 dropped this; Cod keeps it |
| Replace the volume-up + side button gesture | ❌ | Not possible without a jailbreak |
| Draw a crop box directly over another app | ❌ | Same |
| Silently intercept every screenshot | ❌ | Same |
| Control Center / Lock Screen / Action Button | ⚠️ | iOS 18+ Float Latest Screenshot control implemented; native launch tested, physical PiP check pending |

## One-gesture capture

For immediate floating, open **Settings → Set up fast floating** in Cod and add
the signed **Screenshot and Float with Cod** Shortcut, then assign it to Back
Tap. For the optional crop-first personal workflow, use the steps below.

The closest thing to Snapper's activation gesture:

1. Shortcuts → new shortcut → **Take Screenshot** → **Crop With Cod**.
2. Settings → Accessibility → Touch → Back Tap → Double Tap → that shortcut.

Double-tap the back of the phone in any app and you land on Cod's crop surface
with that app's screenshot loaded. `Crop Latest Screenshot` and `Clear Cod Pins`
are also exposed as intents.

For an image in Photos or a screenshot preview, use **Share → Cod**. By default,
the extension opens the crop surface and waits for **Float**. Draw a region to
float that crop, or tap Float without drawing to use the whole image.
In **Settings → Share Sheet**, turn on **One tap float** to skip selection and
float the whole image as soon as Cod is tapped. The switch defaults off,
persists between launches, and does not change explicit Float Shortcuts.

Both modes use the same containing-app PiP path. The extension places the
chosen image in a custom pasteboard representation and asks Cod to open
`cod://float-shared-image`. Cod creates the player-backed PiP window in its own
process and attempts to return to the source app. Copy, Copy Text, Save, and
Scan Code remain available inside Cod. The shared preference uses Apple's
[keychain access-group mechanism](https://developer.apple.com/documentation/xcode/configuring-keychain-sharing),
with a group scoped to Cod's share settings rather than the app's credentials.

The extension launch uses an **unsupported responder-chain workaround** for
this personal, sideloaded build. `NSExtensionContext.open` is tried first but was
rejected on the tested iPhone; the responder-chain `UIApplication.open` callback
reported success, and the actual image reached Cod on iOS 26.7 on October 2,
2026. This is not a supported App Store architecture or a guarantee for future
iOS versions. Registering image document types also enables document-opening
flows where the source app offers them; it does not guarantee an “Open in Cod”
button in every Share sheet.

**Float With Cod** and **Crop With Cod** remain available as Shortcuts actions.
They are optional; Share → Cod needs no Shortcut. Their image input must be
wired explicitly; merely adding one to a shortcut did not
reliably pass Share Sheet images during device testing.

Starting new PiP requires the content source's actual window scene to be
foreground-active: AVKit rejected background/inactive starts on this iPhone.
Cod must therefore appear briefly; background playback support does not grant
permission to start a new PiP from a cold/background app. Earlier attempts to
own the window directly from the share extension rendered gray or died.

Automatic return previously called private `UIApplication.suspend`, which is
Home, not the previous app. `suspendReturningToLastApp:true` was present and
invoked on the iPhone but still returned Home. The source-aware October 6 build
instead passes the share host's bundle identifier with the image and attempts
to reactivate that existing app using guarded `LSApplicationWorkspace` runtime
calls. It first tries an available system Back-to action. Unknown sources are
not guessed, and metadata is consumed so later Shortcuts cannot inherit an
earlier Photos destination. The legacy Home fallback remains when no reliable
return request is available. This also applies to active-PiP image replacements.
Temporary screenshot-preview shares are an exception: the exact observed host
`com.apple.ScreenshotServicesService` returns directly to Home without app
activation, Back-to, or the last-app selector. Reopening that system service
produced a black "Screenshots" screen on the phone. This rule is based on the
share host, not the image: a saved screenshot shared from Photos still returns
to Photos. The app behind the temporary preview is not currently identified.

A simulator Share → Cod return-only test identified Photos and resumed the
exact waterfall photo with the share sheet dismissed. A separate source-only
probe resumed the exact flower photo. These probes bypassed PiP and do not
establish on-device PiP persistence or return behaviour. The private system
Back-to getter returned nil on this simulator. All return methods are
unsupported personal-build experiments, not App Store-safe navigation APIs.
The simulator's existing Float Latest Screenshot App Shortcut failed with
“Unable to run App Shortcut” before delivering an intent to Cod, so that run
did not verify Shortcut-origin return. Simulator-only `--return-probe` and
`--navigation-probe` launch arguments retain reproducible return diagnostics;
`--return-source=<bundle identifier>` enables a source-only probe.
The source-aware build passed all 15 simulator unit tests (including four new
source validation/clipboard preservation tests), built for device, and was
installed wirelessly on the paired iPhone on October 6. Its active-PiP return
test still returned Home. The retrieved device logs showed `share source=unknown`
and `navigation=false`, followed by a successful PiP start and the legacy Home
fallback. The source-app activation method was never attempted on that run.
The next hosted-scene build therefore expands source discovery through the
responder chain and the extension's own FrontBoard scene identity. It logs
the hosting identity and field names on lookup failure, not image content.
This is a targeted device-source fix, not evidence yet that app activation
works on the phone.
The hosted-scene build passed all 20 simulator tests, built for the device,
and was installed wirelessly on October 6. Tests cover parent/responder lookup,
cycle bounds and strict scene-identity parsing; actual phone source discovery
and return remain awaiting the next share attempt.
The next two device attempts still reported `share source=unknown`; the exposed
scene identifier named only CodShare, not its host. PiP started in both cases,
then the legacy fallback returned Home. Exact-origin return remains unresolved.

The modern-host return experiment now checks the correctly cased `_FBSScene`
getter, its existing host process/identity, and the extension's existing host
connection. A SpringBoard/ShareSheet scene host is treated as an intermediary,
not proof that the original trigger was Home. Missing/changed runtime signatures
are skipped; no global foreground-app/process enumeration is performed.
The visible `_UIStatusBarNavigationItem` Back-to experiment is isolated behind
the DEBUG-only `--breadcrumb-probe` argument and never runs for normal floats.
Only the primary legacy destination is eligible, not a forward/secondary target.
Navigation response BOOLs are treated as dispatch results, not proof of screen
restoration; subsequent app activation state is logged.
The DEBUG-only `--navigation-probe --return-source=com.apple.mobileslideshow`
source-only test is now available on a physical phone as well as the simulator.
The DEBUG-only `cod://return-probe` URL exercises Back-to without PiP, an image
handoff or clipboard access. Neither probe guesses a source for normal floats.
The first modern-host build passed 27 simulator tests and its known-Photos
return-only probe visibly resumed the same flower photo. Device verification
and live Back-to/host identification remain pending; this is not a confirmed
fix or a guarantee for arbitrary Shortcut/Home/screenshot-preview origins.

The first physical modern-host attempts on October 6 did identify Photos via
`_FBSScene.identity.workspaceIdentifier`, but the containing app then crashed
before starting PiP. Device crash reports at 20:06:14, 20:08:31 and 20:08:38
pointed to `SourceAppReturn.currentStatusBars()` invoking UIApplication's lazy
status-bar getter. UIKit asserted in `_createStatusBarWithRequestedStyle` on
the scene-based iPhone. The isolated source-only test hit the same crash;
its apparent missing diagnostic was not an argument-delivery failure.
The crash fix removes all status-bar access from context capture. The isolated
breadcrumb experiment reads already-existing object ivars only, never UIKit's
lazy status-bar getters. Normal floats keep the now-working source metadata
and attempt source-app activation only after PiP reports it has started.
The crash-fix build passed all 29 simulator tests, including checks that the
status-bar probe never invokes lazy getters and context capture is safe without
a status bar. It built for device and was installed wirelessly on October 6
at 20:12. Restored PiP and the return destination still need physical testing.
The user subsequently confirmed successful floating and return from Photos.
Device logs at 20:20–20:22 show successful Photos activation with PiP, followed
by two screenshot-preview floats that activated ScreenshotServicesService.
The user observed that service as a black, iconless "Screenshots" app. The
screenshot-home-fallback build therefore skips that transient service and uses
the existing Home suspension only after PiP starts; device verification of this
exception remains pending.
All 32 simulator tests passed, including screenshot/Home routing, normal-app
preservation, and transient-context consumption. The device build succeeded
and was installed wirelessly on October 6 at 20:24. These checks do not replace
an actual screenshot-preview float on the phone.

The crop-default/One tap float update passed all 24 simulator tests, including
shared-keychain persistence and save-failure handling. Simulator UI checks
confirmed the switch defaults off, survives restart when enabled, is read by
the separate extension process in both states, and waits for a manual Float
tap when off. The manual tap handed the image to Cod's return-only simulator
probe; real PiP is still device-only. Cropping uses the existing selection
surface with Vision disabled in the extension to stay within its memory budget.
The update was built, signed with the shared preference entitlement in both
targets, and installed wirelessly on the paired iPhone on October 6.

Remaining return-to-screen work:

- Verify source-aware return with active PiP on the iPhone, from Photos,
  screenshot previews, Files and other share hosts.
- Find reliable origin context for Shortcuts (including Back Tap/Action Button
  launches). App Intent input currently provides an image, not the app/screen
  that was foreground before the Shortcut ran. Do not assume Shortcuts itself
  is the desired destination.
- Preserve Home when Home really was the origin, and the exact source screen
  otherwise, for every float trigger. This is the target behaviour, not a
  universal guarantee implemented yet; reactivating an app relies on that app
  retaining its own screen state.

## Architecture

```
Cod/
  App/          CodApp, RootView, CaptureCoordinator (runs actions, routes UI)
  Models/       Snap, SnapAction
  Store/        SnapStore (disk-backed history), AppSettings
  Capture/      ImageProcessing, PhotoLibraryService
  Recognition/  Recognizer — OCR, barcodes, smart regions
  Pins/         PinManager, PinOverlay, PiPPinController
  Intents/      App Intents for Shortcuts
  Views/        Selection (the crop surface), Home, Library, Settings, Routes
CodShare/       Crop-first share extension with optional one-tap whole-image float
CodTests/       Selection geometry, history persistence and PiP state tests
```

Selections are stored in **image pixel space** throughout, so the readout is
exact and crops are lossless. `SelectionGeometry` is the only place that maps
between pixels and screen points.

## How the floating window works

`Float` encodes the snippet into a ~2 second looping H.264 clip
(`FloatingClip`), plays it muted through an `AVQueuePlayer`, and drives
`AVPictureInPictureController` from the resulting `AVPlayerLayer`. Every frame is
identical, so it compresses to a few KB and looping by seeking back to zero is
invisible.

PiP resizing uses the system's native pinch gestures and size limits. Cod does
not impose a window-size cap or enumerate custom resize steps; AVKit controls
the available sizes for the content's aspect ratio and the current device.

### Share-to-float investigation (October 2, 2026)

October 6 follow-up: the user confirmed successful floating. Retrieved logs
show the actual 1536×2048 image received, new PiP startup in ~1.4–1.5 seconds,
and successful in-place replacements. The next build removes the crop/menu
step, waits for the extension view to appear before launching Cod, keeps a
bounded launch callback timeout with Retry/Cancel recovery, and experiments
with last-app return. Visual return destination still needs device validation.
The direct-float build passed all 11 simulator unit tests, built for device,
and was installed wirelessly on the paired iPhone on October 6. Installation
does not establish that the experimental return selector works on that device.

- Device logs confirmed image import, crop transfer, containing-app launch, and
  PiP startup. The earlier gray window was produced by the extension-owned
  playback experiments; the containing-app path displayed the actual image.
- One failed attempt reused a dormant placeholder player from before Cod was
  backgrounded. The next attempt built fresh playback and succeeded. Share URL
  launches now discard dormant prewarming, while replacing an already-active
  PiP still keeps its existing window. First-attempt reliability needs device
  confirmation; the observed difference is evidence for this change, not proof
  of the exact AVKit failure mechanism.
- AVKit explicitly rejected a later request with error `-1001`: the content
  source's `UIScene` was not `foregroundActive`. A second attempt succeeded.
  Startup now checks the source view's actual window scene and waits for its
  `UIScene.didActivateNotification` before requesting PiP.
- The launch path reads actual completion callbacks and has a bounded timeout.
  It no longer equates finding a responder with successfully launching Cod.
- Stage logs are stored in each process's Documents directory:
  `share-diagnostics.log` in `com.josh.cod.share`, and `cod-diagnostics.log` in
  `com.josh.cod`. They record dimensions and stage timings, not image content.
- Ten simulator unit tests and the device build passed. Simulator tests cannot
  establish on-device PiP presentation or persistence.

Things learned the hard way, all of which cost real debugging time:

- **`AVSampleBufferDisplayLayer` is the wrong tool here.** Feeding a still image
  in as a fake live stream gets `isPictureInPicturePossible == true` and then
  `startPictureInPicture()` silently does nothing — no error, no delegate call.
  The renderer needs a control timebase to drain its queue; without one AVKit
  sees a stalled queue and refuses. The `AVPlayer` path just works.
- **AVKit's first-ever PiP request on a device takes ~10 seconds** to flip
  `isPictureInPicturePossible`. Everything Cod does takes ~190ms. That cold cost
  appears to be system-level initialisation and persists across app reinstalls,
  so it's likely back after a reboot. `prewarm()` starts the pipeline on a
  throwaway clip the moment the crop surface opens to hide it.
- **Never tear the player down on a start timeout.** AVKit can open the window
  long after you've given up, and destroying the controller mid-handover is what
  made launching intermittent.
- **`.mixWithOthers` is fine.** It does *not* block PiP eligibility, so the
  user's music keeps playing. Settings → Pins can turn it off if a mixable
  (secondary) audio session ever costs the background time the window needs.

## Known gaps in the Simulator

- Picture in Picture is unavailable — the "float over other apps" pin needs a device.
- `VNDetectBarcodesRequest` can't load its model, so Scan Code fails with a
  clear message. Text recognition works fine.
- Haptics are silent.

## Backlog

See [MVP reliability checklist](MVP_CHECKLIST.md) for verified behavior, the
October 6 hardening sweep, and remaining physical-device acceptance checks.

- [ ] Float real videos through Picture in Picture. AVKit supports this with an
  `AVPlayerLayer`; the remaining product work is video import/share handoff,
  choosing whole-video versus cropped-video behavior, audio policy, controls,
  and lifecycle/file cleanup.
