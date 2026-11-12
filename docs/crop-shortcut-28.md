# Build 28: crop Shortcut, iPhone-only 1.0, Translate on by default

November 11, 2026. Implements launch-plan items A, B and E, and keeps the
owner's new app icon (item D).

## Changes

- **A. Screenshot and Crop with Cod.** A third signed Shortcut: Take
  Screenshot → Crop With Cod. Back Tap opens the fresh screenshot in Cod's
  crop editor; double-tap a region (or tap Float) to float it.
  - The Floating Guide's "Back Tap · crop first" section now offers
    **Add Crop Shortcut**, replacing the manual build-it-yourself steps.
  - `Tools/MakeFloatShortcuts.swift` generates all three workflows.
  - Only the new file was signed (`shortcuts sign --mode anyone`); the two
    existing signed files are unchanged.
  - `verify-store-build.sh` now requires all three.
- **B. iPhone-only.** `TARGETED_DEVICE_FAMILY` is `1` for the app, both
  extensions and the test harness. iPad can be added in a later version.
- **E. Translate on by default.** New installs show Translate in the crop
  action bar. Saved action choices are respected.
- **D. New app icon** committed.

## Verification

Xcode 27.2, iPhone 17 Pro Max simulator, iOS 26.5:

- **Unit tests:** 254/254 pass, including 4 new build-28 tests: Translate
  default, saved choices respected, crop Shortcut bundled and signed, and
  iPhone-only device family.
- **New crop Shortcut UI test:** passes. The installed Shortcut runs, opens
  Cod and shows the crop editor.
- **Rerun after a simulator reboot:** all three Shortcut tests, the updated
  Floating Guide test, and every share, notification and launch test pass.
- **Release archive:** unsigned, build 28, device family [1], three
  Shortcuts. `verify-store-build.sh` and `verify-supported-source.sh` pass.

### Known failing UI tests (pre-existing)

Eight FloatingToolsUITests fail identically on build 27 (`4925efe`) and
build 28, so they aren't regressions:

- `testCurrentTimeHasNoMeaninglessResumeOrRestartControls`
- `testAllColorCapableEditorsHaveNativeColorSelectors`
- `testNativeColorPickerKeepsPreviewVisibleAndAllowsLiveChanges`
- `testPinnedPreviewAdaptsToPhoneLandscape`
- `testNativeTimerCloseHonorsBothKeepRunningChoices`
- `testVideoDocumentImportNativePiPAndLibraryFavorite`
- `testVideoRepeatsByDefaultWithNativePiPAndCanBeSwitchedOff`
- `testFinitePrompterCountdownAndRealNativeRewind`

Most wait for PiP to start in the simulator, or scroll to a control in a tool
editor. Earlier notes counted only a subset of the UI suite as passing on
Xcode 27.2. Fixed in build 30; see [build-30 notes](ui-tests-30.md).

`SubmissionScreenshotTests.testCaptureThirteenInchIPadScreenshots` fails on
an iPhone simulator by design. iPad screenshots are no longer needed.
