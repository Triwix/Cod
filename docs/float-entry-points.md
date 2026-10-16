# Fast floating entry points — October 15, 2026

Build 3 adds optional entry points; it does not replace the working fast share
flow or silently install Shortcuts/change Back Tap settings.

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

## Shortcut packaging gate

`Tools/MakeFloatShortcuts.swift` generates the two workflows for the store/test
bundle ID and the separate personal bundle ID. The App Intent descriptor and
input binding are based on a workflow created using the real iOS 26.5 Shortcuts
editor, not a guessed action identifier. The editor also confirmed that
long-pressing the Image parameter exposes Shortcut Input.

Easy installation requires Apple-signed `.shortcut` files in
`Cod/Resources/Shortcuts/{Store,Personal}`. Signing sends workflow definitions
(including bundle/team identifiers, but no images, credentials or contact data)
to Apple's service. Security review blocked that upload pending explicit user
approval. Do not bypass it, publish an iCloud shortcut link, or claim the
installers are complete before approval and successful import testing. The app
shows truthful manual setup when signed files are absent. The simulator's own
file exporter additionally requires an iCloud sign-in; no sign-in was attempted.

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

- FastDebug: **64 unit tests passed**, including supplied-image pixel identity,
  control intent delivery/authentication, notification payload validation,
  expired/failed explicit claims, stale-ID isolation, and independent crop/
  notification preference persistence.
- Documented-only Debug: the same **64 tests passed** without compiling the
  direct-share app-opening workaround.
- Native warm Share → notification → tap → containing app **passed** in the
  iOS 26.5 simulator; the app received the actual 300×200 fixture.
- **10 native UI tests passed**, including real control-gallery registration,
  warm/cold notification taps with the correct image, crop-first notification
  handoff without a second crop, and all six prior fast-share scenarios.
  The expanded control test also passed: add the control, tap it in Control
  Center, and verify that Cod enters the foreground. This test does not claim
  actual PiP support in the simulator or grant Photos access for the user.
- Default Debug, PersonalDebug and signed FastRelease device builds succeeded.
- Artifact scans include all three bundles (app, Share, Controls); the strict
  and fast-candidate scans passed, with no App Review approval implied.
- Actual PiP and Back Tap/Action Button hardware need a physical iPhone check.
  No new build was installed on the user's phone during this sweep.

Apple reference: [Creating controls](https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system).
The [extension notification discussion](https://developer.apple.com/forums/thread/764570)
does not guarantee delivery by all extension types; runtime evidence above is
specific to the tested simulator OS, not an Apple policy approval.
