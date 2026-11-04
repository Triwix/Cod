# Crop audit follow-up · 1.0 (25)

November 4, 2026. Branch: `codex/crop-interaction-followup25`.

The [updated external audit](https://cod-launch-b13d0b.sites.tab.bot/) confirms
build 24's fixes and adds three low-priority crop interaction notes. This update
addresses those notes without changing supported launch routes or permissions.

## Changes

- Double-tap and the canvas's Float selection accessibility action now use the
  same effective action list as the visible bar. Hiding Float in Settings hides
  both. The Share extension's explicit `[.float]` override continues to work;
  video-region Apply Crop still requires its own button.
- Only the **existing selected region** has a double-tap recognizer. The rest of
  the canvas has an immediate single-tap recognizer, so selecting a detected
  block or clearing a selection no longer waits for a second tap to fail.
  A first tap that creates a new selection cannot count as the first tap of the
  new region's separate double-tap recognizer. Dragging has priority over taps;
  pinching remains simultaneous. Both surfaces use the same named coordinate
  space for pixel mapping, zoom and pan.
- Canvas and steppers share an eight-pixel minimum. An image narrower/shorter
  than eight pixels keeps its actual full extent. A previously smaller selection
  can grow without forcing the opposite edge to move or creating invalid ranges;
  it cannot be shrunk further. Ordinary selections cannot be reduced below eight
  pixels with the steppers. The double-tap hint is hidden in Move mode.

An outside tap retains its usual clear/select behavior. Double-tapping outside
does not Float; it need not preserve the old selection. The UI regression check
now reflects this distinction and reselects the exact region before floating.

## Verification

Artifacts: `/private/tmp/cod-release25.bmKcmtm5`.

- **Nine host XCTest cases pass:** eight geometry/minimum-size cases and the
  settings-to-gesture regression. A temporary macOS Swift package uses symbolic
  links to the actual repository source/test files, including AppSettings,
  SnapAction and CropInteractionPolicy. The test uses a disposable UserDefaults
  suite and in-memory share preferences; it does not read/change live Keychain
  choices. These are host cases, not an iOS unit-suite pass (`crop-host25.log`).
- **Sixteen artifact/source guard tests pass** on disposable copies of the real
  Release app (`verifier25.log`). The source guard and Release artifact audit
  pass. The hosted-policy submission gate remains required.
- Cod / Debug, the unit-test bundle, launch harness and affected UI-test bundle
  compile; Cod / Release archive passes. No concurrency warnings were emitted.
  A signed Debug device build and deep/strict signature check pass. The Release
  archive is unsigned local verification, not distribution/TestFlight validation.
- Both iOS unit and affected UI execution were attempted again. Apple's
  DTServiceHub/lockdown test service failed before any case started. The runs
  were stopped after repeated startup failures (`unit25.log`, `ui25.log`). No
  iOS suite or automated UI case is counted as passed for this build.

## Interactive Simulator check

The Mac was unlocked and the previous visual-check blocker is removed. Cod Test
was installed only in the disposable iPhone simulator (iOS 26.5). Using the real
app UI and its saved stock-photo fixture:

- Opened Library → image context menu → Re-crop, selected the whole image, and
  double-tapped the actual crop canvas. The Float action ran, saved its history
  entry, and displayed AVKit's **Not available here** recovery state. This
  simulator does not support PiP; no floating-picture acceptance is claimed.
- Opened Adjust crop through the canvas accessibility action, incremented Left
  and Top from 0 to 1, and confirmed both the sheet and canvas changed from
  **4096 × 2720** to **4095 × 2719**. All four native edge controls were exposed.
- Changed zoom from 100% to 200% without changing those pixel dimensions.
  Entered Move mode, double-tapped the canvas and confirmed no Float occurred.
- Opened the Floating Guide, checked its explanations, and scrolled through both
  Back Tap flows, the exact Screenshot variable binding and the statement that
  Crop With Cod ignores One tap float. Text was visually inspected for legibility.

Direct pointer drags did not produce a verifiable change through the Mac's
simulator-control surface. Do not count dragging, resizing, pinch interaction,
selection-boundary taps or subjective tap latency as passed; finish these on a
working interactive setup/phone. The final hint-only change was compiled after
the interactive check. This does not replace the unexecuted automated UI cases.

Build 25 is prepared but **not installed on the phone**. The original Cod app and
data remain untouched. Physical PiP/alarms/import/control acceptance, iOS 17/18
launch, a compatible test toolchain, owner-deferred publishing details and signed
distribution validation remain in the [MVP checklist](../MVP_CHECKLIST.md).
