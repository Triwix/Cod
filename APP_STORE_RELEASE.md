# App Store release gates

Current candidate: **Cod Test 0.1.0 (6)**, Cod scheme, Debug/Release only.
Unsupported automatic extension launch, private return/navigation, hidden
PiP controls, origin probes, and extension-side PiP experiments are removed.
There is no separate experimental/personal scheme or opt-in audit bypass.

## Remaining before submission

- Validate actual image PiP on a physical device using the supported entry
  points, including repeat/replacement, early restore, and background playback.
  Back Tap, Lock Screen and Action Button setup must be confirmed by the user.
- Confirm notification behavior on the target OS; Focus, banners, summaries,
  and permission changes can affect delivery. Manual opening remains fallback.
- Obtain Apple Developer Program membership and the required distribution/App
  Group provisioning, create the App Store Connect record, and validate a signed
  Release archive/TestFlight build. Development installation is not submission.
- Host the privacy policy, configure `COD_PRIVACY_POLICY_URL` in project.yml,
  and verify it inside the built app. Run the artifact audit with `--submission`.
- Complete App Store privacy answers, support URL, age/content rating, export
  compliance, listing text and device screenshots. Set the public display name
  from Cod Test to Cod when ready; keep testing identity changes deliberate.
- Provide clear reviewer instructions for Shortcuts/controls and actual PiP.
  Explain the still-image video implementation honestly. Only Apple can decide
  whether its use fits review requirements; public APIs are not preapproval.

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
