# Cod Test 1.0 (11) — consolidated imports and pinned editors

## Implemented

- Media & Documents: a combined Photos image/video picker, compact image Crop
  and latest-screenshot actions, Paste Image, and one Choose File entry point.
  The file importer accepts image/movie/PDF UTTypes and validates actual input.
  Images open the crop/Float surface, videos open native playback controls,
  and PDFs open page selection/cropping. Unsupported/corrupt files show errors.
- Text & Reading groups Text and Teleprompter. No separate Videos/Choose PDF
  sections. Existing image Shortcut packages/actions are unchanged.
- Shared editor layout pins rounded previews and the primary Float action above
  scrolling settings. Header height adapts to available space and the keyboard.
  Rounded clipping applies only to the in-app preview, not generated video pixels.
- Timer/Pomodoro use a circular ring with 20 fps changing frames rather than
  whole-second progress jumps. Whole-second clocks/stopwatches stay at 1 fps;
  optional stopwatch hundredths use 30 fps; prompter remains 15 fps. Paused
  sources don't generate frames. Timing is still monotonic, not callback counting.
- Timer's persisted Keep running when PiP closes switch defaults on. Off pauses
  the timer and cancels its alarm on close; PiP restoration preserves the timer.
  Locking may also close PiP, disclosed beside Off. Closed visual-only timers
  remain accessible on Float until Cod quits; AlarmKit timers survive termination.
- Stopwatch's persisted Show hundredths switch uses `.00`, not milliseconds.
- Favorites have a stable section above newest-first recent history. New favorites
  append in favorite order, left-to-right then the next row; unfavorite/re-favorite
  appends again. Older indexes migrate without dropping media/favorite flags.
- Both Library and Settings offer an explicit Clear Library confirmation:
  Clear Recent History preserves favorites; Delete Everything, Including Favorites
  removes all Cod history/favorites. Neither deletes original Photos/Files media,
  pending shared input, preferences or text/script drafts.

## Alarm investigation and limits

Physical build-10 logs included a one-second timer entering the native alert state
about one second after its recorded deadline, while several five-second timers
were close. Those logs don't measure acoustic onset.

Build 11 observes documented ActivityKit countdown updates to replace provisional
deadlines with AlarmKit's actual fire date even if the Live Activity arrives after
schedule() returns. Session timing is reconciled without reviving cancelled timers.
Diagnostics distinguish estimated/system deadlines, scheduling latency, deadline
corrections and the first observed alert transition. No duplicate local sound,
private API, app suspension or background-audio workaround was added.

The two-second foreground/music simulator test observed the system alert state
about 6 ms after its authoritative deadline. One-second foreground/music and both
native PiP close policies also passed individually. This does NOT prove audible
phone timing or fix an OS-side delivery delay. Retest acoustic onset with music,
Cod foreground/background and phone locked before declaring that issue resolved.

## Verification

Artifacts: `/private/tmp/cod-polish11.j0ZCx3`.

- Debug simulator, signed Debug iPhone and unsigned Release device builds passed.
- All **125 unit tests passed**, `units11final.xcresult` (final-source rerun:
  `units11shipping.xcresult`).
- Targeted UI evidence includes unified-file picker discovery, PDF page/crop/zoom,
  sticky timer preview/preferences, stopwatch hundredths, keyboard/large text,
  compact photo/screenshot actions, word-mode placeholders, remembered duration,
  history-deletion cancellation, native video PiP, Favorites ordering, native
  timer-close policies and one-/two-second foreground/music alerts. See the
  result bundles for individual outcomes; corrected test retries are recorded.
- Clean final single-case bundles: `library11final.xcresult` (Favorites/clear
  choices), `landscape11.xcresult` (phone landscape), and `shortcut11.xcresult`
  (signed image Shortcut, actual cold 300×200 and warm 148×92 inputs). The earlier
  mixed bundles retain the initial test-navigation failures and passing cases;
  they are not represented as a clean full-suite run.
- Early UI iterations exposed an inherited accessibility identifier on the
  transparent header (fixed), iPad top-tab assumptions, PiP occluding a menu,
  and a clipped landscape list row incorrectly reported hittable by iOS. Test
  navigation checks real geometry and stops test PiP before opening that menu.
- Supported-source guard and Release artifact guard passed. Signed Debug artifact
  passed deep/strict signature verification. App Store submission/approval is not
  established by these checks.

Cod Test build 11 was installed on the paired iPhone 16 Pro Max `Jay` using only
`com.josh.cod.store`. The original Cod installation/data were not targeted.

## Physical acceptance

1. Choose an image and video from Photos; choose image/video/PDF from Files.
2. Scroll tool settings with normal/largest text, keyboard open and landscape;
   confirm preview/Float remain usable and PiP content matches the preview.
3. Test short and long timers with music, foreground, background and lock.
   Check audible timing, then close PiP with Keep running both On and Off.
4. Try stopwatch hundredths and native play/pause/restore.
5. Favorite multiple items, add history and verify stable favorite positions.
   Test Clear Recent History versus Delete Everything only on disposable items.
6. Retest the existing Share → Float with Cod image Shortcut; no recreation needed.
