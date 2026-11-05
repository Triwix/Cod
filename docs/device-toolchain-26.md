# Build 26 phone check and test toolchain

November 4, 2026. App code remains build 26 (`84e3227`).

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

## Verified toolchain compatibility issue

The [latest external audit](https://cod-launch-b13d0b.sites.tab.bot/) reports no
new code issues and confirms the build-26 drag fix at the source level. It
suggests a toolchain mismatch behind the remaining test-service failure.

Read-only local checks confirm:

- macOS **27.2**, build **26B123**, Apple silicon.
- Selected Xcode **26.6**, build **17F113**, at `/Applications/Xcode.app`.
- Normal GUI launch still reports `kLSIncompatibleApplicationVersionErr`.

Apple's [SDK and system requirements](https://developer.apple.com/xcode/system-requirements)
list Xcode 26.6 for **macOS 26.2–26.x**. This Mac is outside that supported
range. The same table lists stable **Xcode 27.2** for macOS 26.6 or later, with
Swift 5 language mode and iOS 17+ simulator support. That is the appropriate
supported toolchain to try next; a beta is unnecessary for this task.

The unsupported combination is confirmed. Its being the sole cause of the
DTServiceHub/lockdown test failure is still an inference, and must be verified by
rerunning the unit and affected UI suites after moving to a supported Xcode.
No Xcode update has been installed in this pass. App sources/build number,
permissions and signing identity are unchanged.

The current development profile expires **November 4 at 10:33 PM Pacific**;
refresh provisioning before testing/installing after expiry. This development
limit is separate from the owner-deferred distribution-signing and publishing
requirements in the [MVP checklist](../MVP_CHECKLIST.md).
