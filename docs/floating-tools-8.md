# Cod 1.0 (8) — floating tools

October 19, 2026. Local development candidate; not submitted to Apple.

## Requested scope

From the feature comparison: #1 typed/pasted/shared text, #2 PDF pages/regions,
#9 timers/countdowns/stopwatch/world clocks, #10 Pomodoro, plus auto-scrolling
teleprompter. Actual movie-file import, web browsers, telemetry and task-manager
features have not been added.

The existing Float tab remains image-first. Tools has a separate tab:

- Text: type or explicitly paste, choose size and dark/light/yellow colors,
  preview, then Float. Whitespace-only or illegibly long text is rejected rather
  than silently clipped. The draft persists locally; deleting its text clears it.
- PDF: select a local/provider PDF (up to 40 MB), select a page, Float Page or
  Crop a Region in the existing image editor. Render one bounded page at a time,
  preserving rotation and the original file. Locked PDFs require an unlocked copy.
- Timer: minutes/seconds, common quick durations, visible countdown to zero.
- Stopwatch: elapsed hours/minutes/seconds; pause/resume and restart.
- World Clock: searchable time-zone selection and 12/24-hour display.
- Pomodoro: configurable focus/break durations and session count; automatic
  transitions, ending after the last focus period without a final extra break.
- Teleprompter: local script draft, speed/text size/colors, smooth auto-scroll,
  stopping with the final lines still visible. This does not record video.

These are visual tools, not alarms. They schedule no sound/notification and do
not promise operation on a locked phone. Closing PiP pauses a live tool. The
session screen provides resume/restart and Float Again. PiP restoration returns
to tool controls rather than opening a meaningless image crop screen.

## Supported input and playback

The existing signed image Shortcuts have not been changed or re-signed.
Text can be shared to Cod's extension with the same manual-open / tapped local
notification route as images. The extension renders the supplied text locally
and never launches Cod. Float Text With Cod and Float PDF Page With Cod are
additional App Intent actions; a user-created Shortcut must bind their explicit
input. The PDF action defaults to page 1 and validates the requested page.
Explicit PDF document opening is registered separately from the Share extension.

Text and PDF references reuse the existing image → looping video player.
Live tools use AVSampleBufferDisplayLayer with real rasterized, timestamped
video frames and AVPictureInPictureSampleBufferPlaybackDelegate. Native controls
are preserved. No video-call placeholder, private selectors, suspension, source-
app inference, extension app launch or system-control hiding was added.

Elapsed-time state uses monotonic system uptime, not a count of timer callbacks.
The app declares the documented timer-use privacy reason 35F9.1; timing data is
not transmitted. Live rendering stops when its source is replaced or torn down.
Paused tools do not redraw; non-scrolling tools redraw only when their displayed
second changes. Prompter text layout is cached for playback.

Using public APIs does not preapprove these non-video content uses. Pop Out
Timer's historical 2.5.1 rejection and later approval are relevant review context,
not a guarantee in either direction. The submission draft discloses both paths.

## Verification

Local artifacts: `/private/tmp/cod-tools8.jmPMFc`.

- Initial Debug simulator build passed. Release device builds passed.
- All 88 unit tests passed on the iPad mini simulator, including the final
  candidate rerun (`units-ready8.xcresult`).
  Tests include timeline pause/resume/reset, timer/Pomodoro boundaries, time
  zones, malformed inputs, actual PDF page pixels/rotation, real video frame
  pixels/timestamps, native pause/resume delegate behavior, input precedence,
  teardown and the required privacy declaration.
- Initial tool UI runs exposed test-selector/navigation assumptions; the PDF
  page actually changed correctly and shared text was received. Tests were
  corrected against the captured accessibility hierarchy, not skipped.
- The full iPhone UI run exercised 20 cases (`ui-final.xcresult`): 16 passed;
  four checks hit automation assumptions (an offscreen large-text list entry,
  an application-coordinate landscape swipe, and foreground selection of
  Shortcuts' native Add Shortcut confirmation). Those checks were repaired,
  not skipped; all four passed in `final-smoke2.xcresult` with zero failures.
  The two installed signed image workflows delivered real screenshot input
  and the exact cold/warm 300×200 and 148×92 image fixtures without manually
  activating Cod. The signed workflow assets were not changed.
- The new iPhone text/share, PDF open/page/crop, prompter and time-tool UI cases
  passed. Four iPad tool UI cases passed with zero failures (`ipad-tools.xcresult`),
  including large text/dark appearance and playback-control navigation.
  Screenshots were inspected. The iPhone landscape case passed after anchoring
  gestures to its actual landscape scroll view. The previously documented
  iPad window-resize/landscape hardware acceptance gate still remains.
- Cod Debug simulator, Debug device and Release device builds passed. The final
  phone artifact is `DeviceData/Build/Products/Debug-iphoneos/Cod.app`, display
  name Cod Test, bundle `com.josh.cod.store`, build 8. Deep/strict signature
  verification passed using the Mac's trust services. The current development
  provisioning profile expires October 25, 2026; this is not distribution signing.
- Supported-source and Release artifact audits passed for the app and both
  extensions. Generated App Intents metadata contains both new reference
  actions. The hosted-policy and App Store distribution gates remain open.
- Simulator checks cannot establish visible or background PiP. In particular,
  unit tests exercise real video-frame creation and delegate behavior, not a
  simulator-only override that pretends PiP opened.

## Physical acceptance still required

The owner asked to finish simulator work before requesting phone access again.
Cod Test 1.0 (8) was installed and launched on the owner's iPhone 16 Pro Max
on October 19, 2026, after disabling the Mac's Tailscale exit node restored the
wireless developer connection. Installed bundle/version were verified as
`com.josh.cod.store` / `8`. The original Cod app and data were not modified.
Successful installation/launch does not establish the following physical PiP
acceptance checks; owner testing remains pending.

1. Existing Choose Photo and installed Share Shortcut, including replacement
   of an active tool by an image and of an image by a live tool.
2. Text and PDF full-page/region: actual content visible, native resize and restore.
3. Timer and Pomodoro: background ticking and phase transitions. These are not alarms.
4. Stopwatch and clock: background updates, pause/resume, correct selected zone.
5. Long prompter script: smooth background scroll, pause/resume, last-line hold.
6. Early restore, repeated replacement/close, music mixing and resource use.

The original installed Cod/data must remain untouched. Testing uses only Cod
Test (`com.josh.cod.store`). No App Store upload, external publication or GitHub
push is part of this feature implementation.

## Apple references

- [Sample-buffer PiP content source](https://developer.apple.com/documentation/avkit/avpictureinpicturecontroller/contentsource-swift.class/init(samplebufferdisplaylayer:playbackdelegate:))
- [Playback delegate](https://developer.apple.com/documentation/avkit/avpictureinpicturesamplebufferplaybackdelegate)
- [Required-reason categories, including timer use](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)
