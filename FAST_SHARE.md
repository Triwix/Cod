# Fast share candidate — October 15, 2026

Product requirement: **Share → Cod → PiP**, no user-created Shortcut and no
separate app-open step. The documented-only/manual-open fallback is not the MVP.

## Implemented candidate

**Cod Fast** (`FastDebug` / `FastRelease`, `COD_FAST_SHARE`) updates the separate
**Cod Test** app (`com.josh.cod.store`), not the original `com.josh.cod` app.
Build number is 3. **Cod** Debug/Release retains the documented-only comparison
build; **Cod Personal** retains its original implementation and identity.

- With **One tap float on** (default), selecting Cod Test in Share receives the
  image, saves a one-shot request to the App Group, opens Cod automatically,
  then attempts PiP when Cod's scene is active. No Save, Done, second Float tap
  or separate user app-open action.
- With the switch off, cropping happens **inside the Share extension**. Float
  launches the selected image directly; it does not ask the user to crop again.
- Build 4 packages signed Shortcut installers alongside the optional notification
  launch method, system control, and Shortcut routes added in build 3. These
  do not replace the default direct share.
  See [entry-point setup and verification](docs/float-entry-points.md).
- The main app still comes to the foreground to start PiP. This is not invisible
  background PiP, and this build does not automatically return to the source app.
- Native PiP controls remain. Private source-app inspection, automatic return,
  control hiding, Imgur upload and clipboard image transport are excluded.
- Existing Cod Test settings/history and older inbox data are preserved. New
  shares use one latest App Group request, excluded from backup and removed
  after PiP reports a successful start. The original Cod app is not overwritten.

## Exact launch mechanism and review risk

`CodShare/FastShareAppLauncher.swift` finds an existing UIApplication through
the extension's public responder chain and calls its public `open` method.
It does not call UIApplication.shared, private selectors, dynamic symbol lookup,
runtime method injection or another app's APIs. `APPLICATION_EXTENSION_API_ONLY`
stays **YES**, and this compiles under that restriction.

**That is not the same as Apple supporting this use.** Apple engineers say
ordinary Share extensions have no supported containing-app launch contract.
Their warnings cover runtime workarounds and intended API use. A separate,
recent public question asks about this exact direct responder-chain variant;
it had no Apple reply when checked on October 15, 2026. It is not approval.

The candidate deliberately separates:

1. Technical usability: test warm/cold Share → automatic app launch → correct
   image → PiP on the physical phone.
2. Review eligibility: the unsupported launch use and still-image video/PiP
   purpose remain explicit risks. No local scan, successful build, other app's
   behavior or DTS discussion guarantees acceptance.

Do not hide the mechanism, add obfuscation, remote flags, change behavior for
reviewers, or claim Apple has approved it. No App Store upload/submission or
external support/forum message was authorized or performed in this work.

## Reliability controls

- URLs contain only a UUID matching the latest stored request, not image bytes,
  arbitrary file paths or source-app identifiers.
- Claims check the expected ID and are persisted before PiP starts. An old URL
  cannot claim a newer record through that ID-checked path; stale completions
  cannot delete or acknowledge a new request.
- A newer explicit share can replace an old crop. If a float is preparing, the
  launch request stays queued and is retried on completion, not silently lost.
- Each explicit extension Retry creates a fresh request ID. No automatic loop
  of app launches, no notification or clipboard workaround.
- Responder traversal is cycle-checked and limited to 32 objects. The actual
  launch callback has a three-second deadline and can complete only once.
- App scene activation precedes starting PiP. Large files are decoded to bounded
  images; native UIImage share providers retain the earlier import fallback.

## Verification and reproducibility

- `Cod Fast Launch Tests`: native UI harness, real system Share and Open In
  menus, known 300×200 and 148×92 fixture images. The fast-path assertions wait
  for Cod to become foreground; they **do not activate it themselves**.
- Warm/cold launch, native image/file receipt, second-image replacement,
  crop-before-launch, and cancelling crop are covered by UI scenarios.
- `Cod Fast` tests cover the handoff, request URL validation, busy deferral,
  stale request rejection, crop replacement, rendering and existing state logic.
- Default `Cod` and preserved personal regression suites remain separate.
- Build UI tests, explicitly install that built Cod.app into the simulator,
  then run test-without-building. The test harness doesn't install Cod for you.
- Cold system URL launches don't inherit XCTest process arguments. FastDebug
  exposes a received-image-size diagnostic to verify receipt; FastRelease does
  not include the diagnostic UI.

### Results from this sweep

- **Six native fast-share scenarios verified**: cold launch, warm image-object
  share, file/document-menu share, a distinct second image, extension crop then
  Float without a second crop, and cancel without replay. Five passed in the
  main run; cold launch then passed in its corrected diagnostic-only rerun.
  The first cold run did launch Cod but could not see the test label because
  system launches omit XCTest arguments. This was a test visibility issue,
  not recorded as a passing image-receipt assertion until the rerun.
- **57 FastDebug unit tests passed**, zero failures/skips.
- **57 documented-only Debug unit tests passed**, zero failures/skips.
- **79 preserved PersonalDebug unit tests passed**, zero failures/skips.
- FastRelease builds and signs for device. Both actual signed entitlements
  include the matching App Group. Full signature verification succeeds when
  macOS certificate trust services are available outside the sandbox.
- Fast-candidate audit passes, and the ordinary documented-only audit rejects
  it as intended. The documented-only Debug artifact passes its strict audit.
- **Cod Test 0.1.0 (2)** was installed on the paired iPhone and reinstalled again
  at the user's request. A filtered installed-app check confirms build 2.
  These commands target only `com.josh.cod.store`; no original Cod removal or
  replacement was performed. Physical PiP success still requires the user's test.
  A subsequent attempt to open Cod Test remotely was blocked because the phone
  relocked; that did not undo the successful install or change its build number.

Audit the actual phone app with:

```sh
zsh Tools/verify-store-build.sh /absolute/path/Cod.app --fast-candidate
```

This rejects known private/personal code and launch-probe code, checks shared
metadata/privacy resources and requires the explicit responder-chain policy.
The ordinary documented-only audit intentionally rejects this configuration;
it must not silently be mistaken for the strict comparison build. Neither
audit gives App Review approval. Actual PiP is unsupported in the simulator.

## Sources

- [Apple frameworks engineer: supported extension launch limits](https://developer.apple.com/forums/thread/773342)
- [Apple DTS: extension launch workaround warning](https://developer.apple.com/forums/thread/114485)
- [Exact direct responder-chain variant: unanswered question](https://developer.apple.com/forums/thread/848791)
- [Review Guideline 2.5.1: public APIs and intended purposes](https://developer.apple.com/app-store/review/guidelines/#software-requirements)

Videos remain deferred. Universal original-screen return is not claimed solved.
