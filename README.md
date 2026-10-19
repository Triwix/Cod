# Cod

Float an image over other apps with iOS Picture in Picture, or crop, copy,
recognize text, scan barcodes, and keep snippets inside Cod.

## Release-polish candidate · 1.0 (7)

All private navigation/control APIs, direct Share-extension app-launch tricks,
and experimental build configurations have been removed—not just disabled.
The only application scheme is **Cod**, with Debug/Release configurations.
The development installation is **Cod Test**, `com.josh.cod.store`; it does not replace
the original installed Cod or delete its data.
The public Release display name is **Cod**. This is a release candidate, not an
App Store submission or approval.

Fast entry points:

- **Share → Float with Cod**: install the signed Shortcut once from Cod's
  Float tab's **Add Float with Cod** button (also available in the Floating
  Guide). It accepts the actual shared image and opens Cod through
  App Intents. It appears in the share action list, not the app-icon row.
- **Control Center / Lock Screen / Action Button**: iOS 18+ control opens Cod
  to float the latest saved screenshot. Requires Photos access and, when
  needed, unlocking. Availability of Action Button depends on hardware.
- **Back Tap → Screenshot and Float with Cod**: install the signed Shortcut
  and assign it in Settings → Accessibility → Touch → Back Tap. Captures a new
  screenshot and passes it directly; no clipboard or photo-library guessing.
- **Share → Cod → tap notification**: optional, enabled in Cod's settings.
  Focus and notification settings can affect delivery.
- **Share → Cod → open Cod yourself**: manual fallback. Cod automatically
  prepares the image; no Save/Done or second Float tap is required.

One tap float skips cropping; it does **not** authorize automatic app opening.
Explicit Float Shortcuts always float their supplied input. Cod no longer
automatically returns to another app or Home. Once PiP appears, switch apps
yourself; native PiP controls and system resizing remain available.

Save to a dedicated album defaults off. Existing saved preferences survive.
Share-sheet cropping offers Float only; configurable action-bar actions apply
to the editor inside Cod.

The Float tab prioritizes choosing a photo and installing the ready-made Share
Shortcut. Its setup tip can be hidden without losing access to the guide.
History deletion and lowering the retention limit require confirmation; local
pins and pending shares are separate. Library images can be floated directly.

Documented APIs do not guarantee App Review acceptance. Still-image-to-video
PiP use remains a review question; no Apple preapproval is claimed.

## Build and verification

Xcode 26.6, app deployment target iOS 17, controls iOS 18. Configure your team,
matching App Groups, and development/distribution signing before building.
The project is generated from `project.yml`.

```sh
xcodegen generate
open Cod.xcodeproj
```

Run unit tests with **Cod**, native UI tests with **Cod Launch Tests**, then:

```sh
zsh Tools/verify-supported-source.sh
zsh Tools/verify-store-build.sh /absolute/path/to/Cod.app
```

The scans are regression safeguards, not certification. Simulator tests verify
image transport, encoding, crop handling and system entry points; visible PiP
and hardware gestures still need an iPhone.

See [entry-point details](docs/float-entry-points.md) and
[remaining release gates](APP_STORE_RELEASE.md). Listing text, reviewer steps,
and owner decisions are in the [submission draft](docs/app-store-draft.md).
Older research documents are historical records of experiments removed in
build 6, not current build instructions. Git history retains removed source.
