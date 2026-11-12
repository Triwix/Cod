# Build 30: the eight failing tool UI tests

November 12, 2026. Eight `FloatingToolsUITests` had failed since build 27
under Xcode 27.2 (listed in the [build-28 notes](crop-shortcut-28.md)). None
of them was a Cod bug. While fixing them, one real layout problem from build 29
turned up and is fixed here.

## What was wrong

| Cause | Tests | Fix |
|---|---|---|
| The Xcode 27.2 simulators (iOS 26.3 and 26.5) report `AVPictureInPictureController.isPictureInPictureSupported() == false`. Cod correctly shows its "Not available here" fallback, so no native PiP window ever opens. | Current Time controls, timer close, video repeat, teleprompter rewind, video import | The new `nativePiPStarted()` helper waits for "Floating" or "Not available here". The four PiP-only tests now skip with that reason. The video-import test still checks its import → Library → Favorite half. |
| The teleprompter became a mode of the Text tool; the `tool-teleprompter` tile no longer exists. Text-mode tests also inherited teleprompter mode from earlier tests. | All color editors, native color picker, Home/Library history | These tests open Text through `openTextEditor(prompter:)`, which sets the mode explicitly. The color test now also covers Countdown To, World Clock and System Monitor. |
| In a landscape simulator scene, coordinate drags don't scroll the list, so `reveal` never moved. | Phone landscape | In landscape, `reveal` uses slow swipes on the list itself (velocity 120). |

## App fix

**Phone landscape:** the build-29 tool switcher took enough height to shrink
the pinned preview and push the settings off screen. The switcher is now hidden
when the vertical size class is compact, and Back still reaches the other
tools.

## Verification

Xcode 27.2, iPhone 17 Pro Max simulator on iOS 26.3.

- **Unit tests:** 268/268 pass.
- **The eight tests:**
  - Four pass: color selectors, color picker, landscape, video import with Library favorite.
  - Four skip, each with the PiP-unsupported reason.
- **Full UI suite:** this is the first full run on Xcode 27.2: 74 tests, 4 skipped.
  - **Fixed:** `testHomeHasNoRecentItemsWhileLibraryRetainsHistory` had the same text-mode problem.
  - **Flaky:** four tests failed in the hour-long run and passed when rerun on their own:
    - Library favorites
    - PDF page typing (the Launch Lab's Open In sheet)
    - signed share Shortcut
    - one-second alarm (the Lab's music player)
  - **Expected failure:** the 13-inch iPad screenshot test, because 1.0 ships iPhone-only.

## Still needs a device

The skipped tests are the native PiP checks:

- Current Time playback controls
- keep-running timer close
- video repeat in PiP
- teleprompter 10-second rewind

Run them on an iPhone, or on a future simulator that supports PiP. They aren't
proven by this build.
