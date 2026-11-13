# Build 34: audit fixes A1–A12

November 13, 2026. These fix the items the build-33 audit added to
[MVP_CHECKLIST.md](../MVP_CHECKLIST.md). The owner decided two of them:
- text shared from the Share sheet is Pro
- the Safari extension keeps overriding a site's Picture in Picture opt-out when someone taps Float

## Fixed

| # | Change |
|---|---|
| A1 | **Plan choice:** the Pro screen's plan comes from `ProPlan.offered` and `ProPlan.selection`. A subscriber who opens Upgrade to Lifetime starts on Lifetime, and the purchase button can never buy a plan that isn't shown. |
| A2 | **Shared text is Pro:** the Share extension marks rendered text in the handoff (`QuickFloatHandoff` `isText`; older records read as images). The app asks for Pro before floating or cropping it, since cropping would float it as an image. Shared images stay free. |
| A3 | **No ripgrep needed:** `verify-supported-source.sh` uses `/usr/bin/grep -rnIE` and still fails on unreadable input. |
| A4 | **Safari extension checked:** CodSafari is in the source scan, including the no-app-launch rule, and in the store verifier's binary and privacy loop, with a manifest and content-script check. |
| A5 | **Privacy screen:** it now covers the Speedometer's location use, System Monitor readings, the Safari extension and Cod Pro purchases. `PRIVACY_POLICY.md` gained a purchases paragraph. |
| A6 | **Trial length:** it comes from the App Store offer (`TrialLength`), so the badge, button, disclosure and Settings follow App Store Connect. |
| A7 | **Trial in Settings:** `ProStore.start()` loads products at launch, so Settings offers the trial before the Pro screen is opened. |
| A8 | **Off the main thread:** `VisualFileImport.open` (PDFs up to 40 MB, images up to 50 MB) runs off the main actor, and picked photos decode off the main thread. |
| A9 | **Lighter Safari script:** it does no polling, observing or scanning when Float is off or the page has no videos. The 1.5-second layout timer runs only while buttons are shown. |
| A10 | **Controls entitlements:** CodControls has its own entitlements file with only the App Group. |
| A11 | **Video task warning:** the video float task captures the PiP controller weakly, which clears the warning. The still-image path is unchanged. |
| A12 | **Launch plan ignored:** `docs/launch-plan-1.0.md` is in `.gitignore`. |

## Verification

Xcode 27.2, iPhone 17 Pro Max simulator, iOS 26.3.

- **Unit tests:** 294 run, 0 failures, 3 StoreKit skips on the simulator.
  - `Build34Tests` covers plan offering and selection, trial wording, the text flag (including older records), and the free tier asking for Pro before floating shared text while images stay free.
- **UI tests:** Build31UITests, Build32UITests and Release18UITests pass (11 tests), covering the Pro screen, PDFs and opening files.
- **Release build (unsigned):** both verifiers pass, and `Tools/test-verify-store-build.py` passes (17 tests, including the new Safari and stock-tool checks).

## Not verified here

- **On the phone:**
  - the Lifetime upgrade path and the trial wording with real products
  - shared text from the Share sheet on the free tier
  - Safari script behavior on real pages
- **Signed build:** CodControls' entitlements. The unsigned build doesn't embed them.
