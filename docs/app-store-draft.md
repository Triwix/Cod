# Cod 1.0 — App Store submission draft

Not published or submitted. The account owner must approve all answers and
replace the marked fields. App-name availability has not been checked in
App Store Connect. No enrollment, purchase, signing agreement or upload is
authorized by this document.

## Listing

Name: Cod

Subtitle: Keep a photo over any app

Suggested category: Utilities

Description:

Keep a reference image in view while you use other apps. Cod turns a photo or
screenshot into an iOS Picture in Picture window you can move and resize.

Choose a photo inside Cod, float your latest saved screenshot, or add the
ready-made Float with Cod Shortcut once to float an image from Photos' share
sheet. The Shortcut comes preconfigured; adding it requires your confirmation
in Apple's Shortcuts interface. iOS controls first-use permission prompts.

Need just one part of an image? Crop a region before floating it. Cod also
offers on-device text recognition, barcode scanning, copying, saving and image
history. Processing stays on your device; there are no accounts, ads or analytics.

Optional screenshot controls for Control Center, the Lock Screen and supported
Action Buttons require iOS 18 or later, a saved screenshot and Photos permission.
Back Tap uses a separate screenshot Shortcut that you assign in iPhone Settings.

iOS allows one Picture in Picture window at a time and controls its buttons,
size and movement. Cod opens to start floating; switch apps when the image is
visible. The native Cod app icon in Share doesn't automatically launch Cod.

Keywords draft: photo,screenshot,float,reference,picture in picture,crop,ocr

Support URL: [OWNER MUST PROVIDE]

Privacy-policy URL: [OWNER MUST APPROVE AND HOST]

Copyright/publishing identity: [OWNER MUST PROVIDE]

Price and storefront availability: [OWNER MUST CHOOSE]

## Reviewer instructions

No login is required.

1. Open Cod and tap Choose Photo. Select a locally available image. Keep Cod
   foreground while Picture in Picture opens, then switch to another app.
2. For sharing, use Add Float with Cod on the Float tab. Choose Shortcuts in the
   file-sharing interface and confirm Add Shortcut. The workflow already accepts
   Images, enables Share Sheet and binds Shortcut Input to the image parameter.
3. Open a photo in Photos → Share → scroll to the action list → Float with Cod.
   This is the Shortcut action, not the Cod app icon in the app-icon row.
   Approve the system image-sharing permission if shown.
4. With One tap float off, Choose Photo opens cropping. Explicit Float Shortcuts
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

## Privacy, export and rating answers to review

- No developer collection, tracking, advertising, analytics, login or upload
  service is implemented. Images, OCR and history remain on-device; history may
  be in device backups. Confirm the final App Privacy answers against the final
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

Apple references checked October 18, 2026:

- [Submission checklist](https://developer.apple.com/app-store/submitting/)
- [Current SDK/deployment requirements](https://developer.apple.com/news/upcoming-requirements/)
- [App Review requirements](https://developer.apple.com/app-store/review/guidelines/)
- [Sharing prebuilt Shortcuts](https://support.apple.com/guide/shortcuts/share-shortcuts-apdf01f8c054/ios)
