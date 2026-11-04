# Cod privacy policy — release draft

Last updated: November 3, 2026.

Publication requires the developer's approved identity/contact details below.
This draft describes Cod 1.0's supported-only configuration. Unsupported launch,
return and control-hiding experiments were removed. Remove this draft notice
after approving the publishing identity and contact information, before hosting.

## Data Cod uses

Cod works with images you share, choose, paste, or retrieve from your Screenshots
album, PDF pages you select, and text you type, paste or explicitly share.
Text recognition and barcode detection run on your device. Cod does not
include advertising, analytics, tracking, accounts or an image-upload service
in this version. The developer does not receive your images or recognized text
through Cod. PDF rendering, text rendering, timers and teleprompter playback are
local. Cod does not send documents, scripts or timing information to a server.

## Local storage and deletion

The Share extension prepares one pending image in a local container shared
only with Cod. This container is excluded from device backups. A new share
replaces the previous pending image. Cod removes this temporary copy after
Picture in Picture starts successfully. If floating fails, is interrupted, or
you cancel cropping, the copy remains available to retry or remove in Cod.
After five minutes, a pending image no longer starts floating automatically.
Images saved in the older Shared Images inbox by an earlier test build remain
there until you explicitly remove them; new shares no longer use that inbox.

History separately stores recent images, imported video copies, and recognized text or barcode
results in Cod's private storage. You can set a history limit, turn history off,
or clear it in Settings. Favorites are deliberate saves: they remain when history is
Off, trimmed or cleared with Clear Recent History. Clear Library also offers
Delete Everything, Including Favorites, after confirmation. Favorites have a locally
stored ordering. History may be included in your normal device backup.
Preferences, including whether the optional introduction has been completed or
skipped, are stored locally. Routine diagnostic logging is disabled in public
Release builds. Development test builds keep bounded local logs of operational
events and errors, without image pixels or recognized text. They are not
automatically sent to the developer. These diagnostic files have bounded lines
and total size and are excluded from device backups. Older development logs
may remain in a test installation; disabling logging does not upload them.

Selected local videos are copied into Cod for playback and, when history is enabled,
kept in Library with a thumbnail. Deleting a library video never deletes the original
in Photos or Files. Temporary playback copies are removed when released.
On the next app launch, Cod also cleans up recognized temporary video copies
left by an interrupted session in its own playback folders. It does not sweep
provider folders or delete your original media.

The unified Text editor, with optional Teleprompter mode, retains a local draft
between visits. Earlier separate drafts remain available locally for migration.
Gray example
placeholders are not saved as the user's draft. Delete
the text in the corresponding editor to clear its draft. Clearing image
history does not clear these drafts. Rendered text and PDF pages may appear
as images in history when history is enabled. Cod reads selected PDFs to render
pages and does not retain a separate persistent copy of the original document.
Drafts, like other preferences, may be included in normal device backups.

Named text cards, scripts and tool presets are deliberate local saves, separate
from History. They retain editable content and settings and may retain the chosen
original image for comparison after text recognition. Delete them in Library →
Saved cards & presets. Clear Recent History does not delete these saves;
Delete Everything in Library does. Saved content and a catalog of Library
favorites are stored in Cod's shared local container for its own widgets and
controls. Widget labels display names, not the underlying text or images.
These local saves may be included in normal device backups; this version does
not offer iCloud synchronization.
If a local index cannot be read, Cod preserves it rather than silently replacing
it during a normal save. Library offers a non-destructive reload. Explicit
Delete Everything can reset damaged saved data and remove recognized media left
by interrupted saves; it still does not clear separate drafts, pending shares or
originals in Photos or Files.

Animated GIF conversion and video-region cropping happen locally. Temporary
edited videos do not replace or modify originals in Photos or Files. Scrolling
references locally render the chosen image or a bounded PDF page range.

Removing a pending share or inbox image does not remove copies in history,
Photos or another app. Clearing history does not empty the pending share or
older inbox, or delete Photos copies. Use the
corresponding removal controls for each copy. Deleting Cod removes its app-local
storage; copies in Photos or other apps and previously created device backups
are controlled separately.

## Permissions and clipboard

The system photo picker gives Cod only the images you choose, without requiring
access to the whole photo library. Reading the latest screenshot requires Photos
permission. Saving an image to Photos requests the relevant permission when
needed. Permission can be changed in iOS Settings.

Cod reads the clipboard when you tap Paste. It writes to the clipboard when
you choose a copy action. An explicit image Paste can also read GIF data to
preserve animation. Shared
images are not transferred through the clipboard.

## Actions involving other apps or services

Cod offers optional, ready-made Shortcuts. You approve adding them in Apple's
Shortcuts interface; Cod does not silently install or assign Shortcuts. The
share-sheet Shortcut receives the image you share. The screenshot Shortcut takes
a fresh screenshot when you trigger it, then passes that image to Cod. The
latest-screenshot control reads only Photos assets you have permitted. Apple
manages its own permission prompts and processing under its privacy policies.

Additional text and PDF-page actions in Shortcuts use only the input explicitly
supplied to them. Selecting Cod in a text share sheet renders that text locally
and follows the same manual-open or tapped-notification flow as shared images.
The app does not open itself from its Share extension.

Float Saved Reference actions, widgets and configurable controls use the saved
item or Library favorite you select. They ask iOS to open Cod to start playback;
they do not read another app's screen or silently capture clipboard content.
Deleting a selected reference invalidates that selection instead of floating a
different item. Apple controls authentication and permission prompts.

Live timers use system elapsed time solely for local timing calculations, with
the required timer-use reason declared in the app's privacy manifest. These
tools do not send timing information off-device. On iOS 26 or later, a timer's
optional Alarm when finished switch uses Apple's AlarmKit after your permission.
Its identifier and scheduled finish time are stored locally so you can cancel
it after reopening Cod. Native countdowns also appear in a system Live Activity,
with an explicit cancel control. iOS delivers the alarm independently of the PiP window,
including while locked. Keep alarm running when PiP closes defaults on. Turning it off
makes closing PiP stop that timer and cancel its alarm. Restoring Cod with PiP's
restore button doesn't cancel the timer. Visual-only background timers are kept
only until Cod quits. To cancel a system alarm, pause it
in playback controls or use Cancel alarm on the Float screen. Other tools and
visual-only timers do not schedule alarms.

An optional local notification contains a request identifier, not an image
preview or recognized text. Tapping it opens Cod with the matching local image.
Cod does not use a push-notification server, tracking notification identifiers,
or time-sensitive notifications. Notification permission is optional.

If you choose Share, open a scanned link, or invoke Apple's system translation
interface, the receiving app, website or Apple service handles that data under
its own terms and privacy policy. Cod does not automatically upload your images
to the developer or to Imgur.

## Contact and changes

Developer/operator: **[Provide the approved publishing identity.]**

Privacy/support contact: **[Provide a monitored email address or support URL.]**

Material changes to this policy will be reflected in the hosted policy and its
updated date. Review this policy again if adding uploads, analytics, accounts,
advertising or any other service that changes how data is handled.
