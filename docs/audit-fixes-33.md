# Build 33: pre-launch audit fixes

November 13, 2026. These follow up on an outside, read-only audit of commit
04ae644 (build 32). Items that were already tracked are left out: hosting the
privacy policy, App Store Connect setup, phone and sandbox testing, real
screenshots, and the PiP-for-non-video review risk.

## Fixed

- **OCR follows the device's languages.**
  - The default was English only (`["en-US"]`; also item L1 in the Nov 10 audit).
  - It's now the device's preferred languages that Vision can read, up to three (`AppSettings.defaultOCRLanguages`), falling back to English.
  - The script is matched (zh-TW → zh-Hant).
  - The default is recomputed at launch, so it follows a change of device language. A choice made in Settings is kept.
- **"Temperature" is now "Thermal State".**
  - iOS only exposes a thermal state (Cool, Warm, Hot, Very hot), not degrees.
  - The System Monitor switch now reads Thermal State and the window shows "Thermal".
  - The listing and privacy policy say "thermal state" (App Review 2.3).
  - The stored value is unchanged, so saved setups still decode.
- **Speedometer GPS accuracy:**
  - `kCLLocationAccuracyBest` instead of the navigation level, which is meant for a plugged-in device and costs more battery.
  - When In Use only, the background indicator, and stopping on close are unchanged.
- **Reviewer notes:**
  - They now explain the nearly transparent PiP host view.
  - They spell out how the Speedometer uses background location.
- **Code comments:** three comments no longer name other apps.
- **A Swift 6 warning:** `CaptureCoordinator`'s default `ProStore` argument no longer references a main-actor property from a nonisolated context.

## Checked, no change

- **Debug logging:** the `print` calls in `PiPPinController` and the Share extension are inside `#if DEBUG`.
- **Pro gate:** widgets, controls and the saved-reference Shortcut all reach `CaptureCoordinator.floatSavedReference`, which asks for Pro for cards and presets. The Safari extension runs Safari's own player and stays free by design.
- **Safari `<all_urls>`:** already explained in the reviewer notes.

## Left for later

These are owner decisions or post-launch items.

- **App name:**
  - Bundle IDs, the App Group and product IDs are never shown to people, so they can keep "cod" whatever the store name is.
  - Only the App Store name has to be available. Settle it before creating the App Store Connect record, and before re-signing the Shortcuts if the Shortcut names should change.
- **Background location review risk:**
  - Keep the Speedometer and defend it with the reviewer notes, or remove it from 1.0.
- **Lower priority:**
  - Share preferences in the keychain survive reinstall (old L4).
  - The PiP video task's implicit strong capture warning (old L2, harmless with a singleton).
  - Test files are named by sprint.
  - Changelog-style README.
  - A VoiceOver pass on the crop editor.
  - Device power measurements for System Monitor and Speedometer.

## Verification

- **Unit tests:** 289, 0 failures, 3 StoreKit skips on the simulator. `Build33Tests` covers language matching, fallback and persistence, and the thermal label.
- **Release build (unsigned):** `verify-store-build.sh` and `verify-supported-source.sh` pass.
