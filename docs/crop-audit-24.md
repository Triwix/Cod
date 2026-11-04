# Crop interaction and audit follow-up · 1.0 (24)

November 3, 2026. Branch: `codex/crop-gesture-and-audit24`.

## Interaction

- Double-tap **inside an existing selected image/PDF region** to perform the
  same Float action as the button. The hint appears with the selected dimensions.
  Double-tapping before selecting, on the backdrop, or in Move mode does not
  float. The video-region editor retains its explicit Apply Crop button.
- Taps and drags use exclusive documented SwiftUI recognizers. A tap no longer
  starts a zero-distance drag that could change the crop before recognition.
  Pinching remains simultaneous; pixel selection is independent of zoom/pan.
- Selection options → Adjust Crop provides native steppers for all four pixel
  edges, plus Select Whole Image. VoiceOver exposes Adjust crop and Float
  selection actions. The adjustment sheet starts from the exact integral output
  rectangle; opposite edges remain fixed and at least one pixel is retained.
  This adds an alternative to dragging, not a full-app accessibility claim.
- The Floating Guide explicitly separates immediate Back Tap floating from
  crop-first setup: **Take Screenshot → Crop With Cod**, with Image bound to
  Take Screenshot's Screenshot output. Assign the resulting shortcut in iPhone
  Settings. This uses the existing supported intent and always opens the editor,
  independently of One tap float. Existing signed installers are unchanged;
  the crop-first route is clearly documented manual Shortcut setup.
- The shared crop view in the Share extension invokes its existing handoff
  callback. It still cannot open Cod or start PiP itself. With notification
  handoff enabled, tap the notification; otherwise open Cod manually. The Share
  Shortcut remains the fastest supported sharing route.

## Latest external audit

The [build-23 audit](https://cod-launch-b13d0b.sites.tab.bot/) reported no new
blocking code bugs and confirmed the verifier and rendering fixes. Its remaining
privacy/support/distribution/device/test gates remain open.

- Transparent images now receive a light or dark matte for the temporary opaque
  PiP video, estimated from a 16 × 16 premultiplied foreground sample. Dark logos
  and white artwork can both retain contrast; this is a heuristic, not a guarantee
  for every mixed-color design. Source alpha, crops and originals are unchanged.
- Swift concurrency checking is now **targeted** in the app, Share extension,
  Controls extension and unit-test target. The GIF encoder's ImageIO source,
  options and mutable progress are explicitly confined to its serial encoding
  queue. Live Text state is main-actor isolated and cancelled results cannot
  overwrite the analysis of a newer image. No warnings are silenced with a new
  preconcurrency import or a blanket unchecked conformance.
- The source guard now covers the additional private-class/launcher markers
  scanned in the artifact. New host fixtures test short markers directly in
  source: short Swift strings may be inlined into instructions and evade byte
  scans. Both guards are required; neither is an App Review guarantee.
- `ITSAppUsesNonExemptEncryption` is explicitly false for the current OS-only
  Keychain/file-protection use, and the artifact guard requires that declaration.
  No cryptography library or proprietary algorithm was found. Reassess this if
  dependencies or encryption behavior change. No App Store Connect answers or
  submission have been entered. See Apple's [key documentation](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption)
  and [export guidance](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations).

The two existing non-secret shared Keychain preferences are retained to preserve
installed choices and the tested app/extension transport. Their survival after
app deletion is a known low-priority behavior, not a new shipping blocker.
The timer/host-clock privacy reason remains declared for elapsed-time operations;
it is not removed merely because the source uses clock wrappers rather than a
direct uptime call. Public APIs still do not establish review acceptance of
non-video PiP/background playback.

## Verification and remaining limits

Artifacts: `/private/tmp/cod-release24.eRz78ayT`.

- **Seven actual SelectionGeometryTests pass on macOS** using the repository's
  unchanged geometry source and test file in a temporary Swift package. This
  includes the new edge-bound/fractional/single-pixel checks. This is a host-only
  geometry run, not the iOS unit suite.
- **Sixteen host-side artifact/source guard tests pass**, including short source
  markers and missing/changed encryption declarations. Disposable copies are
  used; the original archive is not mutated.
- Cod Debug, the unit-test bundle, the launch harness and affected UI-test bundle
  compile. Targeted concurrency emits no concurrency warnings. Release archive,
  supported-source guard and artifact audit pass. This is an unsigned local
  Release archive, not distribution signing or TestFlight validation.
- A signed Debug device build and deep/strict signature verification pass.
  Build 24 has **not** been installed on the phone; the original Cod app/data
  remain untouched.
- Both the iOS unit suite and affected UI-test run were attempted. Apple's test
  service again failed before starting a case; the attempts were interrupted
  after repeated startup errors. No iOS unit or UI tests count as passed for 24.
  The two new rendering/intent tests compile but remain unexecuted on iOS.
- The final interactive Simulator check was blocked by the Mac's locked screen.
  Do not claim the gesture has been exercised end to end until that check and
  actual phone PiP acceptance are completed.

Owner-deferred publishing identity, support/privacy hosting, compatible test
tools, iOS 17/18 launch, signed distribution validation and physical-device
acceptance remain in the [MVP checklist](../MVP_CHECKLIST.md).
