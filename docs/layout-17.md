# Cod Test 1.0 (17) — consolidated text and PDF editors

## Changes

- Home has one **Text** entry. The duplicate Image reference and Teleprompter
  rows are removed. Import Photo lives in Text and performs on-device text
  recognition; image detail/crop options offer one Use in Text action.
- A **Teleprompter** switch in that editor reveals presentation, pace, countdown
  and layout options. Switching retains editable text, colors, font size and
  script settings. Still cards keep the 2,000-character limit; scripts keep
  20,000. Switching a long script off reports the limit without truncating it.
- Imported photos retain the original comparison. With Teleprompter on,
  **Keep original image layout** scrolls the bitmap instead of reflowed text.
  This preserves image scrolling, which is distinct from text recognition.
  Appearance controls are hidden for original-layout playback. Named saves
  remain editable cards/scripts, not scrolling-image presets.
- Named cards can become scripts and back while updating the same identifier.
  Existing saved cards, scripts, originals and Shortcut selections remain
  compatible. Library has one creation action. The old standalone prompter
  editor and separate PDF scrolling setup screen were removed.
- The unified draft migrates from the previous text/script draft. Old values
  are not overwritten or deleted; distinct earlier content remains available
  under Earlier drafts, with confirmation before replacing current text.
- PDF page entry, total and stepper share one row. **Auto-scroll pages** is an
  inline toggle. On replaces single-page/crop controls with From/To, speed and
  preview position. Off restores the original page and crop option. Preparation
  is automatic and bounded; invalid, stale or unprepared input cannot float.
  Native finite pause/seek semantics are unchanged.
- No new permissions or external launch routes. Signed image Shortcuts and the
  original Cod installation/data are unchanged.

## Verification

Artifacts: `/private/tmp/cod-layout17.z3qn0l`; builds reuse build-16 DerivedData.
Only `com.josh.cod.store` is eligible for physical installation.

- 182 unit tests passed (`units17complete.xcresult`), including six new checks
  for source/style preservation, non-truncating validation, same-ID card/script
  conversion, placeholder restoration and PDF range validation.
- iPhone UI checks passed for inline PDF toggle/crop visibility, automatic range
  preparation and finite playback, saved text reopening, and saving a timed
  script/reading guide (`ui17.xcresult`). That bundle also records initial
  photo/mode test failures searching for a lazy-list switch above the viewport;
  corrected checks explicitly scroll toward the top.
- Debug signed device and Release builds passed (`device17.log`, `release17.log`).
  Supported-source, Release artifact and whitespace audits passed. These are
  not distribution validation or App Review preapproval.
- Corrected iPhone checks passed for text/word-mode switching, photo import and
  original-image scrolling, and the single Home entry (`ui17final.xcresult`).
  iPad checks passed for inline PDF toggling, typed/invalid pages and remembered
  timer values (`ipad17.xcresult`), and retained text/mode settings
  (`ipad17modes.xcresult`). Cold/warm Share Shortcut delivery and manual Share
  activation also passed (`ui17modes.xcresult`). The final unit suite passed all
  182 tests again (`units17final.xcresult`). Screenshots were visually inspected.
- The final-source photo-import/original-layout check passed on rerun
  (`photo17retry.xcresult`, October 21). The preceding attempt
  (`photo17ready.xcresult`) timed out opening the system photo picker, before
  image selection or Cod's loading task. The successful rerun used unchanged
  sources. Final Debug/Release builds (`device17ready.log`, `release17ready.log`),
  the development signature, source audit and Release artifact audit passed.
- The first phone installation attempt was blocked because the phone was locked.
  After the owner unlocked it, build 17 installed and launched successfully on
  the current iPhone 16 Pro Max on October 21 (`com.josh.cod.store`, Cod Test).
  The original Cod app/data were not modified.

Floating-picture quality and the reorganized flow still need phone acceptance.
The owner reported build 16's features looked good before requesting this layout
change; that is not blanket acceptance of every remaining release gate.
