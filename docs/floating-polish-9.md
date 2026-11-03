# Cod Test 1.0 (9) — floating UI refinements

October 19, 2026. Local development candidate, not an App Store submission.

## Owner's requested changes

- Float and Tools are now one sectioned Float list: images/screenshots,
  references, time/focus, and reading. Library and Settings remain separate.
  Existing signed image Shortcuts and supported Share routes are unchanged.
- A teleprompter example seeds a fresh or migrated empty draft once. Existing
  scripts are preserved; clearing the draft after seeding stays cleared.
- Text and every live-tool editor expose native background/text color pickers,
  alongside presets. Custom colors reach actual raster/video frames.
- World Clock is called Current Time. Its preview reads the current system date
  even after closing PiP; it has no app-level Resume or Restart controls.
- Stopwatch pause/resume is directly available in the editor, with a current
  value readout, rather than only behind a second playback-controls screen.
- Timer has an optional Alarm when finished switch on iOS 26+. It is off by
  default and asks for AlarmKit authorization only on an explicit start.
- PDF rendering now explicitly scales small pages to the raster target before
  applying crop-box origin/rotation. The previous fitting transform centered
  small pages in excessive white padding. Crop also has 1–6× zoom, pinch,
  bounded pan/Move mode and Fit, without changing the pixel-space selection.

## Timing and alarm behavior

Current Time reads Date, not a count of callbacks. Elapsed tools now use Swift's
ContinuousClock so device sleep doesn't lose elapsed time. This doesn't promise
that iOS keeps drawing the PiP window while locked.

AlarmKit delivers the default alarm sound independently of PiP and Cod's process.
It uses a fixed-date, alert-only alarm; no countdown Live Activity is advertised
without implementing the required widget. NSAlarmKitUsageDescription explains
the permission. AlarmKit is weak-linked and guarded; older iOS gets the visual
timer and an explanation, not an unsupported alarm API call.

An enabled timer alarm starts even when PiP is unsupported or fails. Closing
PiP doesn't cancel it. Pause cancels its alarm; resume/restart recomputes the
finish date. Native AVKit setup/teardown callbacks mustn't disarm an alarm.
Scheduling/cancel operations are serialized so a late schedule cannot undo a
newer pause. Finishing the video countdown doesn't cancel an alarm as it rings.
Failures are visible and pause the timer rather than silently claiming success.

Identifiers and finish dates persist locally. Float lists scheduled timer alarms
with a cancel action, including after app relaunch. System-dismissed alarms are
reconciled against AlarmKit's current list. The alarm stays scheduled if the app
is terminated. Manually changing the device clock during a timer is an extended
physical test gate for this fixed-date approach.

## Verification

Artifacts: `/private/tmp/cod-polish9.0eRYwu`.

- All 102 unit tests passed in `units-final-ready9.xcresult`. Coverage includes
  real custom-color pixels, PDF edge/corner colors at up/downscaled resolutions,
  all four rotations with a non-origin crop box, zoom/pan pixel round trips,
  explicit stopwatch pause, a clock date advancing an hour, alarm error handling,
  rapid pause versus late schedule, and preserving alarms on close/completion.
- Cod Debug simulator, signed Debug device and unsigned Release device builds
  passed. Latest build logs: `device-ready9.log` and `release-ready9.log`.
- Supported-source and Release artifact audits passed. The development artifact
  is `DeviceData/Build/Products/Debug-iphoneos/Cod.app`, Cod Test,
  `com.josh.cod.store`, build 9. This does not validate distribution provisioning.
- Simulator UI checks passed for all color-capable editors, text/shared text,
  Current Time's controls, prompter editing, stopwatch pause, time editor discovery,
  large-text/dark forms, normal setup and landscape. The sectioned List required
  tests to reveal lazy rows rather than assume a pending-share retry card couldn't
  push Choose Photo below the initial large-text viewport.
- PDF zoom/pan selection and the corrected full-page scale passed on iPhone;
  the original failure was a test reading the accessible label instead of the
  zoom value. Final screenshots are in `ready-attachments`.
- Actual AlarmKit permission/scheduling/cancel passed on iPad. A real system
  Timer finished alarm appeared after terminating Cod on both iPad and iPhone;
  the iPhone evidence is `alarms-ready9.xcresult`. This is not simulated success.
- A later cancellation test needed to scroll UP the Float list to the alarm row,
  instead of continuing DOWN from the Timer entry. Its final rerun and the
  unchanged signed photo Shortcut regression both passed with zero failures in
  `final-regression9.xcresult`. The actual Shortcut delivered cold/warm 300×200
  and 148×92 image inputs, without manually activating Cod. Earlier failing
  runs remain in the artifact directory; they aren't counted as clean suites.

Cod Test 1.0 (9) was installed on the owner's iPhone 16 Pro Max on October 19,
2026. Installed name, bundle (`com.josh.cod.store`) and version were verified.
The original Cod installation/data weren't modified. Physical feature and sound
acceptance remains pending the owner's testing.

## Physical acceptance

1. Unified Float list, color pickers and existing image sharing still feel fast.
2. New empty prompter draft has useful text; existing scripts aren't overwritten.
3. PDF opens at a sensible scale, including crop, zoom, pan and the correct region.
4. Stopwatch Pause freezes elapsed time and Resume continues it.
5. Current Time has no Resume/Restart; check the selected time zone after locking.
6. Enable Alarm when finished, approve permission, and run a short timer while
   locked. Check actual sound/volume, Focus/silent mode and native Stop.
7. Pause/resume/restart, close PiP without canceling the alarm, cancel from Float,
   relaunch and confirm no stale alarm row. Test permission denial/revocation.

Original Cod app/data must remain untouched. Only Cod Test is installed. No
GitHub push or external publication is included. Apple alone decides App Review;
documented APIs are not preapproval for the existing non-video PiP use cases.

## Apple references

- [AlarmKit scheduling and authorization](https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit)
- [Alarm configuration](https://developer.apple.com/documentation/alarmkit/alarmmanager/alarmconfiguration/alarm(schedule:attributes:stopintent:secondaryintent:sound:))
- [Continuous clock](https://developer.apple.com/documentation/swift/clock/continuous)
- [PDF drawing transform](https://developer.apple.com/documentation/coregraphics/cgpdfpage/getdrawingtransform(_:rect:rotate:preserveaspectratio:))
