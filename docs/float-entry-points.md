# Supported floating entry points · 1.0 (7)

Only documented, user-mediated launch routes remain. The responder-chain
launcher and all private return/origin/control code were physically removed,
along with their compile flags, schemes, tests and obsolete personal resources.
The source and artifact checks have no experimental bypass.

## How to use

1. **Shared photo:** tap **Add Float with Cod** on Cod's Float tab. Choose
   Shortcuts and approve Add Shortcut. The installer also remains in Settings →
   Set up fast floating after the Home tip is hidden.
   Then Photos → Share → **Float with Cod** in the action list. The workflow
   explicitly accepts Images and passes Shortcut Input to FloatWithCodIntent.
   Missing input stops; it never asks for an unrelated file or substitutes a
   latest photo/clipboard image.
2. **Latest saved screenshot:** add Cod's Float Latest Screenshot control in
   Control Center, Lock Screen, or an available Action Button (iOS 18+).
   OpenIntent runs in the containing app and requires authentication. Grant
   Photos permission first; Limited Access sees only allowed screenshots.
3. **Fresh screenshot with Back Tap:** add **Screenshot and Float with Cod**
   in the guide, then assign it to Double/Triple Tap in iPhone accessibility
   settings. It captures a fresh image and explicitly passes the action output.
4. **Notification:** enable **Tap notification to float** in Cod and approve
   notification permission. Share → Cod stores the actual image in the App
   Group; tapping the notification opens Cod. With One tap float off, crop in
   the extension before tapping Float. No image is attached to the notification.
5. **Manual fallback:** Share → Cod prepares the image and dismisses. Open Cod
   within five minutes to float, or crop first when One tap float is off.

iOS controls initial image-sharing permission prompts for Shortcuts. Allow
Once repeats them; Always Allow is the user's choice. The signed Store
workflows already included in the app were signed with user approval on
October 18, 2026; no new upload/signing was needed for this polish. Package
identity is checked against the app/team before offering an installer. Changing
the publishing identity requires regenerating and signing matching workflows.

Once PiP appears, switch apps yourself. There is no automatic previous-app or
Home navigation, native controls are retained, and no PiP size restrictions are
added beyond iOS's own limits. Cropping in the main app has the full configured
action bar; the extension has Float only.

## Safety and scope

- App Group UUID claims prevent stale notifications floating a different image.
- Cold notification taps are queued before the root UI exists; work waits for
  an active scene. Explicit input takes precedence over unrequested pending work.
- Expired, failed and cancelled shares require explicit retry, not silent replay.
- Image decoding uses bounded ImageIO thumbnails, not full camera-size bitmaps.
- Notifications are optional, local and UUID-only. Focus, disabled permissions
  and banners affect delivery. Failure preserves the request for explicit retry.
- No screen recording, clipboard handoff, private origin detection, app
  suspension, responder-chain opening, or private AVKit settings remain.
- Dedicated-album saving defaults off; this update does not delete old albums,
  history, settings, the original phone app, or user-installed Shortcuts.

## Build-7 release polish

The updated Home installer, guide, history safeguards, image-cache budget and
in-app pin touch controls are documented in the
[build-7 handoff](release-polish-7.md). It includes final test evidence and
remaining physical-device/submission gates. These changes do not restore direct
Share-extension app opening or automatic return navigation.

## Earlier supported-only acceptance

- **66 unit tests passed** on the iOS 26.5 simulator after removing the old
  implementations and configurations. These include actual image/video-frame
  checks, request claiming/expiry, preferences, metadata and entry-point logic.
- Signed **Cod / Release** device build succeeded. Source regression checks,
  all-three-bundle artifact checks, privacy resources, and deep/strict signature
  verification passed. The obsolete experimental audit flag is now rejected.
- **Cod Test 0.1.0 (6)** was installed on the user's current iPhone. The user
  subsequently confirmed that Photos → Share → the Float with Cod Shortcut
  worked after connecting its Image parameter to Shortcut Input. The bundled
  ready-made workflow already has that connection; build 7 puts its installer
  prominently on Home to avoid manual editing.
- **10 native UI tests passed**, zero failures/skips: real Control Center
  registration/launch; document opening; manual Share preparation without
  automatic Cod launch; action-bar scope; crop/cancel without replay; warm/cold
  notifications and crop-first notification; both signed Shortcut installers.
  Share Shortcut cold/warm receipts matched the 300×200 and 148×92 fixtures.
  Screenshot Shortcut delivered the new 942×2048 simulator screenshot. Native
  image-sharing permission used Allow Once; no manual app activation was used
  to make a Shortcut test pass. Tests replace only disposable simulator workflows,
  never user-installed phone Shortcuts.

Simulator checks do not prove visible PiP on hardware or App Review acceptance.
Physical build-4 confirmations were for an older candidate. Build-7 checks and
remaining device acceptance are tracked in APP_STORE_RELEASE.md. The original
installed Cod and its data were not modified or deleted.

## Apple references

- [Controls and OpenIntent](https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system)
- [Share-sheet Shortcuts](https://support.apple.com/guide/shortcuts/launch-a-shortcut-from-another-app-apd163eb9f95/ios)
- [Back Tap Shortcuts](https://support.apple.com/guide/shortcuts/run-shortcuts-tapping-iphone-apd897693606/ios)
- [Apple engineer: extension-launch limitation](https://developer.apple.com/forums/thread/773342)
- [App Review software requirements](https://developer.apple.com/app-store/review/guidelines/#software-requirements)

These sources support the available mechanisms, not approval of Cod's
still-image-to-video PiP use. Final acceptance remains Apple's decision.
