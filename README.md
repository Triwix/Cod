# Cod

Float an image over other apps with iOS Picture in Picture, or crop, copy,
recognize text, scan barcodes, and keep snippets inside Cod.

Design inspiration: the Snapper jailbreak tweak. This credits the inspiration,
not an affiliation or endorsement. Cod uses documented Apple APIs on standard iOS.
Keep this development credit separate from App Store branding and listing copy.

## Reliability candidate · 1.0 (22)

Build 22 bounds/cancels still-image video encoding, moves image preparation and
share encoding off the UI thread, loads storage size asynchronously and disables
routine Release diagnostics. Debug compilation, the Release archive and local
source/artifact checks pass. Automated execution is blocked by the Mac's Apple
test-service failure; Xcode's GUI is also rejected as OS-incompatible. The approved
developer-tools authorization change didn't resolve it. Earlier build-21 results don't establish this candidate's
acceptance. Four correctly sized 13-inch iPad screenshot drafts are prepared.
Cod Test build 22 was installed and launched on the phone on November 3;
physical feature acceptance remains open. See [reliability notes](docs/release-hardening-22.md).

## Native UI refinement · 1.0 (21)

Build 21 applies the approved native UI refinement: clearer Float/Crop hierarchy,
neutral aligned navigation icons, consistent touch targets and action shapes,
content-fitting pinned previews, grouped Library controls and optional detailed
sharing guidance. The launch confirmation follows system appearance. Features,
section order and supported entry points are preserved. See the
[redesign report and screenshots](docs/redesign-21.md).

Build 20 fixes a request-lifecycle bug in image sharing and Shortcut input. Fresh
playback cleanup no longer publishes an intermediate stop that could discard the
new request's result and leave a pending share incorrectly retryable. Five new
deterministic lifecycle tests cover the transition; see the
[audit follow-up](docs/audit-follow-up-20.md) for verification and release gates.

Build 19 hardens storage recovery, stale saved-reference updates, temporary media
cleanup and diagnostic-log bounds/backup exclusion. Thumbnail fallback is
downsampled; image imports consistently honor the 50 MB limit with a decoded-pixel
budget. PDF scrolling prepares one source page at a time. End-of-script clock
positioning is paused before seeking to avoid a race at the finite range boundary.
See [hardening evidence and performance tradeoffs](docs/hardening-19.md).

Build 18 adds an optional introduction on Float and in Settings. It explains the
Share Shortcut, notification fallback and iOS's app-opening/PiP limits without
blocking incoming images or requesting permissions up front. Home imports show
cancellable loading and persistent recovery messages; picker cancellation is
not an error, and cancelled/older loads cannot replace newer input. Color rows
have larger touch targets and the text editor has clearer accessibility guidance.
See [build-18 verification](docs/release-polish-18.md) and the
[submission preparation](docs/submission-package-18.md). No submission or phone
installation is implied by a successful local build.

Build 17 consolidates text/photo recognition and teleprompter into one **Text**
editor. Import Photo reads editable text; Teleprompter reveals scrolling/word
modes, pacing, guide and countdown settings without replacing the source.
Imported photos can instead scroll with Keep original image layout. Cards and
scripts retain their identifiers when converted in this same editor. PDF page
entry/total/stepping share one row; Auto-scroll pages replaces it and cropping
with inline range/scroll settings. Pages prepare automatically. See
[layout-17 verification](docs/layout-17.md).

Build 16 adds the selected [feature candidates](docs/feature-candidates.md):
readable text from image recognition with an original-image comparison; named
editable text cards, scripts and tool presets; favorite/card-specific Shortcuts,
Home Screen widgets/controls on iOS 18+; finite auto-scrolling images and PDF page
ranges; video-region cropping; teleprompter reading guides, margins and spacing;
target-duration script pacing; and animated GIF playback through real videos.

Import Photo is inside Text; Use in Text is also available from an image's
in-app crop menu and Library detail. Enable Teleprompter for longer text instead
of squeezing it into a single card. Saved cards & presets
is in Library, independent of History; named saves retain source/settings and
can be updated. Float Saved Reference in Shortcuts or a configured widget/control
opens the chosen card or Library favorite. Deleted selections report an error,
not a different reference. Alarm presets still require alarm permission.

PDF Auto-scroll Pages accepts a valid range of up to 20 pages within a 24,000-pixel
scrolling-canvas limit; it has genuine pause/seek semantics and retains the final
region. Video Crop Region selects a region on the oriented poster and prepares
a separate video; reset returns to the untouched original. GIF imports are bounded
to 50 MB, 600 frames and two minutes, converted on-device, and keep the normal sound
and repeat controls. Photos, Files, explicit GIF clipboard paste and image-Intent
inputs that retain GIF data are supported. A provider/Shortcut that supplies only
a still UIImage cannot recover the animation; the regular Share extension still
prepares a still image. Use Photos or Choose File for reliable animated input.

Teleprompter target duration is 15 seconds–1 hour, excluding its optional starting
countdown. It changes the actual scrolling/word pace, not the user's speaking
speed. All new launch routes use documented, user-initiated Apple mechanisms;
Cod does not return to the previous app automatically. See
[build-16 verification and acceptance](docs/features-16.md).

The **Float** tab groups Media & Documents, Text & Reading, and Time & Focus.
The Photos picker accepts images and videos; compact image Crop and screenshot
actions remain available. Choose File accepts supported images, videos and PDFs,
with content-appropriate image, video and PDF-page controls.
Text and all live tools include native background/text color selectors and
presets. Color selection uses a non-dimming sheet so the exposed preview retains
its actual colors. Every tool/document editor labels its output Preview; the
text sample directs users to the separate editor. Recent history is in Library,
not duplicated at the bottom of Home. PDF cropping supports zoom and pan. Current Time reads the system date;
it doesn't offer meaningless restart/resume controls. Stopwatch pause is
available directly in its editor, with optional hundredths. Rounded previews and
Float stay pinned above scrolling settings, adapting to smaller viewports and the keyboard.
Text previews clip the fitted image itself, including short/wide and taller notes.
Pomodoro focus minutes, break minutes and session count can be typed directly or
adjusted with steppers; invalid values disable Float until corrected. Local videos
have Repeat Video on for each new selection and sound off. Repeat can be changed
during playback without refloating; native pause and seeking remain available.
Empty text and prompter fields show gray sample placeholders, not editable drafts;
Float uses the sample until the user supplies text. Both editors have Clear next
to Paste. Word mode offers words per group and words per minute. Teleprompter
offers a default-on three-second starting countdown (1–60 seconds), a genuine
finite script timeline, native seek callbacks and in-app position/±10s controls.
Its script preview excludes the starting countdown; actual playback includes it.
Current Time can show/hide its location and date, append the date-correct zone
abbreviation, and size all three lines independently. These display preferences
are remembered. Its setup preview ticks every second, time-zone search is visible
on entry, and Reset sizes to preset appears after any size changes. System is the
default appearance preset across text and tools; Dark, Light, Yellow and custom
colors remain available. System follows the device's appearance in previews and
live tools. Still-text output captures the chosen appearance when floated.
Scrolling scripts target 60 fps with deadline-based pacing, cached text layout,
visible-glyph drawing and fractional positioning; countdown and finite seeking
remain unchanged. PDF page selection supports validated numeric input and steppers.
The existing installed image Shortcuts and their signed packages are unchanged.
Shared text works through the supported manual/notification Share route, or
the new Float Text With Cod action in a user-configured Shortcut. PDF pages
can also arrive through explicit document opening or Float PDF Page With Cod.

Text/PDF references use the existing still-image video player. Changing tools use
timestamped video frames with AVKit's documented sample-buffer playback APIs.
Teleprompter reports a finite range synchronized to its real script position;
Current Time, stopwatch and timer/Pomodoro sessions remain non-seekable. Native
PiP buttons, resize and restore behavior are retained. An optional
**Alarm when finished** switch uses AlarmKit on iOS 26+ after user authorization.
The system delivers its sound independently of PiP, including while locked.
Keep alarm running when PiP closes defaults on for timers; turn it off to stop the
timer and cancel its alarm when PiP closes. Restoring Cod through PiP doesn't
cancel the timer. Visual timers retained after closing remain accessible on
Float until Cod quits; native alarms survive app termination. Other elapsed tools
pause when PiP closes. Timer and Pomodoro progress use a smoothly updated circular
ring. Alarm-enabled timers use a genuine AlarmKit duration countdown,
with a widget/Live Activity presentation. Timing starts when PiP opens (or as an
in-app fallback if PiP fails); asynchronous setup does not consume the chosen
duration. Automatic completion/audio interruptions must not cancel the alarm.
The timer remembers duration and uses hour/minute/second wheels. Cod reconciles
provisional alarm dates with the native countdown when ActivityKit publishes it;
logs distinguish estimated/system deadlines and alert-state delay. Acoustic
timing on the physical phone is still an acceptance check, not a simulator claim.
See [build-15 notes](docs/floating-polish-15.md), [build-14 notes](docs/floating-polish-14.md), [build-13 notes](docs/floating-polish-13.md), [build-12 notes](docs/floating-polish-12.md), [build-11 notes](docs/floating-polish-11.md), [build-10 notes](docs/floating-polish-10.md), [build-9 notes](docs/floating-polish-9.md) and the
[original floating-tools implementation](docs/floating-tools-8.md).

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
  The notification tap opens Cod; selecting the app icon alone doesn't. Focus
  and notification settings can affect delivery. The Share Shortcut above avoids
  the notification tap and is the faster supported sharing route Cod offers.
- **Share → Cod → open Cod yourself**: manual fallback. Cod automatically
  prepares the image; no Save/Done or second Float tap is required.

One tap float skips cropping; it does **not** authorize automatic app opening.
The guide explains this iOS extension/app boundary, optional Lock Screen setup,
and the native restore/full-screen control. If notification delivery isn't
available, the extension says the image is saved and explains manual opening.
Opening Cod manually can consume a pending share even with notification mode on.
No new Done tap is added to successful notification/manual-queue handoffs.
Explicit Float Shortcuts always float their supplied input. Cod no longer
automatically returns to another app or Home. Once PiP appears, switch apps
yourself; native PiP controls and system resizing remain available.

Save to a dedicated album defaults off. Existing saved preferences survive.
Share-sheet cropping offers Float only; configurable action-bar actions apply
to the editor inside Cod.

The Float tab prioritizes choosing a photo and installing the ready-made Share
Shortcut. Its setup tip can be hidden without losing access to the guide.
History deletion and lowering the retention limit require confirmation;
favorites and pending shares are separate. Favorites survive history limits,
Off and Clear Recent History, and can be filtered in Library. Favorites have a
stable top section; new favorites append without history moving them. Clear Library
offers explicit Clear Recent History and Delete Everything, Including Favorites,
with confirmation. Delete a favorite explicitly
to remove its files. Library can enable History directly. In-app pins and their
settings/Shortcut have been removed, retaining only legacy preference decoding.
Library images and videos can be floated again.

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
