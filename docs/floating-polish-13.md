# Cod Test 1.0 (13) — preview clarity and live color selection

## Changes

- The shared pinned editor header explicitly says Preview for text, teleprompter,
  timer, stopwatch, Current Time, Pomodoro, PDF pages and videos, including live
  tool controls. It remains separate from the editable settings. Preview sizing
  budgets for the extra label so smaller viewports still expose settings.
- The blank text example now says “Use the text editor below to write your own,
  or paste some text,” rather than inviting users to tap the rendered preview.
  Examples remain placeholders; they aren't saved as user drafts.
- Background/Text color rows still use Apple's native UIColorPickerViewController
  with live bindings, grid/spectrum/sliders and no alpha. Cod owns the SwiftUI
  sheet presentation and enables background interaction, leaving the exposed
  preview undimmed. Done/swipe dismissal retains the selected color; presets and
  reset remain available. No inspection/modification of system view hierarchies.
  A fully expanded picker can cover the preview; drag it down or dismiss to see it.
- Removed Home's duplicate Recent items section and its unused store dependency.
  Library history, thumbnails, favorites, retention and deletion are unchanged.
- No Share/Shortcut/Control entry-point changes, new permissions, media exports,
  timer/alarm behavior changes or original-Cod installation/data changes.

## Documented presentation APIs

- https://developer.apple.com/documentation/uikit/uicolorpickerviewcontroller
- https://developer.apple.com/documentation/swiftui/uiviewcontrollerrepresentable
- https://developer.apple.com/documentation/swiftui/view/presentationbackgroundinteraction(_:)
- https://developer.apple.com/documentation/swiftui/view/presentationdetents(_:)

## Verification

Results and captures: `/private/tmp/cod-polish13.Bifc8n`.
Cached products: `/private/tmp/cod-polish11.j0ZCx3/{BuildData,UIData,DeviceData,ReleaseData}`.

- `units13.xcresult`: 131/131 unit tests passed, including the new example-wording
  and rendering checks and all existing media, alarm, history and album-default tests.
- `phone13.xcresult`: 3/3 UI cases passed: native live colors, landscape/pinned
  preview, and largest accessibility text with the keyboard. Opening the picker
  leaves the actual preview pixels identical; selecting both background and text
  colors changes the preview pixels before dismissal. Preset reset also works.
- `color13final.xcresult`: repeated phone color/pixel comparison passed after the
  test helper stopped redundantly checking already-visible controls.
- `ipad13.xcresult` retained as a mixed run: all six color-capable editors' Preview
  labels/selectors and PDF page/crop passed. Home navigation rejected a visible
  bottom row because it reserved phone-tab-bar space on iPad; the video-to-library
  check raced native PiP/editor dismissal. These were test-navigation issues,
  corrected in test code without changing production playback/navigation.
- `ipad13fixed.xcresult`: 3/3 passed: Home has no recents while Library still has
  history, actual undimmed live colors/pixel comparisons on iPad, and real video
  import/native PiP/favoriting. Test navigation accounts for the iPad top tab bar,
  nested accessible tab buttons and asynchronous editor/PiP dismissal.
- Initial color-test instrumentation incorrectly required the underlying preview
  to be accessibility-hittable while UIKit's color picker was active. The native
  controller marks its accessibility container modal even when visually undimmed.
  The final test instead compares exposed preview pixels, checks live updates,
  and verifies its frame remains above the picker. Initial results are retained.
- Cod scheme Debug and Release device builds passed (`device13final.log` and
  `release13final.log`), as did strict/deep development-signature verification,
  `verify-supported-source.sh`, `verify-store-build.sh` on the Release app and
  `git diff --check`. These are not distribution validation or App Review approval.
- Cod Test 1.0 (13), `com.josh.cod.store`, installed successfully on the paired
  iPhone 16 Pro Max Jay. Original Cod and its data were not targeted. No phone
  clipboard, Photos content, Shortcuts, settings or Library items were reset.

Phone acceptance: open Text or a live tool, check the separate Preview label,
change both colors while watching the preview, then return to Float and Library.
