# Fast image → PiP experiments

**October 15 follow-up:** see [FAST_SHARE.md](FAST_SHARE.md) for the isolated
fast-launch candidate. This document records the October 7 public-only baseline
and its manual-open fallback; it is not the latest candidate's workflow.

October 7, 2026. Product target: native **Share → Cod → PiP**, optional cropping,
no required user-created Shortcut. This target remains unresolved in the
public-API build. The working personal app is separate and was not overwritten.

## Changes in Cod Test

- Separate bundle `com.josh.cod.store`, display name **Cod Test**; original Cod
  stays `com.josh.cod` with its existing installation and data.
- Share extension receives and prepares the latest image automatically and
  dismisses. No Save, Done, inbox selection or extra Float tap.
- Opening the app within five minutes attempts Float automatically. Native
  share → containing-app launch is still a manual step, not a solved behavior.
- Choosing a photo, pasting explicitly, or receiving a genuine image document
  inside the app floats immediately by default. **One tap float** off restores
  the crop-first option. Explicit Crop/Float Shortcuts retain their semantics.
- Durable one-shot request claims, explicit retries, expiry and new-share
  replacement prevent stale-image automatic replay. Old inbox data is preserved.
- ImageIO first limits large file imports to 2048 pixels on the long edge.
  Native UIKit image-object providers now have a bounded fallback. The native
  simulator UIImage share exposed the earlier file-only import bug.
- Public build has no private launch/return, hidden PiP controls, Imgur upload
  or clipboard share transport. The phone Release build excludes launch probes.

## Public launch experiments

Test environment: iPhone 17 simulator, iOS 26.5, Xcode 26.6. A native disposable
test app creates a known 300×200 red/blue image and invokes real system sharing
and document menus. No Mac clipboard or personal photo content is used.

1. **UIDocumentInteractionController Open In menu**: choosing Cod Test invoked
   its Share extension. Cod did not enter the foreground within ten seconds.
   Registering image document types does not guarantee an app-opening share
   item on these source/system surfaces. Other sources may offer genuine direct
   document opening, but Photos/Files support is not claimed from this test.
2. **SwiftUI Button(intent:) inside the Share extension**, with an App Intent
   compiled into app and extension, `openAppWhenRun = true`, iOS 26 foreground
   immediate mode: the button was available and tapped after successful import.
   Cod did not become foreground within eight seconds; the extension stayed
   onscreen. Cod's own logs confirm `perform()` executed **inside the Share
   extension**, not the containing app. System logs separately show metadata/
   donation identity errors for the ad-hoc signature. App and extension
   metadata both contain the intent. This is a failed foreground launch in the
   tested setup, not proof that every valid system intent surface is incapable
   of foregrounding an app.
   The test passing means the button diagnostic executed, not launch success.
   This probe is restricted to **LaunchProbe**, not the phone Release build.
   A follow-up development-certificate signature was accepted by the intent
   service, again ran `perform()` inside the Share extension, and still lacked
   the expected application identity entitlement for donation.
   Reusing the app's own real development identity entitlements then caused a
   simulator process-launch rejection before testing. No valid foreground
   intent execution was established. Further testing needs a properly signed
   physical-device diagnostic; no phone probe is installed in this sweep.
3. **OpenURLIntent with the existing custom scheme**: not shipped or represented
   as a viable experiment; Apple's documentation expressly requires universal
   links and does not support custom URL schemes. A universal-link route needs
   an owned HTTPS domain, association setup and a separately valid invocation
   surface; it does not by itself grant a Share extension foreground-launch rights.

These observations are bounded simulator results, not proof of impossibility on
all devices or future iOS versions. No unsupported technique is relabeled as a
public-API solution. Notifications, domain-based handoff and other system surfaces
are not claimed tested here.

## Automated verification

- Public unit suite: **53 passed**, no failures or skips.
- Preserved personal unit suite: **75 passed**, no failures or skips.
- Signed development Release app/extension build succeeds; matching signed
  App Group entitlement `group.com.josh.cod.store` checked in both bundles.
- Artifact checks pass the phone Release and reject the LaunchProbe artifact,
  including Xcode's separate debug code library. They check known private-code
  strings/resources, not every Apple policy or distribution requirement.
- Native UI acceptance: image-file share and native UIImage-object share both
  reached the correct 300×200 image in Cod without Save/Done/Float buttons.
  **One tap float off** was verified across app/extension processes: cold app
  launch opens cropping, cancellation keeps explicit retry, and restarting the
  app does not replay the cancelled image. Three acceptance scenarios passed
  across the final public-flow and isolated crop runs. These runs cannot show PiP.

Simulator PiP is unsupported. These tests establish receipt/routing/request
safety, not a visible, correctly rendered or long-lived PiP window. Real device
acceptance is still required, including music, replacement, early taps, resizing
and background duration. No automatic source-screen return is promised here.

## Repeating native UI tests

Generate the project from `project.yml`. Build **Cod Launch Tests** for Debug,
with `COD_DISPLAY_NAME='Cod Test'`, using a separate derived-data directory.
Then explicitly install that built `Cod.app` into the target simulator before
running `test-without-building`. The UI runner installs the test harness but
does not install the separately identified Cod app automatically.

For the public intent diagnostic use **Cod Launch Probe**, configuration
**LaunchProbe**, and explicitly install that built Cod app before its UI test.
Afterwards restore the ordinary Debug test app. Do not install the probe on the
phone or submit it. Use the default **Cod** Release build for phone testing.

## Primary references

- [Apple extension launch discussion](https://developer.apple.com/forums/thread/773342)
- [App Intent extension restrictions](https://developer.apple.com/forums/thread/764570)
- [OpenURLIntent: universal links only](https://developer.apple.com/documentation/appintents/openurlintent)
- [Intent runtime behavior](https://developer.apple.com/documentation/appintents/configuring-the-runtime-behavior-of-your-app-intents)
- [Document interaction controller](https://developer.apple.com/documentation/uikit/uidocumentinteractioncontroller)

No App Store submission, upload or publication occurred in this sweep.

## Phone handoff

**Cod Test** (`com.josh.cod.store`, development-signed Release) was installed on
the paired iPhone 12 Pro Max. The installation command succeeded and a filtered
installed-app check confirmed both **Cod Test** and the original **Cod** remain.
The installed build has no LaunchProbe button/code. This does not yet establish
successful real-device PiP.

First checks: **Cod Test → Choose Photo** should float immediately; then a photo
or screenshot's **Share → Cod Test**, followed by opening **Cod Test**, should
float automatically. Turn off **Settings → Share Sheet → One tap float** to
check crop-first behavior. The manual-open limitation is deliberately explicit.
