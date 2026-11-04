# Crop drag lifecycle · 1.0 (26)

November 4, 2026. Branch: `codex/crop-drag-lifecycle26`.

## Finding and fix

The [build-25 audit](https://cod-launch-b13d0b.sites.tab.bot/) identified a valid
ownership problem: the selection's conditional tap layer also owned a drag.
Collapsing its rectangle, moving it out of view, or making the selection nil
could remove that layer before normal drag completion. The persistent drag mode
and magnifier point then had no guaranteed cleanup path.

- A single drag recognizer now belongs to the **stable parent canvas**, with
  priority over its child tap recognizers. The selection layer owns only its
  double-tap. Removing that layer no longer removes an active drag handler.
- Drag activity uses GestureState. Normal completion and the automatic reset
  after cancellation invoke the same idempotent cleanup: clear the drag mode,
  magnifier point, page-pan anchor and pre-drag snapshot; bound the pan again.
- Magnifying also uses GestureState, so cancellation cannot leave the editor's
  magnifying flag true. Pinch completion/reset clears its starting zoom and
  bounds the page pan.
- A collapsed/invalid resize restores its preceding valid crop. An invalid new
  selection with no preceding crop returns to whole-image actions. Previously
  selected small blocks remain valid recovery targets. A crop outside the
  viewport is retained if it is still inside the image; viewport visibility
  does not determine gesture ownership or selection validity.
- Null resize intersections are converted to no selection instead of passing an
  infinite-origin rectangle to the selection chrome/readout.

Single taps outside the selection remain immediate. Double-tap still requires
an existing region and an enabled Float action. The Share extension continues
to use its existing handoff callback; there are no new launch routes, permissions
or private APIs.

Apple documents [gesture priority](https://developer.apple.com/documentation/swiftui/view/highprioritygesture(_:including:))
and [automatic GestureState reset on completion or cancellation](https://developer.apple.com/documentation/swiftui/gesture/updating(_:body:)).
The [gesture guidance](https://developer.apple.com/documentation/swiftui/adding-interactivity-with-gestures)
distinguishes transient state from successful onEnded callbacks. These documented
mechanisms are used here; they are not an App Review guarantee.

## Verification and limits

Artifacts: `/private/tmp/cod-release26.eHbqrJRV`.

- **Twelve actual host XCTest cases pass** using the repository's source and
  test files in the temporary macOS package. The added cases cover collapse onto
  the opposite corner, invalid/null/non-finite completion, no previous selection,
  small-block recovery and valid image crops outside the zoomed viewport.
  Existing geometry, minimum-size and settings/gesture checks remain passing
  (`crop-host26-final.log`). These are policy/model tests, not SwiftUI event tests.
- **Sixteen artifact/source verifier tests pass** on disposable copies of the
  Release app. The supported-source and final Release artifact audits pass.
  Cod Debug, the unit-test bundle, launch harness, UI-test bundle and Release
  archive compile without concurrency warnings. A signed Debug device package
  passes deep/strict signature verification. The Release archive remains unsigned
  local verification, not distribution/TestFlight validation.
- Added a targeted UI regression: draw a crop, drag its top-left handle exactly
  onto its opposite corner, verify recovery, then draw elsewhere and verify the
  new dimensions rather than a stale resize. It compiles. The iOS unit suite and
  affected UI cases were attempted, but the same Apple DTServiceHub/lockdown
  failure occurred before the first case; the attempts were stopped. No iOS unit
  or UI case is counted as passed for this build.
  A normal GUI launch of `/Applications/Xcode.app` was rechecked on November 4
  and still returns `kLSIncompatibleApplicationVersionErr` for this macOS version.
- In a simulator copy with the shared parent drag handler, a double-tap before
  selecting chose a detected block without floating. After Select Whole Image,
  double-tap on the real canvas reached Float, saved its history entry and showed
  the simulator's **Not available here** PiP recovery state. The final pinch-reset
  and small-block fallback changes were subsequently compiled/host-tested.

The original stuck drag has not been dynamically reproduced on this Mac. The
new collapse/cancellation UI case, pointer dragging, resize crossing, off-screen
movement, pinch interruption and actual PiP still need execution on a working
test runner or physical device. The earlier simulator-control pointer limitation
is not treated as a successful drag test. This pass fixes the identified source
ownership/lifecycle paths and records the remaining runtime gap explicitly.

Build 26 is prepared but **not installed on the phone**. The original Cod app and
data are untouched. Publishing/contact/privacy hosting remains owner-deferred;
distribution signing, supported-old-OS launch and physical acceptance remain in
the [MVP checklist](../MVP_CHECKLIST.md).

The built app's development profile was decoded and its expiry confirmed as
**November 4, 2026, 10:33:39 PM Pacific**. Refresh development provisioning before
installing/testing after that deadline. This is separate from distribution signing.
