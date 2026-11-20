# Build 36: Recents fixes, video speed and sections, video links, documents

November 19, 2026.

## Recents
- The same setup floated in light and dark mode is now one row (lists saved earlier are merged, keeping a star).
- Rows show what differs: hundredths, a non-wide window shape.
- Image sets, PDF Flip Pages and auto-scroll documents now appear in Recents and float again from there (their images are kept with the image sets and cleaned up at launch once no longer listed).

## A. Video speed and sections
- Speed 0.5×–2×, applied immediately, also while floating (PiP's Play keeps it).
- "Play one section": Start/End sliders; Repeat repeats just that part.

## B. Video from a Link
- Home row "Video from a Link", the Share extension (a shared link or a text that's only a link), and a new "Open Video Link With Cod" Shortcut action open a private web view. Start the video, tap Float (or the Float button on the video). WebKit's own PiP plays it; keep the screen open.
- Pro (Videos & GIFs). Safari Video stays free.
- **Age rating:** this is unrestricted web access, so Cod is rated 16+; the owner accepted that to keep the in-app browser (see app-store-draft.md).

## C. Documents
- Word, PowerPoint, Excel, Pages, Keynote and Numbers files are laid out by WebKit and printed to Letter PDF pages, then use the PDF screen (one page, Flip Pages, Auto-scroll).
- Text, Markdown and RTF open in the Text editor.
- Cod is offered in "Open in" for these types.

## Verification
- 307 unit tests pass (3 StoreKit skips). Build36Tests cover all of the above, including a real .docx converted to 2+ pages with visible text.
- Build36UITests (video speed/section, link screen) pass; release build and all verifiers pass.
- Full UI suite (first run since build 30): 83 tests, 4 skipped (no PiP in the simulator), 2 failures. The iPad screenshot test fails as expected (1.0 is iPhone-only). Redesign21's Recents check needed to scroll now that Recents lists more kinds of floats; fixed, and the class passes.
- Simulator: Float on a web video starts it (simulator shows full screen; real PiP needs the phone). Not checked: PowerPoint/Keynote layout quality, PiP from the web view on a phone.
