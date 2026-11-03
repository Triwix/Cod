# Cod 1.0 — App Store submission draft

Not published or submitted. The account owner must approve all answers and
replace the marked fields. App-name availability has not been checked in
App Store Connect. No enrollment, purchase, signing agreement or upload is
authorized by this document.

## Listing

Name: Cod

Subtitle: Floating references & tools

Suggested category: Utilities

Description:

Keep a reference image in view while you use other apps. Cod turns a photo or
screenshot into an iOS Picture in Picture window you can move and resize.

Choose a photo inside Cod, float your latest saved screenshot, or add the
ready-made Float with Cod Shortcut once to float an image from Photos' share
sheet. The Shortcut comes preconfigured; adding it requires your confirmation
in Apple's Shortcuts interface. iOS controls first-use permission prompts.

Need just one part of an image? Zoom, move and crop a region before floating it.
The sectioned Float list also offers typed/pasted text, PDF pages, a timer,
stopwatch, Current Time and Pomodoro session. Text includes an optional
teleprompter with scrolling or centered word groups, a starting countdown and
adjustable reading pace. Read editable text from a photo with on-device
recognition, compare it with the original, and save named cards or scripts to reuse.
Auto-scroll an image or selected PDF page range with finite pause/seek playback.
Import local videos and animated GIFs from Photos or Files. Choose sound,
repeat or a cropped video region without changing the original. Favorite library
items for repeated use, or choose a saved reference in a Shortcut, widget or control.
Choose background and text colors in each text/live-tool editor. On iOS 26 or
later, optionally enable a system alarm when a timer finishes; permission is
required. With that switch off, the timer is visual-only.
Cod also
offers on-device text recognition, barcode scanning, copying, saving and image
history. Processing stays on your device; there are no accounts, ads or analytics.

Optional screenshot controls for Control Center, the Lock Screen and supported
Action Buttons require iOS 18 or later, a saved screenshot and Photos permission.
Back Tap uses a separate screenshot Shortcut that you assign in iPhone Settings.

iOS allows one Picture in Picture window at a time and controls its buttons,
size and movement. Cod opens to start floating; switch apps when the image is
visible. The native Cod app icon in Share doesn't automatically launch Cod.

Keywords draft: pip,photo,screenshot,reference,teleprompter,pdf,timer,stopwatch,clock,ocr,crop

Support URL: [OWNER MUST PROVIDE]

Privacy-policy URL: [OWNER MUST APPROVE AND HOST]

Copyright/publishing identity: [OWNER MUST PROVIDE]

Price and storefront availability: [OWNER MUST CHOOSE]

## Reviewer notes — concise draft

No login, subscription, server or purchase is needed. A supported physical iPhone
or iPad is required to assess the actual PiP picture. Simulator controls alone
do not establish successful visible playback.

Quick test: open Cod → Photos & videos → Float, select a local photo and keep Cod
foreground until PiP appears. Then switch to another app yourself. Cropping is
available through the separate Crop action. First-run guidance is optional;
Settings → Quick introduction reopens it.

Fast sharing: Float → Floating guide & setup → Add Share-Sheet Shortcut. Choose
Shortcuts and confirm Add Shortcut; its shared-image input is already bound.
In Photos, Share → Float with Cod in the action list below the app icons. Allow
the system image-sharing prompt if shown. The Cod app icon is a different route:
it prepares the image in an App Group, then the user opens Cod or taps an optional
local notification. The Share extension does not launch the app directly.

Text opens a single card/script editor. Enable Teleprompter to see playback
settings. Choose File supports images, local videos, animated GIFs and PDFs;
PDF page selection is one row, and Auto-scroll pages exposes a bounded range.
Named cards/presets are in Library. Time & focus contains the remaining tools.

Implementation disclosure: still-image PiP is a generated looping video through
AVQueuePlayer/AVPlayerLayer and AVKit. Tools and finite reference/script playback
use AVSampleBufferDisplayLayer and AVKit's documented playback delegate. Imported
videos use normal finite playback, with optional repeat. Audio playback background
mode supports active PiP, not unrelated background work. No private launch,
automatic return to another app or hidden control settings are used.

Optional timer alarms require iOS 26+ and a user-granted AlarmKit permission;
the alarm switch defaults off. Screenshot controls require iOS 18+ and access to
the saved screenshot. Permissions are requested only when needed. The photo picker
does not require broad Photos access. Images, documents and recognition are
processed locally. This disclosure is not a claim that the still-image/tool
content use is preapproved; Apple decides App Review acceptance.

## Internal verification detail — not the reviewer-note field

No login is required.

1. Open Cod and tap Choose Photo. Select a locally available image. Keep Cod
   foreground while Picture in Picture opens, then switch to another app.
2. For sharing, use Add Float with Cod on the Float tab. Choose Shortcuts in the
   file-sharing interface and confirm Add Shortcut. The workflow already accepts
   Images, enables Share Sheet and binds Shortcut Input to the image parameter.
3. Open a photo in Photos → Share → scroll to the action list → Float with Cod.
   This is the Shortcut action, not the Cod app icon in the app-icon row.
   Approve the system image-sharing permission if shown.
4. Photo and screenshot rows have separate Float/Crop actions. One tap float
   applies to pasted/shared images; explicit Float Shortcuts
   still float their supplied image directly. They do not substitute the latest
   photo or use clipboard transport.
5. Inspect the real image, replace it with another, resize the native PiP window,
   and restore it into Cod. PiP needs a supported physical device.

Implementation disclosure: Cod encodes the selected still image into a short
looping video and uses AVQueuePlayer/AVPlayerLayer with the public AVKit PiP
controller. It uses native PiP controls and playback background mode; it has
no private launch, origin-detection, app-suspension or control-hiding APIs.
Idle prewarm playback is released when Cod backgrounds without an active float.
This is a disclosure, not a claim of approval for the still-image PiP use case.

Build 21 reviewer checks: use the sectioned Float list, enter a short text reference
and Float; choose a PDF and zoom/select/crop a page; start Timer, Stopwatch, Current Time,
Pomodoro and Teleprompter with several paragraphs. Live tools render real,
timestamped frames through AVSampleBufferDisplayLayer and the documented AVKit
sample-buffer playback delegate. Check native play/pause, restore and close;
these tools do not insert custom buttons into PiP. Timer alarms are off by
default. On iOS 26+, explicitly enable Alarm when finished and authorize the
system prompt to test an audible alarm, including while locked. This is a
native duration-based AlarmKit timer with its required countdown widget/Live
Activity. The chosen duration is remembered with hour/minute/second wheels.
Keep alarm running when PiP closes defaults on; Off stops the timer and cancels its
alarm when PiP closes. Restoring to Cod doesn't cancel it. Pause/resume/restart
updates it; cancel from Float, including after relaunch. Other tools don't
schedule alarms. Test a local MP4/MOV through the combined Photos & videos picker or Choose File;
these use ordinary finite AVPlayer playback, not generated-image looping.
Videos repeat by default with native seeking/play-pause controls; Repeat Video
can be disabled during playback. Pomodoro numbers support direct keyboard entry
as well as steppers, with input ranges validated before Float.
System is the default generated-text/tool appearance, with fixed Dark/Light/Yellow
and custom-color alternatives. Current Time's setup preview updates each second;
search is visible on entry to Time Zone, and changed line sizes can be reset.
Scrolling scripts use cached layout and a 60-fps target; check smoothness on a
physical device rather than interpreting simulator callbacks as a visual pass.
An empty text/script field uses a gray sample; focusing it edits an empty draft.
In word mode, adjust word-group size and reading speed. Favorite a library item
and verify it stays in the stable Favorites section above new history. Clear Recent
History preserves it; Delete Everything, Including Favorites removes it after
confirmation. Rounded previews and Float stay above scrolling settings. Timers
use smooth circular progress; Stopwatch offers optional hundredths. Permission denial is shown rather than silently claiming
an alarm was armed.
Only Apple can determine whether these content uses satisfy review requirements.

Additional reference checks: Text → Import Photo performs local recognition and
keeps the original available for comparison. Save a named text card or script in
Library → Saved cards & presets; reopen it to edit source/settings. In Shortcuts,
add Float Saved Reference and choose that card. A configurable Home Screen widget
and system control on iOS 18+ offer the same selection and open Cod after an
authenticated tap. No Share-extension direct launch is used. Delete Everything
also removes saved cards/presets; Clear Recent History preserves them.

Choose File accepts animated GIFs and prepares genuine local video playback.
Photos/Files must supply original animation data; the app-icon Share extension
still prepares a still image. Auto-scroll images or a bounded PDF page range
uses finite, pausable/seekable reference playback. Crop Region prepares a separate
local video without changing its source. Teleprompter guide, margins, spacing and
Finish in… affect its finite playback; countdown is additional to reading time.

## Privacy, export and rating answers to review

- No developer collection, tracking, advertising, analytics, login or upload
  service is implemented. Images, OCR, editable cards and history remain local;
  saved cards/history may be in device backups. Widget/control configuration uses
  a local App Group catalog of reference identifiers/names, not a sync service.
  Confirm the final App Privacy answers against the final
  signed build and hosted policy.
- Optional local notifications are UUID-only. No remote push service or image
  attachment is used.
- No third-party SDKs or custom encryption were found. The owner must answer
  export-compliance questions; no legal determination or encryption exemption
  has been filed on their behalf.
- Complete Apple's current age-rating questionnaire. There is no public content
  feed, chat, advertising or embedded unrestricted web browser; image content is
  supplied by the user. Do not infer a final age rating from this draft.
- Accessibility: large-text/layout checks cover the tested home/setup screens.
  Do not claim full-app VoiceOver, Voice Control or accessibility certification
  without completing those checks, particularly the gesture-based crop editor.

## Screenshots and evidence

Prepare final marketing screenshots from the signed release candidate, showing
only content the owner has rights to use. Include the Float tab, Shortcut setup,
crop editor and an actual physical-device PiP example. Simulator QA attachments
are useful layout evidence, not a substitute for a real PiP screenshot.

The current [screenshot and owner-handoff plan](submission-package-18.md)
separates draft work from actual submission. No account answers or uploads have
been made on the owner's behalf.

Apple references checked October 28, 2026:

- [Submission checklist](https://developer.apple.com/app-store/submitting/)
- [Current SDK/deployment requirements](https://developer.apple.com/news/upcoming-requirements/)
- [App Review requirements](https://developer.apple.com/app-store/review/guidelines/)
- [Sharing prebuilt Shortcuts](https://support.apple.com/guide/shortcuts/share-shortcuts-apdf01f8c054/ios)
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
- [Version information and keyword limits](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/)
- [App Privacy definitions](https://developer.apple.com/app-store/app-privacy-details/)
