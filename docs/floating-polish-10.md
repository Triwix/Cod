# Cod Test 1.0 (10) — UI, video, favorites and timer refinement

Implemented October 19, 2026. Installed and verified on the owner's current
iPhone 16 Pro Max as **Cod Test**, `com.josh.cod.store`, version 1.0 / build 10.
The original Cod installation and its data were not changed. No commit or push
was performed for this batch.

## Changes

- Photo and latest-screenshot sources have compact horizontal Float/Crop pairs;
  accessibility text sizes use a stacked layout. Paste Image remains directly
  available. Explicit Crop always crops, independent of automatic arrival mode
  and One tap float. The same correction applies to explicit Crop Shortcuts.
- Text and Teleprompter show gray example placeholders, not editable/persisted
  sample drafts. Focusing the empty field starts an empty draft; typing replaces
  the placeholder. Float uses the sample if the draft is blank. Clear sits next
  to Paste. The previous auto-seeded sample migrates back to a placeholder;
  edited scripts are preserved.
- Preview and Float are at the top of text and live-tool editors. Readability
  settings still control the actual rendered preview. PDF workflow is unchanged.
- Teleprompter retains scrolling and adds centered word groups (1–8 words) and
  adjustable words per minute. The final group remains visible; pause/restart
  and native PiP controls remain available.
- Actual local video imports from Photos, Files and explicit document opening,
  with validation for playable, non-protected video, bounded to 500 MB per import.
  Video plays once with a real inline player layer and native PiP pause/seek
  controls, separate from the unchanged still-image encoder. Sound defaults off
  and can be enabled. Cod owns copies; cleanup never removes original media.
  With history on, a video copy and thumbnail are retained for replay/favorites.
  The existing bundled Share Shortcut remains image-only.
- Library can enable History directly. Stars and a Favorites filter support
  deliberate saves. Favorites survive history limits, Off and Clear History;
  explicit Delete removes a favorite. Older indexes decode without losing
  captures. OCR enrichment doesn't overwrite a favorite's flag.
- Removed in-app pin overlays, manager, settings, actions and Clear Pins Shortcut.
  Only the retired action's decoding value remains, filtered out of UI/execution
  so old preferences don't reset. Native PiP floating is retained.
- Timer remembers duration with Clock-style hour/minute/second wheels, including
  after relaunch. Duration is bounded to 23:59:59; zero cannot start a timer.

## Timer correction

Previously, the timer started while PiP was still being prepared. It also used
an absolute-date alarm, and an AVKit playback-pause callback could cancel an
alarm during completion or a system transition.

The new countdown starts after PiP confirms opening. If PiP is unsupported or
fails, an explicitly enabled alarm can still start as an in-app fallback.
Alarm scheduling is serialized, and its asynchronous setup isn't deducted from
the displayed duration. A native AlarmKit duration timer replaces the fixed-date
alarm. The required countdown widget/Live Activity is included in CodControls;
its cancel intent is registered in both the app and widget targets.

Automatic completion leaves the system alarm alone. Native pause callbacks
are checked after teardown transitions settle, and audio interruption isn't
treated as user cancellation. Explicit Pause/Cancel still updates the alarm.
Closing PiP does not cancel an enabled alarm. Other tools and visual-only timers
do not schedule alarms. iOS 26+ and alarm permission remain required; older
devices retain visual timers. AlarmKit is weak-linked for the iOS 17 app target.

This is Cod's own system alarm, not an existing timer in the Clock app. Music
mixing remains a separate audio preference. Simulator tests establish delivery
and state transitions, not acoustic performance on physical speakers/headphones.

## Verification

Artifacts and results: `/private/tmp/cod-finish10.AjgpE6`.

- Debug signed device build: `DeviceData/Build/Products/Debug-iphoneos/Cod.app`.
- Release build: `ReleaseData/Build/Products/Release-iphoneos/Cod.app`.
- Full unit suite: **112/112 passed**, `units10final.xcresult`.
- Native iPad simulator tests: **4/4 passed**, `native10ready.xcresult`: actual
  video PiP/favorite/filter; two-second alarm with Cod foreground; delivery after
  Cod is terminated; scheduling/cancellation from Float.
- A final audio rerun explicitly verifies that the separate harness audio player
  starts before opening Cod: **1/1 passed**, `audio10verified.xcresult`.
  Test audio is audible playback in the test harness only, never a production
  silent-audio keepalive. Physical music/alarm output still needs owner QA.
- Phone simulator: direct history enabling, compact action pairs and actual
  signed Share Shortcut cold/warm image delivery passed in `phone10ready.xcresult`.
  Its history safety case initially used an ambiguous Float tab/action selector;
  corrected case passed separately, **1/1**, `history10final.xcresult`.
- Text editing/clear/placeholders, word mode, remembered wheels, all live editor
  discovery, largest-text Home and actual iPhone landscape/dark checks passed
  across `ui10.xcresult` and `ui10b.xcresult` targeted runs. Early duplicate Done
  buttons were fixed. Early wheel tests were corrected to address the child
  wheel of the identified picker. These are not a claim of one clean all-tests
  UI run or comprehensive accessibility certification.
- Inspected the actual video PiP screenshot: colored moving fixture content and
  native pause, ±10-second seek and timeline controls, not a blank/gray window.
- Supported-source guard, final Release artifact audit, deep/strict device
  signature verification, and `git diff --check` passed. Verified AlarmKit's weak
  linkage and cancel-intent metadata in both required bundles.

## Phone acceptance

1. With music playing, float a two-second alarm-enabled timer while staying in
   Cod. Confirm a full countdown and audible alarm without leaving Cod. Repeat
   with a longer duration, in another app, locked, and with headphones as needed.
2. Change hours/minutes/seconds, leave/reopen Cod, and confirm the chosen duration.
3. Check compact photo Float/Crop, empty example/typed/Clear text, both prompter
   modes and readability changes. Existing image Share Shortcut needs no rebuild.
4. Import a real video with sound from Photos/Files; float, resize, pause, seek,
   restore, close and replay it from Library. Test Video sound separately.
5. Favorite an image/video, change the history limit or Clear History, and confirm
   it stays. Test explicit deletion and the system Live Activity cancel control.

Store submission still requires the owner/account/policy/distribution gates in
`APP_STORE_RELEASE.md`. Documented APIs and these checks are not App Review
preapproval for still-image or other nontraditional PiP content.

Apple references used for this implementation:

- [AlarmKit scheduling and countdown widget requirements](https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit)
- [Native duration timer configuration](https://developer.apple.com/documentation/alarmkit/alarmmanager/alarmconfiguration/timer(duration:attributes:stopintent:secondaryintent:sound:))
- [Live Activity interaction and app-target intent registration](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)
