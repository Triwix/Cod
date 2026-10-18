# Fast floating entry points — October 18, 2026

Build 4 packages signed Shortcut installers for the optional entry points added
in build 3. It does not replace the working fast share flow or silently install
Shortcuts/change Back Tap settings.

## Implemented

- **Control Center / Lock Screen / Action Button (iOS 18+)**: a new `CodControls`
  WidgetKit extension exposes Float Latest Screenshot. Its `FloatControlIntent`
  conforms to `OpenIntent`, is compiled into both the app and control extension,
  requires authentication, and delivers the existing latest-screenshot request
  after the system opens Cod. It needs a saved screenshot and Photos access.
  Limited Photos access sees only permitted screenshots. The control itself
  does not capture the current screen or receive an arbitrary viewed photo.
- **Back Tap**: a Screenshot and Float with Cod workflow captures a new
  screenshot and explicitly passes that action's output to `FloatWithCodIntent`.
  Users install the Shortcut and assign Double/Triple Tap themselves in
  Settings → Accessibility → Touch → Back Tap. Action Button can also run it.
- **Share-sheet Shortcut**: Float with Cod accepts Images, enables
  `ActionExtension`, and binds `image` to the `ExtensionInput` token. Missing
  input stops rather than asking for an unrelated file. This workflow appears
  in the share action list, not the app-icon row. Initial system permission
  confirmations may add first-run steps.
- **Notification handoff**: Settings → Share Sheet → Tap notification to float
  requests permission in the containing app. The Share extension writes the
  actual image to the App Group, then schedules one notification with a request
  UUID only. A tap foregrounds Cod; the launch delegate queues the request even
  before RootView exists. One tap float off crops inside the extension first.
  The notification path never invokes the fast-share app-opening workaround.

The notifications option defaults **off**, preserving the current installation's
behavior. Turning it off removes only Cod's float notification. Focus, summaries,
banner settings and revoked permission can affect delivery. A scheduling failure
shows an error and keeps the image for explicit retry in Cod. No silent fallback
to an unsupported app launch, no remote push server, sound, image attachment,
clipboard transport, or time-sensitive privilege is used.

## Signed Shortcut packaging

`Tools/MakeFloatShortcuts.swift` generates the two workflows for the store/test
bundle ID and the separate personal bundle ID. The App Intent descriptor and
input binding are based on a workflow created using the real iOS 26.5 Shortcuts
editor, not a guessed action identifier. The editor also confirmed that
long-pressing the Image parameter exposes Shortcut Input.

All four Apple-signed `.shortcut` files are bundled in
`Cod/Resources/Shortcuts/{Store,Personal}`. The user approved sending these
definitions to Apple's signing service on October 18. They include bundle/team
identifiers, but no images, clipboard, credentials or contact data. Host signing
with `shortcuts sign --mode anyone` succeeded without signing the simulator into
iCloud or publishing an iCloud link. The in-app guide offers Add Shortcut
buttons; the user chooses Shortcuts and approves installation. They still assign
Back Tap themselves in Settings. The guide retains manual instructions only as
a fallback when files are absent.

iOS 26.5 shows an initial **Allow [Shortcut] to share [item] with Cod Test?**
dialog. This is a system data-sharing permission, not a manual Open Cod step or
file picker. Allow Once repeats it on subsequent runs; Always Allow is the
user's option for avoiding repeated prompts. Tests use Allow Once and never
grant persistent access on the user's behalf.

## Correctness and privacy

- Notification UUIDs are validated against the current App Group request. A
  stale tap never falls through into floating a newer pending image.
- Notification taps are explicit actions and can resume the exact expired or
  failed request, but cannot claim one already in progress. Ordinary activation
  retains the existing no-replay/expiry behavior.
- The app sets its notification delegate before launch finishes so cold taps
  are not lost. Work waits for an active scene, and busy PiP work defers it.
- Shortcut images are decoded with ImageIO to a maximum 2048-pixel edge and a
  32 MB encoded-input limit; input never falls back to the newest library photo.
- The control includes its own no-tracking/no-collection privacy manifest and
  has no App Group, keychain, Photos or clipboard access in the widget process.
- Supported entry-point APIs do not preapprove the app's still-image PiP use.
  `Cod Fast` still contains the separately disclosed unsupported direct-share
  launcher; use the default `Cod` scheme to exclude it entirely.

## Verification

- Build 4 FastDebug: **66 unit tests passed**, including signed installer
  bundling, explicit Float ignoring the crop preference, supplied-image pixel identity,
  control intent delivery/authentication, notification payload validation,
  expired/failed explicit claims, stale-ID isolation, and independent crop/
  notification preference persistence.
- Build 4 documented-only Debug: the same **66 tests passed** without compiling the
  direct-share app-opening workaround.
- Native warm Share → notification → tap → containing app **passed** in the
  iOS 26.5 simulator; the app received the actual 300×200 fixture.
- Build 4: **12 native UI tests passed**, including real control-gallery registration,
  warm/cold notification taps with the correct image, crop-first notification
  handoff without a second crop, all six prior fast-share scenarios, and the two
  signed Shortcut tests below. The control test passed: add the control, tap it in Control
  Center, and verify that Cod enters the foreground. This test does not claim
  actual PiP support in the simulator or grant Photos access for the user.
- Default Debug, PersonalDebug and signed FastRelease device builds succeeded.
- Artifact scans include all three bundles (app, Share, Controls); the strict
  and fast-candidate scans passed, with no App Review approval implied.
- Native build 4 imports reached Apple's Add Shortcut interface for both signed
  workflows. Run testing found and fixed a capture-template error: the screenshot
  workflow must not use Stop and Respond for missing external input, because it
  produces its own image. Share input remains explicitly required.
- Both new native Shortcut tests passed unattended: signed import through the
  app's installer, native image-sharing permission (Allow Once), cold launch
  with the 300×200 shared fixture, replacement with the 148×92 second fixture,
  and a fresh screenshot delivered at 942×2048. No file picker or manual app
  activation was used. Actual PiP remains unavailable in the simulator.
  Installer UI tests are simulator-only and never replace phone Shortcuts.
- Actual PiP and Back Tap/Action Button hardware need a physical iPhone check.

## Physical acceptance still required

On the new iPhone, verify the actual image remains visible in PiP after leaving
Cod, repeat with a different image, and try each chosen entry point. Control
Center needs a screenshot already saved to Photos and permission to see it;
the capture Shortcut uses its own new screenshot instead. Assigning Back Tap,
Lock Screen, or Action Button remains a user-controlled setup step.

After the user enabled Developer Mode, device-specific development signing
succeeded and **Cod Test 0.1.0 (4)** was installed wirelessly on the new iPhone
16 Pro Max running iOS 27.0.1. The device's installed-app record confirms the
bundle ID and build. Deep signature verification passed and the development
profile includes that phone. First launch was denied with iOS's signing/trust
message. The user trusted their development profile and confirmed that Cod Test
opens successfully on October 18. The user then reported the Photos share/PiP
flow seemed good and explicitly confirmed the Control Center screenshot route
worked. Physical Back Tap, Lock Screen/Action Button, installed share Shortcut,
and notification checks remain pending. The original Cod identity remains untouched.

Apple reference: [Creating controls](https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system).
The [extension notification discussion](https://developer.apple.com/forums/thread/764570)
does not guarantee delivery by all extension types; runtime evidence above is
specific to the tested simulator OS, not an Apple policy approval.
