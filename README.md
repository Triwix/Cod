# Cod

A Snapper 3-style snipping and screenshot toolbox for **non-jailbroken** iPhones.
Draw a rectangle on a screenshot, then instantly copy, OCR, scan, save, share or
float it above everything else.

## Build

```bash
xcodegen generate && open Cod.xcodeproj
```

Then set your team under **Signing & Capabilities** for both targets (`Cod` and
`CodShare`) and run. Deployment target is iOS 17.0; built and tested against the
iOS 26.3 Simulator with Xcode 26.2.

The project is generated from `project.yml` — edit that, not the `.xcodeproj`.
The shared `Cod` scheme includes the `CodTests` unit-test bundle; choose an
installed iOS Simulator and use **Product → Test**.

## Signing constraints

Built for a **free Apple ID (personal team)**, which means:

- No App Groups, so the share extension can't write into the app's history.
  It's self-contained instead: crop, OCR, scan and save all complete in-process.
- No ReplayKit broadcast-extension ring buffer (that needs a shared container).
- Re-sign every 7 days.

Everything is written so that upgrading to a paid account only *adds* options;
nothing needs restructuring.

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
| Share sheet integration | ✅ | Share extension runs the same crop surface |
| Screenshot delay | ✅ | 0–2s |
| Black / white pin shadow | ✅ | Plus opacity and corner radius |
| One-tap close on a pin | ✅ | Snapper 3 dropped this; Cod keeps it |
| Replace the volume-up + side button gesture | ❌ | Not possible without a jailbreak |
| Draw a crop box directly over another app | ❌ | Same |
| Silently intercept every screenshot | ❌ | Same |
| Control Center modules | ⚠️ | Shortcuts + Back Tap / Action Button instead |

## One-gesture capture

The closest thing to Snapper's activation gesture:

1. Shortcuts → new shortcut → **Take Screenshot** → **Crop With Cod**.
2. Settings → Accessibility → Touch → Back Tap → Double Tap → that shortcut.

Double-tap the back of the phone in any app and you land on Cod's crop surface
with that app's screenshot loaded. `Crop Latest Screenshot` and `Clear Cod Pins`
are also exposed as intents.

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
CodShare/       Self-contained share extension
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
