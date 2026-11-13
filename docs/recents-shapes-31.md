# Build 31: window shapes, System Monitor readings, Speedometer and Recents

November 12, 2026. These follow up on the owner's notes from Floathing:
- choose the Picture in Picture window's shape
- switch each System Monitor reading on or off, and add more readings
- make speed its own tool
- replace the Library with Recents of everything floated, with stars to pin items

## Window shapes

iOS sizes a Picture in Picture window from the aspect ratio of the video it
plays. Cod's tools draw their own frames, so each tool now draws at the chosen
shape:

| Shape | Ratio | Frame |
|---|---|---|
| Wide (default) | 16:9 | 960 × 540 |
| Standard | 4:3 | 800 × 600 |
| Square | 1:1 | 680 × 680 |
| Tall | 3:4 | 600 × 800 |
| Portrait | 9:16 | 540 × 960 |

- **Where:** a "Window" row in every tool editor and in the Teleprompter.
- **Layout:**
  - The renderer lays out everything relative to the canvas: rings, title/value blocks, clocks, Lines, Words, table rows and image sets.
  - Tall teleprompter windows show more of the script.
- **Not covered:** photos, videos, PDFs and text cards keep their own shape, which comes from the content (crop a photo to change it).
- **Saving:** the shape is part of a tool's saved setup and recents. Older presets decode as Wide.

## System Monitor

- **A switch per reading:**
  - Battery, Temperature, Download and Upload, which stay on by default.
  - New: Connection (Wi-Fi/Cellular/Ethernet/Offline via `NWPathMonitor`).
  - New: Free Storage (`volumeAvailableCapacityForImportantUsage`).
  - New: Memory in use (Mach `host_statistics64`: active + wired + compressed).
  - New: CPU (`host_processor_info` tick deltas).
  - New: Low Power Mode.
- **Order:** rows always follow a fixed order. A monitor needs at least one reading.
- **Layout:** more than five readings in a wide window draw as two columns. Values shrink to fit instead of clipping.
- **Privacy manifest:** Free Storage is a required-reason API, so `PrivacyInfo.xcprivacy` declares `NSPrivacyAccessedAPICategoryDiskSpace` with reason 85F4.1 (shown to the user).
- **No FPS reading:**
  - While floating, Cod runs in the background, and iOS doesn't let a background app measure the screen's frame rate.
  - Showing Cod's own render rate would be a made-up number.
- **No uptime reading:** showing device uptime isn't one of Apple's approved reasons for the boot-time API.

## Speedometer

- **A separate tool:** Speedometer is now its own tool next to System Monitor, and the tool switcher moves between the two. It was a switch inside System Monitor.
- **What it shows:** a large number with km/h or mph.
- **Location:** it asks for location the first time its editor opens, and uses it only while it's open or floating.
- **Older presets:** System Monitor presets from build 29 that had Speedometer on still decode. The old flag is ignored.
- **Wording:** the location purpose text, privacy policy and editor footer now name the Speedometer tool.

## Recents

- **The tab:** the Library tab is now **Recents**. It lists images, videos and tool setups in one list, sorted by when each was last used.
- **Floating again:**
  - Tapping a row floats it again.
  - An image or video floated from Recents moves to the top (`Snap.lastUsedAt`, `SnapStore.touch`) instead of being saved twice.
- **Stars:**
  - Stars pin items in a Starred section at the top. A Starred filter shows only those.
  - Starred images use the existing favorite flag, so they still survive history limits.
  - Starred tool setups are never trimmed. Up to 30 unstarred setups are kept (it was 6).
- **Other actions:** long-press for Details & Text (the existing OCR/barcode sheet), Re-crop, Copy, Edit Before Floating and Remove. Swipe to remove.
- **Saved cards & presets** sits at the bottom of Recents.
- **Clear Recents** keeps starred items and saved cards. Delete Everything removes them too.
- **Home:** the Home Recents strip shows starred setups first.
- **Wording:** user-facing Library/Favorites text in Settings, Privacy, widgets and Shortcuts now says Recents/starred.

## PDFs page by page

- **Three modes:** the PDF screen now offers One Page, **Flip Pages** and Auto-scroll. Multi-page PDFs open in Flip Pages.
- **What Flip Pages does:**
  - It renders the chosen range (2–30 pages) into an image set that **opens paused** on the first page.
  - The floating window's skip buttons go back or forward one page, whatever interval iOS shows on them (on the phone that's ±10 or ±15 s).
  - Pressing play turns pages on a timer (10 s default).
  - The window shape defaults to the shape closest to the page (US Letter → 3:4) and can be changed.
- **Image sets:** they gain a **Start paused** switch (off by default, so existing sets behave as before).
- **Code:** `FloatingToolConfiguration.startsPaused` and `setName`; `LiveFloatSource.activate()` no longer auto-plays paused content.
- **Tests:**
  - Unit tests: paused start, one-page skips with clamping, the live source staying paused, and shape matching.
  - UI test: `testMultiPagePDFsOpenReadyToFlipPagesPaused`.
  - Updated: the PDF UI tests now pick their mode explicitly.

## Verification

Xcode 27.2, iPhone 17 Pro Max simulator on iOS 26.3.

- **Unit tests:** 278 pass (275 before the PDF change). New ones cover:
  - every tool rendering at every shape
  - tall teleprompter travel
  - reading order and formatting
  - CPU tick math and live reads of CPU, memory and storage
  - Speedometer formatting
  - starring, trimming and persistence of recents
  - build-29 recents still decoding
  - search and last-used sorting
  - floating an image again without saving a copy
- **New UI tests (`Build31UITests`):**
  - the shape picker changes the preview's shape
  - every reading has a switch
  - the Speedometer opens and switches to System Monitor
  - starring a tool setup pins it above Recent
- **Updated UI tests:** the existing tests now use the Recents tab, starring, and tap-to-float.
- **Rendered frames:** Wide two-column System Monitor, Speedometer, Pomodoro at 4:3, and portrait teleprompter (Scroll and Lines), clock, stopwatch and System Monitor were checked as images.
- **Still to do on the phone:**
  - real PiP windows at each shape
  - CPU and memory values against expectations
  - Speedometer while driving or walking
  - the location indicator

### Full UI run

- **Overall:** 78 UI tests ran, with 4 skipped because the simulator has no Picture in Picture.
- **Expected failure:** the iPad screenshot test, because 1.0 is iPhone-only.
- **Flaky:** eight tests failed in the 107-minute run and passed when rerun on their own. Most were event-synthesis timeouts while the simulator was bogged down late in the run:
  - Recents stars and clearing
  - photo import
  - default appearance
  - saved card
  - saved-reference control
  - landscape
  - two-second alarm
  - Redesign21 Recents check
- **Release archive (unsigned, build 31):** `verify-store-build.sh` and `verify-supported-source.sh` pass, and the shipped privacy manifest includes 85F4.1.
