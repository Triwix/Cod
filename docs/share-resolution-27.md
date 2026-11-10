# Build 27: full-resolution Shortcut/Share input and share confirmation

November 10, 2026. This fixes the two high-priority findings (H1, H2) from the
[build-26 audit](audit-2026-11-10.md). No other behavior changed.

## H1: Shortcut and Share images keep their resolution

Before, Crop With Cod, Float With Cod and the Share extension decoded every
image at a 2048 px maximum edge. An iPhone 16/17 Pro Max screenshot (1320 ×
2868) arrived at about 943 × 2048, which blurred crops and weakened OCR.

- Intents run in the app and now decode up to **4096 px**
  (`UIImage.appImportMaximumEdge`).
- The Share extension now decodes up to **3000 px**
  (`UIImage.shareExtensionMaximumEdge`). That covers every current iPhone and
  iPad screenshot at native size, and stays within the extension's memory
  budget.
- The handoff from extension to app stays lossless PNG when it fits under
  32 MB. A detailed photo that would exceed that falls back to JPEG (quality
  0.92) instead of failing with "too large".

## H2: Sharing to the Cod icon says what to do next

Before, with the default settings (notifications off), the extension showed
"Preparing image…" and then closed. Nothing floated, and nothing explained that
Cod has to be opened. The extension now stays on **Image ready — "Tap Done,
then open Cod to float it"** (or "to crop and float it" when One tap float is
off), with the existing note about the Float with Cod Shortcut. It still never
opens Cod itself. Notification mode is unchanged: a successful notification
handoff still closes right away.

## Verification

Xcode 27.2, iPhone 17 Pro Max simulator, iOS 26.5:

- **Unit tests:** 250/250 pass, including two new tests:
  - A native 1320 × 2868 screenshot keeps its size through both the Shortcut
    and the Share decoding paths.
  - The handoff falls back to JPEG.
- **UI tests:** 13/13 pass.
  - All of `LaunchFlowTests` and `NotificationFlowTests`, plus the shared-text
    test.
  - The manual-share tests now require the ready screen, check its "open Cod"
    text, confirm Cod didn't open, and then tap Done.
- **Release archive:** unsigned, CFBundleVersion 27. `verify-store-build.sh`
  passes.
- **Source check:** `verify-supported-source.sh` passes with ripgrep on PATH.

Not yet checked: the ready screen and full-resolution crops on a physical
iPhone, and the extension's memory headroom with very large shared photos on a
device.
