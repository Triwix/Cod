# Build 26 phone check and test toolchain

November 4–5, 2026. App code remains build 26 (`84e3227`).

## Phone installation and acceptance

The owner found they were still running build 23, which predates the crop
double-tap feature. Cod Test **1.0 (26)** was then installed and launched on
**Jay, iPhone 16 Pro Max**. Apple's device tool confirmed both launch and the
installed version for `com.josh.cod.store`. The original Cod app/data were not
targeted, and this was an update of the existing Cod Test installation.

The owner then confirmed **Crop Photo → draw a box → double-tap inside** floats
the correct crop. This is actual physical-device acceptance of that basic flow,
not just the simulator's unsupported-PiP recovery state.

The separate collapse → release → draw-again check has been requested; its
result is pending. Drag/pinch cancellation, boundary cases, extended PiP
reliability, alarms and old-OS launch remain open until specifically checked.

Local installation receipts:
`/private/tmp/cod26-phone-install.json`,
`/private/tmp/cod26-phone-launch.json`,
`/private/tmp/cod26-phone-installed-app.json`.

## November 4 toolchain diagnosis

The [latest external audit](https://cod-launch-b13d0b.sites.tab.bot/) reports no
new code issues and confirms the build-26 drag fix at the source level. It
suggests a toolchain mismatch behind the remaining test-service failure.

Local checks on November 4 showed:

- macOS **27.2**, build **26B123**, Apple silicon.
- Selected Xcode **26.6**, build **17F113**, at `/Applications/Xcode.app`.
- Normal GUI launch still reports `kLSIncompatibleApplicationVersionErr`.

Apple's [SDK and system requirements](https://developer.apple.com/xcode/system-requirements)
list Xcode 26.6 for **macOS 26.2–26.x**. This Mac is outside that supported
range. The same table lists stable **Xcode 27.2** for macOS 26.6 or later, with
Swift 5 language mode and iOS 17+ simulator support. That is the appropriate
supported toolchain to try next; a beta is unnecessary for this task.

The development profile used for the phone installation expired **November 4
at 10:33 PM Pacific**. Refresh provisioning before the next device install.

## November 5 verification with Xcode 27.2

After the owner installed Xcode, the active toolchain reported **27.2 (27B52)**.
The iOS 26.5 simulator ran both XCTest schemes. The signed iPhone unit run
passed **248 tests**. One test needed to await asynchronous image preparation
before checking that an explicit Float replaces the old crop. Simulator signing
also supplies the App Group and Keychain permissions exercised by the unit suite.

Across the initial runs and focused reruns, **19 iPhone and 5 iPad UI checks**
passed. The final crop run passed both collapse/redraw and double-tap, including
the backdrop tap and the exact 299 × 200 crop saved in Library. The iPhone also
passed both signed Shortcuts, all five notification scenarios, manual Share
handoff and history cancellation. The simulator's document menu used the Share
extension and manual-open fallback. On iPad, PDF opening, page selection and crop,
the Back Tap guide, large text, fast setup and dark landscape passed.

Control Center listed both Cod controls and the screenshot control opened Cod.
The simulator emitted an App Intents enum metadata warning at invocation. The
phone check still needs to verify the screenshot reaches PiP and the saved
reference control runs with a configured reference.

The Release archive, supported-source check, local artifact check and all **16**
verifier tests passed. The archive is unsigned. Submission validation still
requires a hosted privacy-policy URL and distribution signing. Xcode did not
offer the iOS 17.5 or 18.5 simulator downloads, so the older-iOS launch checks
remain open.

Test logs, Xcode result bundles and the unsigned archive are under
`/private/tmp/cod-xcode27.MJF5wE` on the development Mac.
