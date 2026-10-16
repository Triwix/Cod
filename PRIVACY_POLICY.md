# Cod privacy policy — release draft

Last updated: October 7, 2026.

Publication requires the developer's approved identity/contact details below.
This draft describes only the App Store V1 configuration, not the personal build
with optional Imgur uploads. Remove this draft notice before hosting it.

## Data Cod uses

Cod works with images you share, choose, paste, or retrieve from your Screenshots
album. Text recognition and barcode detection run on your device. Cod does not
include advertising, analytics, tracking, accounts or an image-upload service
in this version. The developer does not receive your images or recognized text
through Cod.

## Local storage and deletion

The Share extension prepares one pending image in a local container shared
only with Cod. This container is excluded from device backups. A new share
replaces the previous pending image. Cod removes this temporary copy after
Picture in Picture starts successfully. If floating fails, is interrupted, or
you cancel cropping, the copy remains available to retry or remove in Cod.
After five minutes, a pending image no longer starts floating automatically.
Images saved in the older Shared Images inbox by an earlier test build remain
there until you explicitly remove them; new shares no longer use that inbox.

History separately stores recent crops and their recognized text or barcode
results in Cod's private storage. You can set a history limit, turn history off,
or clear it in Settings. History may be included in your normal device backup.
Preferences are stored locally. Cod also keeps bounded local diagnostic logs
of operational events and errors; it does not automatically send them to the
developer or include image pixels or recognized text in these logs.

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
you choose a copy action, including the optional copy-on-pin setting. Shared
images are not transferred through the clipboard.

## Actions involving other apps or services

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
