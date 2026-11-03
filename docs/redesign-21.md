# Native refinement · Cod Test 1.0 (21)

Approved direction, November 2, 2026:

- Product: keep a reference visible while using another app.
- Character: direct, quiet, precise.
- World: small reference cards over a working screen.
- Moments: real image, text and timer previews, and saved Library thumbnails.
- Signature: a consistent PiP mark and clearly prioritized Float action.

Retain Cod's name, San Francisco type, existing blue accent, native navigation,
features and section order. Apply the Unslop workflow by Damir Sokolovsky
([@heydamir](https://x.com/heydamir), [Unslop](https://heydamir.design/unslop)),
licensed CC BY 4.0. This is a native SwiftUI adaptation, not a copied web theme.

## Audit and ordered passes

1. Spacing: consolidate 4/8/12/16/20/24-point spacing and 44-point minimum touch
   targets. Remove padding nested inside already padded List rows.
2. Color: keep semantic system surfaces; reserve blue emphasis for Float and
   meaningful setup actions. Preserve content colors and System appearance.
3. Icons: keep SF Symbols in aligned columns with neutral navigation icons.
4. Copy: shorten always-visible guidance; preserve detailed iOS constraints in
   optional explanations and the existing guide.
5. Type: retain native, scalable text styles, regular/medium hierarchy and
   monospaced figures. Keep accessibility sizes supported.
6. Layout: fit short preview cards to their actual aspect, retain the pinned
   preview/Float action, and group Library navigation and filters coherently.
7. Details: use a consistent 12-point action shape and quiet thumbnail badges.
   Preserve confirmations, errors, disabled states and accessibility identifiers.
8. Visuals: use actual user content. No generated art or decorative hero is
   appropriate for a utility whose purpose is to reach PiP quickly.
9. Motion: restrained press feedback, no bounce or looping decoration; respect
   Reduce Motion. Leave native PiP itself under iOS control.

## Verification

Baseline screenshots and three passing existing UI flows:
`/private/tmp/cod-redesign21.598wJ5/baseline.xcresult`.
The nine passes above are implemented. Content colors still belong to the
references themselves, not to navigation chrome. Native system navigation and
its appearance are retained. No image generation was needed.

- All 218 signed unit tests passed on the iPad simulator, with no skips or
  failures (`unit21.xcresult`).
- Eight iPhone UI checks passed in `phone21.xcresult`. The first new largest-text
  check failed in its setup because a lazily loaded Home row started offscreen;
  its helper was corrected to scroll before inspecting the row.
- Three checks passed in `phone21-final.xcresult`: that largest-text case,
  landscape/dark appearance, and installed signed Shortcut cold/warm image input.
  Together these establish passing results for 11 distinct iPhone UI cases.
- Four iPad UI checks passed with no skips: Home/Library/Settings, fitted and
  pinned short-text preview, dark largest-text Timer, and largest-text optional
  introduction (`pad21.xcresult`).
- Populated Library favorites/order/clear-history check passed
  (`library21.xcresult`). This brings the verified UI cases to 12 on iPhone and
  four on iPad, with the initial test-helper failure resolved as described above.
- Signed Cod / Debug device build and signature verification passed. Identity:
  `com.josh.cod.store`, display name Cod Test, build 21 (`device21.log`).
- Cod / Release archive, source guard, artifact scan and whitespace checks passed
  (`archive21.log`, `archive-audit21.log`). The local Release archive is unsigned,
  not distribution/TestFlight validation.

Artifacts are under `/private/tmp/cod-redesign21.598wJ5`. The signed development
app is `DeviceData/Build/Products/Debug-iphoneos/Cod.app`; the unsigned archive is
`Cod21.xcarchive`. No push or submission was performed.
Local verification is complete.

Installed and launched Cod Test 1.0 (21) on Jay (iPhone 16 Pro Max) on November 2,
2026. Apple's device tool confirmed the installed version and successful launch.
Only `com.josh.cod.store` was targeted; the original Cod app and data were left
untouched. Owner review of the redesign and physical feature acceptance remain open.

Actual floating-picture quality, timer alarm timing, physical-device accessibility
and iPad window resizing remain manual release gates. The simulator checks
establish layout and handoff behavior, not successful visible native PiP.

## Screenshots

Unmodified simulator captures:

- [iPhone Home](screenshots/redesign-21/home.png)
- [Text and fitted preview](screenshots/redesign-21/text.png)
- [Library](screenshots/redesign-21/library.png)
- [Library with favorites and recent history](screenshots/redesign-21/library-populated.png)
- [Settings](screenshots/redesign-21/settings.png)
- [iPad dark Timer at the largest text size](screenshots/redesign-21/ipad-dark-large-text.png)

Only documented Apple APIs are permitted. The Share extension must not launch
Cod directly. The original phone installation is untouched; development testing
uses `com.josh.cod.store`. Privacy/support hosting remains owner-deferred, and
no App Review approval is claimed.
