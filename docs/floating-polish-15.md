# Cod Test 1.0 (15) — current-time usability and smoother scrolling

## Changes

- Time Zone search explicitly uses Apple's always-visible navigation search
  placement. Opening the picker no longer requires pulling the list downward.
- Current Time's setup preview updates once per second from the real system
  date, independent of editing. Its accessible value updates too.
- Reset sizes to preset appears only when a location/time/date size differs
  from the defaults (44/100/36). It resets all three sizes, including hidden
  lines, remembers the reset and leaves colors/line visibility untouched.
- System is the default preset for text and all generated tools. Dark, Light,
  Yellow and custom colors remain. SwiftUI's actual appearance is explicitly
  resolved for previews; custom colors override the preset. Live tools also
  read their own source view's documented traits and update System appearance
  without restarting, seeking or rescheduling alarms. Gray samples still work.
  Still-text images capture the selected appearance when generated; they are
  still images, not reactive UI snapshots.
- Scrolling teleprompters target 60 fps instead of 15. Deadline-based pacing
  subtracts rendering work rather than appending a full sleep to every frame,
  and skips stale catch-up work after a delay. Cached TextKit layout draws only
  visible glyphs with fractional positioning, avoiding full-script layout per
  frame and whole-pixel steps. Word mode remains 15 fps; clocks remain 1 fps.
- Steady script playback no longer resets the video timebase on every frame.
  Pause/resume/seek still synchronize immediately; large drift reconciles.
  Paused content remains deduplicated but can refresh for an explicit seek or
  appearance change. Countdown, script speed/duration, finite rewind and final
  text hold are preserved; appearance changes do not alter elapsed time.
- No Share entry-point, permission, library-retention or alarm-policy changes.
  Dedicated-album saving remains off by default; saved choices are preserved.

## Verification

Results/logs: `/private/tmp/cod-polish15.9ntOrB`.

- Cod Debug signed device build and unsigned Release device build succeeded
  (`device15.log`, `release15.log`); Debug signature verification passed.
- 150/150 unit tests passed (`units15final.xcresult`). New tests cover System
  colors and custom/gray overrides, legacy preset decoding, size reset isolation,
  appearance updates preserving playback, frame cadence/deadline math and cached
  fractional scrolling/final hold. The initial pacing-test expectation for an
  invalid-fps input was corrected to match the explicit bounded fallback.
- Four iPad UI tests passed (`ipad15.xcresult`): immediately visible time-zone
  search and selecting Tokyo; preview ticking with no setting interaction;
  conditional/reset/persisted clock sizes; System/fixed presets; and real native
  PiP ten-second rewind moving the actual paused script. Preset and search
  screenshots were visually inspected.
- Four iPhone UI tests passed (`phone15.xcresult`): search/selection, ticking and
  size reset, preset choices, and native custom colors updating without dimming
  the preview. The existing color test explicitly chooses Dark so selecting
  White still changes its starting background after the new System default.
- A cached roughly 16,000-character script rendered 60 frames in about 0.013
  seconds on this Mac's simulator unit-test process. This measures rasterization
  only, not end-to-end phone throughput, power consumption or native PiP FPS.
- Source regression audit, Release artifact audit and whitespace checks passed.
  These are local checks, not distribution validation or an App Review promise.

## Device acceptance

The simulator still shows black native PiP pictures for sample-buffer tools;
callback/seek success is not counted as a visible-picture or smoothness pass.
The owner's build-14 feedback describes visible script motion on the phone, but
build 15's subjective scrolling improvement still requires a phone check.
Cod Test 15 installed successfully on the current Jay (iPhone 16 Pro Max),
bundle `com.josh.cod.store`. The subsequent launch was denied because the phone
had locked; the owner can open Cod Test normally when ready. No physical visual
pass is claimed. The original Cod app/data were not touched.

## Apple references

- [Always-visible navigation search](https://developer.apple.com/documentation/swiftui/searchfieldplacement/navigationbardrawerdisplaymode/always)
- [Visible glyph range](https://developer.apple.com/documentation/uikit/nslayoutmanager/glyphrange(forboundingrect:in:))
- [TextKit layout/drawing](https://developer.apple.com/documentation/uikit/nslayoutmanager)
- [Nonblocking task sleep and tolerance](https://developer.apple.com/documentation/swift/task/sleep(for:tolerance:clock:))
