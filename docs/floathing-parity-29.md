# Build 29: Floathing feature parity and a reorganized Float tab

November 11, 2026. The owner asked for every feature Floathing lists, and for the
Float tab to borrow Floathing's organization (dashboard, active session,
recents, tool categories, a switcher inside setup). Floathing's App Store
listing (v1.6) and screenshots were the reference; nothing was copied from its
code or artwork.

## Feature parity

| Floathing | Cod before | Cod build 29 |
|---|---|---|
| Teleprompter with auto-scroll | Scroll and Words modes | Adds **Lines** mode: current line large, next lines dimmed, n/m counter |
| Timer, stopwatch, countdown | Timer, stopwatch, Pomodoro | Adds **Countdown To** a date and time (days/hours/minutes/seconds) |
| World clock | One time zone | Adds **World Clock**: up to 4 cities, with "Tomorrow"/"Yesterday" notes |
| Sticky notes | Text cards | Same |
| Reference images, multi-image import | Single images | Adds **Image Set**: 2–30 photos, auto-advance 2–120 s, PiP skip buttons step one image |
| System monitors (network, battery/thermal, speedometer) | — | Adds **System Monitor**: battery, temperature, download/upload rate, optional speedometer |
| Safari extension for web video PiP | — | Adds **Float Video with Cod** Safari extension |
| Presets, live preview | Saved cards and presets, live preview | Same, plus **Recents** |
| Quick presets | Duration menu | **Preset chips** (5–60 min) on Timer |

Cod still adds what Floathing doesn't have: crop-to-float, OCR/translate,
barcode scanning, Shortcuts, Back Tap, widgets, Control Center controls and
AlarmKit alarms.

## Float tab organization

- **Crop & float** stays first (Cod's lead): photos/videos, latest screenshot,
  paste, the new **Image Set**, and files.
- **Now floating** card: what's floating, a live value, Pause/Resume and Stop,
  plus Playback controls.
- **Recents**: the last six tool setups. Tap to float again; long-press to
  edit or remove.
- **Time** card: six tiles (Timer, Stopwatch, Countdown To, Pomodoro, Current
  Time, World Clock).
- **Text, system & web** card: Text & Teleprompter, System Monitor, Safari Video.
- Inside a Time tool, a **switcher** across the top moves between the six
  Time tools without going back.

Tool tiles keep the `tool-<kind>` accessibility identifiers, so existing UI
tests and automation still find them.

## Implementation notes

- New settings on `FloatingToolConfiguration` are stored as optionals
  (`storedEventDate`, `storedWorldClockZones`, …) behind computed properties.
  Presets saved by earlier builds have no such keys and still decode; a unit
  test covers this.
- **System Monitor** samples once a second only while a monitor is floating
  or its editor is open (`SystemMetricsSampler`). Its sources:
  - battery and thermal state from `UIDevice` and `ProcessInfo`;
  - network byte counters from `getifaddrs` (Wi-Fi `en*` and cellular
    `pdp_ip*` only, with counter wraps treated as zero);
  - speed from Core Location, only when Speedometer is on.
- **Location:** Info.plist adds `NSLocationWhenInUseUsageDescription` and the
  `location` background mode. Floating means Cod is in the background, so the
  speedometer needs it. The background location indicator stays on, and
  updates stop when the monitor stops.
- **Image sets** live in Application Support/Image Sets. Sets no saved
  reference uses are removed at the next launch.
- **Safari extension** (`CodSafari`, `com.josh.cod.store.safari`):
  - Manifest v3. A content script adds a "Float" pill to videos at least
    200 × 110 that support web PiP.
  - Tapping it calls the standard `requestPictureInPicture()`, falling back to
    `webkitSetPresentationMode`.
  - The popup can hide the button or float the largest video on the page.
  - No page data is read beyond finding video elements, and nothing is sent.
  - The native handler does nothing and never opens Cod.
- The privacy policy now covers the speedometer, the extension and image sets.

## Verification

Xcode 27.2, iPhone 17 Pro Max simulator, iOS 26.5.

- **Unit tests:** 268/268 pass. New `NewToolsTests` cover:
  - Lines splitting and timing
  - Countdown formatting and finished state
  - World Clock rows, day notes and validation
  - Network rate wrap handling and metric text
  - System snapshot rows
  - Image-set indexing and validation
  - Decoding presets saved by older builds
  - Recents dedupe, cap and persistence
  - Category coverage
- **UI tests:** 22 Float-tab, editor, guide, introduction and large-text
  tests pass. These cover Redesign21, ReleaseUX and Release18 in full, plus 13
  tool-editor tests. Also passing: the crop Shortcut, the share flow (one flaky
  run, then a pass on rerun) and the updated media-choices test, which now
  scrolls to the Text tile. The eight tool UI tests that already failed on
  build 27 weren't rerun here.
- **Release archive:** unsigned, build 29, with CodShare, CodControls and
  CodSafari. `verify-store-build.sh` and `verify-supported-source.sh` pass. The
  store check doesn't yet inspect the Safari extension by name; add it before
  submission.
- **Simulator walk-through:**
  - The new Float tab renders.
  - Tool tiles open their editors.
  - System Monitor shows live network rates. Battery reads "—" in the
    Simulator, which reports no battery.
- **Safari content script:** checked in a desktop browser against a local
  test page. The Float pill appears on the video, and clicking it put the
  video into Picture in Picture and started playback.
- **Still to do on the phone:**
  - Enable the extension in Safari and float a real web video.
  - Speedometer accuracy, and the location indicator while floating.
  - Battery and temperature readings.
  - PiP skip buttons stepping through an image set.
  - Lines mode readability.

App Review notes to add: why the `location` background mode is needed (the
Speedometer works only while floating, which puts Cod in the background), and
that the Safari extension only triggers Safari's own Picture in Picture.
