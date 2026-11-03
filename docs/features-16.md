# Cod Test 1.0 (16) — readable, reusable references

The owner selected research candidates **1, 2, 3, 4, 6, 10, 11 and 12**.
The other candidates remain ideas, not implementation tasks or release gates.

## Implemented

- **1 — Image to readable text:** Read Text in the image-reference picker,
  crop options and Library image detail runs on-device recognition. The result
  is editable and reflows wrapped lines. Compare with the original image,
  reflow current edits, explicitly restore recognized line breaks, or send a
  longer passage to the teleprompter. Numbers and wording are not intentionally
  rewritten; recognition can still be wrong. Still text is limited to 2,000
  characters; the teleprompter accepts up to 20,000.
- **2 — Named cards and presets:** Save editable text, scripts and time-tool
  configurations in Library → Saved cards & presets. Reopen and update the same
  reference instead of saving only a bitmap. Source, colors, layout and timing
  are retained. Saved references work with History off; clearing recent history
  preserves them, while Delete Everything also removes them. No iCloud sync.
- **3 — Reference-specific entry points:** Float Saved Reference is an App
  Intent that selects a saved card, tool preset or Library favorite by stable
  identifier. It is available to Shortcuts, plus a configurable Home Screen
  widget and Control Center/Lock Screen control on iOS 18+. A chosen Shortcut can be
  assigned to Back Tap or the Action Button. These authenticated actions open
  Cod; users configure Apple's system surfaces. Removed references show an
  error rather than floating unrelated content. Widgets show names, not note
  text or media; avoid sensitive reference names on shared screens.
  System colors use Cod's own window traits, including the inactive scene
  while Control Center dismisses, rather than forcing Light during handoff.
- **4 — Finite reference scrolling:** Auto-scroll images and selected PDF page
  ranges with speed, position preview, pause and actual timeline seeking. The
  last region remains visible. PDF input is bounded to 20 pages and the overall
  scrolling canvas to 24,000 pixels in height. Only visible page portions are
  drawn; this is not touch-scrolling inside PiP. Image decoding is bounded to
  50 MB input, 16 million pixels, 4,096-pixel width and 12,000-pixel height.
- **6 — Video region crop:** Choose a spatial region from the oriented poster
  frame and prepare a local cropped video. Sound/repeat remain available.
  Reset to the original without modifying the source. Preparation can take
  time; protected or unsupported media are not promised.
- **10 — Teleprompter layout:** Optional reading-line guide and line spacing
  for scrolling mode, plus side margins in both modes. Irrelevant guide/spacing
  controls are hidden in centered word mode. Settings are saved with scripts.
- **11 — Target reading duration:** Finish in… calculates scrolling or word
  pace for 15 seconds through one hour, with the existing countdown added
  separately. In-app playback controls show the remaining playback time.
  Pause, rewind and seeking remain finite. This controls playback
  pacing, not the speaker's actual finishing time.
- **12 — Animated GIFs:** Local ImageIO/AVFoundation conversion preserves frame
  order and timing as real H.264 video. Photos, Files, explicit clipboard paste
  and the image App Intent retain GIF data when the provider supplies it.
  Maximum 50 MB, 600 frames and two minutes; very short delays are bounded to
  20 ms. Optimized delta frames are composited. Video sound/repeat/crop controls
  apply to the resulting clip. A share provider that supplies only a still
  UIImage cannot recover lost motion; the app-icon Share extension still queues
  a still image. Prefer Choose Photo or Choose File for GIFs.

## Verification

Logs and result bundles: `/private/tmp/cod-features16.Usgtmx`.

- **176 unit tests passed, zero failures**, including actual Vision recognition
  of text/numbers, saved-source persistence and update/deletion, corrupt-index
  protection, color/configuration round trips, exact intent identifiers,
  timed scroll/word/countdown math, guide layout, finite PDF/image playback,
  GIF frame decoding/compositing/timing, oriented video crop pixels/duration and
  light/dark reading-guide alpha blending. Final suite:
  `units16finalready.xcresult`; `units16acceptance.xcresult` and
  `units16handoff.xcresult` also passed 176 (the preceding
  `units16complete.xcresult` passed 175).
- iPhone simulator UI passes cover saving/reopening text cards, saving timed
  scripts with reading guides, PDF page-range preparation and seeking, video
  cropping/reset, GIF import through Photos and native control-gallery
  registration. Results: `ui16.xcresult`, `ui16native.xcresult`,
  `ui16control.xcresult`, `ui16fix.xcresult`.
- Existing entry-point regressions passed: signed Share Shortcut installation
  and cold/warm delivery of two different images; app-icon sharing does not
  launch Cod and delivers on manual activation; One tap float Off opens crop
  and cancelled input does not replay. Results: `ui16regression.xcresult`.
  That bundle also records an initial control-test failure: receipt was checked
  behind a still-open editor/lazy-list scroll offset even though the app log
  recorded its 900-pixel card input. **The corrected control test passed**:
  choose the newly saved card in Apple's native configuration picker, tap its
  configured control, verify Cod opens and reveal the actual image receipt on
  Float. Result: `ui16controlverified.xcresult`.
- iPad simulator checks passed for saved-card editing/reopening and timed script
  saving (`ipad16.xcresult` / `ipad16final.xcresult`), plus corrected PDF page
  entry, preparation and finite playback (`ipad16pdfverified.xcresult`). The
  initial PDF check exposed an unreliable wide-row tap/keyboard interaction;
  fields now retain visible labels, offer Done, and Prepare has an explicit
  full-width button target. Tests select the existing trailing digit rather
  than assuming the caret is after it (which entered `21` on the phone).
  Script/card screenshots were inspected; the corrected guide preview was
  checked visually as well as with the unit test. These checks do not certify
  all iPad landscape/window sizes or visible PiP.
- The final PDF selection flow passed on both iPhone and iPad with explicit
  replacement of the existing number: `phone16pdffinal.xcresult` and
  `ipad16pdffinal.xcresult`. Playback controls and preparation were exercised.
- Debug signed device and Release device builds passed. The signed Debug build
  is **Cod Test**, bundle `com.josh.cod.store`; deep signature verification
  passed. The widget's App Group entitlement and both targets' saved-reference
  App Intent metadata are present. Build 16 was installed and launched on the
  current Jay (iPhone 16 Pro Max) on October 20, 2026. Installation updated only
  `com.josh.cod.store`; physical feature acceptance is still pending.
  Final build logs: `device16finalready.log` and `release16finalready.log`.
- Supported-source and Release artifact audits passed, including the new shared
  catalog configuration and intent metadata checks. The artifact is not a
  distribution-signed archive; submission-mode privacy-URL validation remains
  a release gate.

Earlier checks exposed and fixed crop export extending short clip durations,
tiny H.264 rasters that encoded but did not decode, an opaque reading-guide band
caused by copy blending, and test gestures changing wheel/toggle values instead
of scrolling. Native Open In can present a Share
extension rather than directly open the app; the GIF test uses a real Photos
picker import instead of assuming a launch.

## Still requires physical acceptance

The tested iPhone simulator runtimes report native PiP unavailable; the GIF UI
test checks that failure is explained and input remains usable. Other simulator
tool tests exercise the actual in-app playback model, not visible floating
picture quality. Earlier simulator runs showed black sample-buffer PiP pictures.
Neither is counted as a successful phone PiP, smoothness or power-use test.

Verify recognition accuracy on real screenshots; persistent editing and deletion;
chosen-card/favorite Shortcut, widget and control handoffs; scrolling readability
and pause/seek; crop orientation/sound; GIF motion/repeat; and target-duration
prompter pacing/guide/countdown on the phone. Existing timer-alarm timing and
general PiP reliability checks remain open in the [MVP checklist](../MVP_CHECKLIST.md).

Only documented APIs are used. The Share extension does not launch the app;
Shortcut/system-control/user-tapped-notification/manual-open behavior remains.
No automatic return to the previous app, hidden native controls or App Review
approval guarantee is introduced. The original Cod installation/data are untouched.

Apple references: [configurable controls and OpenIntent](https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system),
[ImageIO frame properties](https://developer.apple.com/documentation/imageio/cgimagesourcecopypropertiesatindex(_:_:_:)),
[video composition](https://developer.apple.com/documentation/avfoundation/avvideocomposition).
