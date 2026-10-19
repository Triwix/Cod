# App Store release gates

Current candidate: **1.0 (7)**, Cod scheme, Debug/Release only. Public Release
display name is **Cod**; development device builds explicitly use **Cod Test**
and keep the separate `com.josh.cod.store` installation identity.
Unsupported automatic extension launch, private return/navigation, hidden
PiP controls, origin probes, and extension-side PiP experiments are removed.
There is no separate experimental/personal scheme or opt-in audit bypass.

## Remaining before submission

- Basic Choose Photo and Share Shortcut floating were confirmed by the user on
  Cod Test 1.0 (7), including switching apps. Complete extended physical-device
  checks for repeat/replacement, early restore, resizing, and background playback.
  Back Tap, Lock Screen and Action Button setup must be confirmed by the user.
- Confirm wide-window/landscape behavior on an iPad before universal release.
  The simulator's windowed mode retained a portrait viewport, so that specific
  geometry check is explicitly skipped, not counted as passed. The iPhone's
  stricter landscape check passed.
- Confirm notification behavior on the target OS; Focus, banners, summaries,
  and permission changes can affect delivery. Manual opening remains fallback.
- Obtain Apple Developer Program membership and the required distribution/App
  Group provisioning, create the App Store Connect record, and validate a signed
  Release archive/TestFlight build. Development installation is not submission.
- Host the privacy policy, configure `COD_PRIVACY_POLICY_URL` in project.yml,
  and verify it inside the built app. Run the artifact audit with `--submission`.
- Complete App Store privacy answers, support URL, age/content rating, export
  compliance, listing text and device screenshots. Review the prepared
  [submission draft](docs/app-store-draft.md); replace owner placeholders.
- Confirm the final publishing team/bundle/App Group before signing. Bundled
  signed Shortcuts refer to an exact app/team; if either changes, regenerate
  and sign matching workflows with approval. The installer and release audit
  reject mismatched package metadata instead of offering a broken workflow.
- Provide clear reviewer instructions for Shortcuts/controls and actual PiP.
  Explain the still-image video implementation honestly. Only Apple can decide
  whether its use fits review requirements; public APIs are not preapproval.

## Scope completed in the polish pass

- Float-first Home, ready-made Share Shortcut installer, dismissible setup tip,
  clearer guide and fallback instructions, and direct floating from Library.
- Large-text/landscape support for the home and launch views, clearer accessible
  labels, higher-contrast filled buttons and readable error toasts.
- Confirmation before clearing history or reducing retention; existing Photos,
  preferences, pins and pending shares are not cleared by those operations.
- Corrected decoded-image cache accounting and in-app pin control touch areas.
- Removed unused routes, store methods and Share-extension source memberships;
  retained legacy decoding/inbox data for compatibility, not new features.
- Idle PiP prewarm is released on backgrounding without an active float.
- Explicit privacy manifests and local source/Release packaging checks. These
  are not a substitute for distribution validation or App Review.

Videos remain a later feature, not a requirement of this still-image MVP.
See the [build-7 handoff](docs/release-polish-7.md) for verification evidence,
development artifacts and the final phone acceptance list.

## Verification commands

Generate with `xcodegen generate`; test the **Cod** and **Cod Launch Tests**
schemes against an installed simulator. Build **Cod / Release** for the device
or archive, then run:

```sh
zsh Tools/verify-supported-source.sh
zsh Tools/verify-store-build.sh /absolute/path/to/Cod.app
zsh Tools/verify-store-build.sh /absolute/path/to/Cod.app --submission
```

The final command intentionally fails until a real HTTPS privacy-policy URL
is configured. Verify distribution signing and all three embedded bundle
entitlements separately. These checks do not establish review acceptance.

Older release/test narratives live in Git history. Research documents kept in
the repository are historical and must not be used to restore removed tricks.
