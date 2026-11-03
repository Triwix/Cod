# Cod Test 1.0 (14) — playback, references and clearer supported sharing

## Changes

- Shared-image guidance explicitly says Share → Cod needs a notification tap or
  manual opening; the installed Float with Cod Shortcut opens Cod directly.
  One tap float only skips cropping. The guide explains the extension/app boundary,
  optional user-added Lock Screen control and iOS's restore/full-screen button.
  Floating status now says Cod doesn't switch apps for the user.
- No new confirmation tap in successful Share handoffs. If the image was saved
  but notification delivery is unavailable, the extension shows Image ready with
  manual-open instructions instead of an inaccurate failed-image message. A
  genuine storage failure still reports failure. Crop UI explains the next step.
- Manual opening can receive a pending share even with notification mode enabled.
  Explicit Shortcut/document input still wins; request-ID matching, expiration,
  single claiming and explicit retry rules remain. No extension-side app launch.
- Teleprompter countdown defaults on at three seconds, adjustable 1–60 seconds
  and remembered. It starts with playback after PiP opens, not during preparation;
  pause, close/resume and restart operate on the same actual timeline.
- Both prompter modes now have finite, seekable playback. Frames are rendered on
  demand, not pre-exported into a potentially huge movie. The sample-buffer timebase
  follows actual script position; finite ranges, end clamping and native skip
  completions are implemented. Public requiresLinearPlayback is off for scripts.
  In-app position and ±10s controls supplement iOS's native controls; iOS chooses
  its own native skip interval. Seeking paused content doesn't resume it, Play at
  the end deliberately replays, and the last text remains visible at completion.
  Frame queueing uses the documented iOS 17+ sample-buffer renderer consistently.
  BGRA pixel buffers now write real premultiplied alpha instead of leaving a
  skipped channel undefined; an opaque-frame regression test checks it.
- Still images, text and PDF pages keep their working still-frame video loops.
  Current Time must stay current; stopwatch has no defined end. Timer/Pomodoro
  remain non-seekable elapsed sessions: seeking their pixels alone must not
  desynchronize real alarms or alter an actual elapsed measurement.
- Current Time can hide/show location, zone abbreviation and date, and adjust
  location/time/date sizes independently. Abbreviations are date-specific (DST
  aware, or GMT offsets when supplied by Foundation). Three-line layout fits
  the content area; hidden lines don't reserve space. Preferences are remembered.
- PDF page numbers can be typed or stepped. Out-of-range/empty input cannot float
  or crop an old page; selected/rendered page identity is checked before actions.
- Full guided onboarding is deferred. Snapper inspiration is credited in README,
  not app branding/store metadata. This is a conservative editorial choice, not a
  claim that mentioning jailbreak inspiration automatically causes rejection.

## Primary references

- https://developer.apple.com/documentation/avkit/avpictureinpicturesamplebufferplaybackdelegate/pictureinpicturecontrollertimerangeforplayback(_:)
- https://developer.apple.com/documentation/avkit/avpictureinpicturesamplebufferplaybackdelegate/pictureinpicturecontroller(_:skipbyinterval:completion:)
- https://developer.apple.com/videos/play/wwdc2021/10290/
- https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionOverview.html
- https://support.apple.com/guide/iphone/multitask-with-picture-in-picture-iphcc3587b5d/ios
- https://support.apple.com/en-us/102638
- https://developer.apple.com/app-store/review/guidelines/ (metadata, copycat and IP rules)

## Verification

Logs/results: `/private/tmp/cod-polish14.Mfj4GV`.

- Cod Debug and unsigned Release device builds succeeded (`device14final.log`,
  `release14final.log`); the Debug app's signature verified. No distribution
  archive or App Review approval is claimed.
- 142/142 unit tests passed (`units14alpha.xcresult`), covering countdown/frame
  rendering, finite timing and real seek callbacks, paused/end/replay behavior,
  clock line sizing/DST and typed PDF-page validation, plus existing regressions.
- Seven real Share-extension tests passed (`share14final.xcresult`): manual and
  notification handoffs, whole-image/crop behavior, and manual activation while
  notification handoff is configured. Successful shares still dismiss without
  an added Done tap. Explicit notification taps were exercised by simulator UI.
- The bundled signed Share Shortcut delivered the supplied 300×200 cold-launch
  and 148×92 warm-launch images (`shortcut14b.xcresult`). One earlier run supplied
  zero input bytes on the second share; the repeated real handoff passed. Keep
  import failures/retries in the physical acceptance sweep, not silently certified.
- iPad Current Time display/persistence and typed PDF valid/invalid-page checks
  passed (`ipad14b.xcresult`, `ipad14.xcresult`). The native prompter's ten-second
  back button changed the actual paused script position by ten seconds, not just
  its progress display (`visible14.xcresult`, prompter case). The separate clock
  control check passed after the test opened the currently-floating session from
  Home (`clock14final.xcresult`); it has no Resume/Restart controls.
- The same clock line/size/persistence and typed PDF-page checks also passed on
  the iPhone simulator (`phone14.xcresult`, two tests), exercising its smaller UI.
- Source regression audit, Release `Tools/verify-store-build.sh` artifact audit,
  and whitespace checks passed. Submission mode is still gated by the hosted
  privacy policy and distribution provisioning.
- Native imported-video PiP repeated the real three-second fixture, could stop
  repeating, and defaulted back to Repeat On for a newly opened video
  (`video14.xcresult`). Its PiP picture was visibly present in the captured frame;
  the black-picture observation below is specific to the sample-buffer tools.

### Still open — do not count as visually verified

The iPad simulator opens a native PiP window and its pause/rewind callbacks work,
but its video picture is black for BOTH finite scripts and the existing live
clock. This was observed in XCTest captures and directly in Simulator's window.
Public renderer status reported ready/rendering with no error and matching
timebases. Switching to the current renderer, explicit BGRA alpha, and checking
an opaque source host did not establish a visible picture; the speculative host
opacity change and temporary diagnostics were removed. It is not yet established
whether this is simulator-specific. No visual playback pass is claimed.

After the owner unlocked the phone, Cod Test 14 installed successfully on the
current Jay (iPhone 16 Pro Max), bundle `com.josh.cod.store`. Actual-picture,
countdown and native-rewind acceptance on the phone is still pending. The
original Cod installation and data have not been touched.
