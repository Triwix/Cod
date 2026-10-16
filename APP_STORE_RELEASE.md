# App Store V1

Build 3 adds a WidgetKit control and an optional notification-based Share
handoff without changing the direct-share default. See
[entry points and release/testing gates](docs/float-entry-points.md). The
documented-only scheme excludes the fast launcher; enabling notifications is
a one-time permission/setup step, not a private launch workaround. Signed
Shortcut installer files still require explicit signing approval and import QA.

October 15 update: **Cod Fast** is now a separate fast-launch usability
candidate; see [FAST_SHARE.md](FAST_SHARE.md). It intentionally retains only the
unsupported responder-chain app launch, with no private return/control hiding.
The default **Cod** scheme below remains the documented-only comparison, not
the user's accepted MVP. Neither is approved or submission-ready.

Updated October 7, 2026. This is a public-API test candidate, not an approved or
submission-ready app. The product goal is image → PiP as quickly as possible,
ideally native Share → Cod → PiP. The user rejected Save/Done/inbox Float as the
MVP workflow. The remaining manual-open fallback is not acceptance of that goal.

## Two independent configurations

- **Cod** scheme: Debug / Release; app `com.josh.cod.store`, extension
  `com.josh.cod.store.share`; App Group `group.com.josh.cod.store`.
- **Cod Personal** scheme: PersonalDebug / PersonalRelease; original app
  `com.josh.cod` and extension `com.josh.cod.share`. Only these configurations
  define `COD_PERSONAL`, compiling the unsupported automatic launch/return
  and experimental control hiding. Never submit this scheme.
- The working phone installation has not been replaced. The source immediately
  before this transition is saved in
  `.checkpoints/pre-app-store-transition-20261006.tar.gz`.
- The separate store bundle ID permits installation alongside the personal app.
  The store version has a separate history and settings; there is no implicit
  migration or deletion of the user's personal data.

## Current fast-flow test workflow (not final MVP acceptance)

1. Share one image → **Cod Test**. Cod prepares it and dismisses the extension
   automatically; no Save or Done button.
2. Open **Cod Test** within five minutes. It immediately attempts Float, with
   no inbox selection or second Float tap. This manual app-open step remains
   unresolved for the native share extension.
3. **Choose Photo** inside Cod also goes directly to PiP. Direct image document
   input floats automatically if the source really launches the app; a menu
   called “Open in” may instead invoke the share extension. Do not advertise
   document-opening as a universal Photos/Files share workaround.
4. **One tap float** defaults on for this separate public build. Turn it off
   for cropping before Float. Explicit Float/Crop Shortcuts retain their semantics.
5. One latest request is kept in the App Group, excluded from backup. New shares
   replace the previous pending request. Successful PiP start removes the
   temporary request; failure/interruption/cancel keeps an explicit retry.
   Requests are claimed persistently before starting and never replay on
   restoration, ordinary activation or restart. After five minutes they need
   explicit retry. Older inbox data remains available without silent deletion.
6. Once PiP is visible, switch apps manually. Normal system controls remain.
7. Optional foreground Shortcuts remain available. They do not return to an
   arbitrary original app. Normal system PiP controls are retained.

The share extension never requests the app to launch in this configuration.
All private origin/return probes and control methods are compiled out of both
Debug and Release. The extension enables `APPLICATION_EXTENSION_API_ONLY`.
Imgur upload is personal-only; store V1 keeps processing on device, with explicit
system sharing, URL opening and system translation remaining user choices.

## Verification

October 7 fast-flow checks and experiment details are in
[FAST_LAUNCH_TESTS.md](FAST_LAUNCH_TESTS.md). Development signing now succeeds for
the separate app and extension, and both signed entitlements include the actual
matching App Group. This is not a distribution archive or App Store approval.

Earlier October 6 baseline, superseded by the fast-flow changes:

- Store configuration: **40 simulator tests passed**, zero failures/skips.
- Personal configuration: **62 simulator tests passed**, zero failures/skips;
  the original private-flow tests run only in this configuration.
- Unsigned device Release build passed; the preserved PersonalRelease build
  also passed. These are compilation checks, not distribution archives.
- The known-private-code/resource check passed for both the store device
  Release artifact and simulator Debug artifact. It rejects the PersonalRelease
  artifact; submission mode also correctly rejects the blank policy URL.
- App/extension matching App Group metadata and both privacy manifests are
  verified by tests. Simulator code signing uses simulated entitlements; this
  does not prove actual device provisioning or cross-process share delivery.
- Simulator launch and screenshot show the new inbox and manual workflow.
  No end-to-end share-extension UI/PiP device pass is claimed; desktop simulator
  UI control timed out, and native PiP remains a physical-device test.

Repeat these checks after any remaining signing, UI or release changes.

- Generate with `xcodegen generate` after editing `project.yml`.
- Test **Cod** on an installed simulator; also run **Cod Personal** tests to
  check that the retained personal flow still compiles and its tests pass.
- Build Release for a generic iOS device, then run:

  ```sh
  zsh Tools/verify-store-build.sh /absolute/path/to/Cod.app
  ```

  The check verifies the store identities, bundled manifests, App Group metadata,
  and absence of known personal/private method strings. It is a regression
  safeguard, not proof of every Apple review requirement.
- Both bundles contain a required-reason manifest for their own UserDefaults
  preferences (`CA92.1`). Shared images use files, not shared UserDefaults.
- Re-run against the final signed archive, including `--submission` after the
  real hosted privacy policy is configured. Validate signing and actual
  entitlements separately in Xcode/App Store Connect.

## Release gates still open

- [ ] Resolve or explicitly agree on the remaining native-share app-launch
  limitation without calling the slower fallback the requested one-tap MVP.
  The document menu did not foreground Cod. The public intent button executed
  inside the Share extension, not the app; signing/metadata limits mean this
  does not establish the outcome on every other system/device intent surface.
- [ ] Confirm distribution eligibility and App Store identities/profiles. Both
  app and extension now sign successfully for development with their matching
  App Group; distribution signing and App Store Connect setup remain unverified.
- [ ] Physically verify the shared App Group across the separately signed app
  and extension: Photos, screenshot preview, Files, Messages; cold/rebooted
  launches, repeated/replacing shares, removal, crop cancel and explicit retry.
- [ ] Physically verify PiP with manual app switching, early taps, restoration,
  dismissal, lock/unlock, rotation, native resize, music and another app's PiP.
  Simulator tests cannot establish native PiP visibility or longevity.
- [ ] Test current iOS and the oldest supported iOS 17 version, plus iPad if
  keeping the current iPhone+iPad target. Test VoiceOver and large text.
- [ ] Fill contact details in `PRIVACY_POLICY.md`, approve its wording, host it
  at a stable HTTPS URL, and set `COD_PRIVACY_POLICY_URL` in `project.yml`.
  The in-app Privacy screen exists, but a real policy/contact link is required
  before submission. The URL is intentionally blank, not a fake placeholder.
- [ ] Complete App Store privacy answers using the final signed app's actual
  behavior. Do not copy a "no data collected" claim from a template; review
  any services or SDKs added later and the policy again.
- [ ] Choose final branding, version/build, pricing, age-rating and export
  compliance answers. Add app/support URLs, screenshots for advertised devices,
  store description and review instructions explaining the actual agreed flow.
- [ ] Produce a signed distribution archive, validate and upload it, run
  TestFlight acceptance, then submit for review. No upload or publication yet.
- [ ] Assess review feedback on still-image looping video and background PiP.
  Public APIs alone don't guarantee the intended-purpose/background policy is
  satisfied. Explain the real implementation rather than disguising it.

Videos and automatic return to Spotify beneath screenshot preview are deferred.
Neither is advertised as working in store V1.

## Official references

- [Review guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)
- [Required-reason API declarations](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
- [Submission](https://developer.apple.com/app-store/submitting/)
