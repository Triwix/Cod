# Build 35: swipe the preview to choose the window shape

November 19, 2026. Build 34's design is unchanged. Two functional changes
from the redesign experiments were kept; every visual change was dropped.

## Changes

- **Swipeable shape preview.** In the tool editor, the teleprompter editor and
  PDF Flip Pages, the preview at the top is a strip of the same content in
  every window shape. The shape in the middle is the one that floats; the
  shapes on either side show faded so it's clear you can swipe. Tapping a faded
  shape also selects it. A caption ("16:9 · Wide") and dots show the shape.
  The Window row in settings is still there and stays in step with the preview.
  VoiceOver users can also swipe up or down on the caption.
- **No error at launch.** When Cod checks for a new screenshot on its own (on
  opening, with Photos access) and finds none, it no longer shows "Couldn't
  load screenshot". Errors still show when you tap Float or Crop yourself.

## Not kept

The koi look (build 35 draft), the dark-only prototype, its Home layouts and
the canvas mockups. They are backed up in `.claude/redesign-backup/`.

## Verification

See the build-35 entry in [MVP_CHECKLIST.md](../MVP_CHECKLIST.md).
