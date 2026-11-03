# Optional feature candidates

Research recorded October 20, 2026. The owner subsequently selected **1, 2, 3, 4,
6, 10, 11 and 12** for implementation in Cod Test build 16. Their implementation,
verification and remaining device acceptance are tracked in
[build-16 notes](features-16.md) and the [MVP checklist](../MVP_CHECKLIST.md).
The other candidates remain unapproved ideas, not additional release gates.
Keep the numbers stable so they match the research shared with the owner.

Recommended first candidates: **1, 2, 3, 4 and 6**. The product direction is to
make references faster to capture, easier to read and simpler to reuse, rather
than add unrelated floating utilities. Candidate 5 is especially relevant to
artists and iPad users. Priorities are product judgments; individual user posts
and reviews are qualitative signals, not proof of broad demand.

All implementations must follow [the development policy](../AGENTS.md): only
documented Apple APIs used for their intended purposes, supported user-initiated
entry points, no direct Share-extension app launching and no hidden PiP controls.
Competitor listings describe advertised features, not verified implementation
details or a guarantee that Apple will approve Cod. PiP remains system-managed;
these candidates do not assume arbitrary interactive overlays.

| # | Candidate | Use cases and scope | Caveats |
|---|---|---|---|
| 1 | Screenshot to readable floating text | Reflow recognized screenshot text into an editable, readable card for instructions, addresses and ingredients. Extends existing text extraction rather than adding it anew. | Keep the original available; recognition may misread numbers and table layout. Do not silently rewrite content. |
| 2 | Named editable cards and presets | Save multiple notes, scripts and tool configurations with their source and appearance settings, beyond image/video favorites. | Preserve editable data, not only a rendered image; keep organization lightweight. |
| 3 | Favorite-specific Shortcuts, widgets and controls | Launch a chosen saved reference or script instead of only the latest screenshot. | Users configure system controls; opening Cod or unlocking may still be necessary. Depends on reusable saved content. |
| 4 | Long screenshot and document auto-scroll | Read tall screenshots or selected PDF pages at a legible size with adjustable scrolling, pause and meaningful timeline seeking. | Not touch-scrolling inside PiP; bound document size, rendering work and memory use. |
| 5 | Small multi-image reference boards | Compose two to four images into one reference for drawing, diagrams and comparisons. | One composite PiP, not multiple independent windows; configure the layout in Cod. Readability is limited on smaller phones. |
| 6 | Video region crop | Enlarge a tutorial's hands, slides or other important region before floating. | Start with local unprotected video; some files need preparation, with orientation and performance testing. |
| 7 | Video segment repeat and speed | Repeat a selected passage for music, dance, language or exercise practice. | Extends whole-video repeat; configure in Cod and retain meaningful native playback controls. Test seeking and loop boundaries. |
| 8 | Web passage or webpage reference card | Import explicitly shared text or a snapshot with a source link for recipes and instructions. | Not a full floating browser; authenticated pages may not import and snapshots become stale. |
| 9 | Document-to-text/script import | Import TXT, Markdown, RTF, Word or PDF text into reference cards and the teleprompter, starting with simpler formats. | Different from existing PDF image viewing. Complex layouts may be lost; scans require recognition. |
| 10 | Teleprompter reading guide and layout | Optional reading-line guide, margins and line spacing to reduce eye movement and losing one's place. | Complement existing scrolling/word modes without cluttering the editor. |
| 11 | Target-duration teleprompter pacing | Calculate scrolling pace for a requested duration and show estimated remaining time. | Estimate only; cannot guarantee the speaker finishes at that time. |
| 12 | Animated GIF support | Preserve motion in short demonstrations and visual references. | Convert animation into genuine video playback; cap size and duration and test frame timing. |
| 13 | Translate then float | Translate explicitly shared text or recognized screenshot text into a reference card. | Check supported language pairs and model downloads; recognition and translation can introduce errors. No silent screen reading. |
| 14 | Optional iCloud sync and exports | Back up and move reusable references/scripts across the user's devices. | Later priority, after saved editable content; handle offline use, conflicts, privacy and storage consumption. |

## Research sources

- Candidates 1 and 13: Apple's [on-device text recognition](https://developer.apple.com/documentation/vision/recognizing-text-in-images), [language availability](https://developer.apple.com/documentation/translation/languageavailability) and [translation download behavior](https://developer.apple.com/documentation/translation/translationsession/translations%28from%3A%29).
- Candidate 2: [Picture in Picture Notes](https://apps.apple.com/us/app/picture-in-picture-notes-pip/id1618652473) advertises note organization; [Floathing](https://apps.apple.com/us/app/floathing-pip-for-everything/id6757504902) advertises reusable setups.
- Candidate 3: Apple's [configurable system controls](https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system).
- Candidate 4: [Yoink's documented reference-scrolling feature](https://blog.eternalstorms.at/2021/09/20/yoink-v2-3-ios-15/); this older developer article demonstrates the product concept, not a recommendation to copy its control implementation.
- Candidate 5: [An original Procreate user request for multiple PiP reference images](https://www.reddit.com/r/ProCreate/comments/1w6pvaj/reference_app_that_allows_pictureinpicture_mode/). Treat as an anecdotal demand signal.
- Candidate 6: Apple's [video-composition APIs](https://developer.apple.com/documentation/avfoundation/avvideocomposition).
- Candidate 7: [Video Player - PIP and more](https://apps.apple.com/us/app/video-player-pip-and-more/id1610938825) advertises playback speed and A-B repeat.
- Candidates 8 and 12: [Pip Up](https://apps.apple.com/gb/app/pip-up-persist-float-window/id6483210322) advertises webpage snapshots; an individual review requests animated GIF support.
- Candidates 9, 10 and 11: [Teleprompter](https://apps.apple.com/us/app/teleprompter/id941620509) advertises document imports, reading guides, margins and timed scrolling.
- Candidate 14: Apple's [CloudKit guidance](https://developer.apple.com/documentation/cloudkit/deciding-whether-cloudkit-is-right-for-your-app).
- All candidates: Apple's [PiP playback documentation](https://developer.apple.com/documentation/avkit/adopting-picture-in-picture-in-a-standard-player) and [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/). Public APIs alone are not a promise of approval.
