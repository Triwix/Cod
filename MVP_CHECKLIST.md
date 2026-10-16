# Image-floating MVP reliability

October 15 fast-share candidate: [FAST_SHARE.md](FAST_SHARE.md). The product
acceptance target remains Share → Cod → PiP, not the manual-open fallback.
Fast launch is separated from private source-app return and PiP control hiding;
physical acceptance and review eligibility are distinct, unfinished checks.

App Store transition is tracked separately in [APP_STORE_RELEASE.md](APP_STORE_RELEASE.md).
The default **Cod** scheme now tests a public-API automatic-receipt/manual-open
fallback, not the desired one-tap native Share → PiP workflow. See
[fast-launch tests](FAST_LAUNCH_TESTS.md). It does not need Save/Done/inbox Float.
the earlier source-aware flow below is retained only in **Cod Personal**.
These earlier physical confirmations do not certify the new store workflow.

Updated October 6, 2026. Research build: `return-context-research-20261006`;
clean build: `return-research-complete-20261006`.
Videos remain deferred; this checklist covers still-image floating only.

## Verified so far

- The user confirmed Photos → Share → Cod → Float shows the image and returns
  correctly. Logs recorded both a new window and an in-place replacement.
- The user confirmed the screenshot-preview exception fixes the black
  "Screenshots" screen. Later logs explicitly show PiP starting before Cod
  returns directly to Home, without activating ScreenshotServicesService.
- Messages sharing reached PiP in ~1.2 seconds and dispatched Messages
  activation. Logs establish that pipeline, not the exact visual return screen.
- Earlier simulator UI checks established crop-default and One tap float modes
  and preference persistence across the separate app/extension processes.
- The reliability sweep passed 43 automated tests, with no failures or skips.
  It also built and installed on the paired iPhone. Phone checks below still
  need repeating on this build.
- The unsigned device Release configuration also builds successfully, with
  debug-only return experiments excluded. This is a compile check, not a
  distribution/signing or App Store acceptance check.
- The user confirmed all three requested checks on the reliability build:
  cropped-photo floating, replacing the image in an active PiP window, and
  closing PiP then floating again, with no issues.
- The user also confirmed One tap float on/off behavior and at least one minute
  of floating while music keeps playing. PiP/Spotify screenshot return and early
  tap behavior remain separate issues, not covered by these passing checks.

## Early-tap and screenshot-origin follow-up

Device logs at 21:33:11 showed PiP did start, then iOS requested interface
restoration and began stopping it. At 21:33:12 Cod still activated Photos from
its delayed automatic return. This is evidence of a restoration/navigation race,
not a failed initial PiP start. Apple's
[restoration callback documentation](https://developer.apple.com/documentation/avkit/avpictureinpicturecontrollerdelegate/pictureinpicturecontroller(_:restoreuserinterfaceforpictureinpicturestopwithcompletionhandler:))
describes this as restoring the app UI before PiP stops.

The follow-up cancels automatic return and start retries on restoration/stop,
preserves the image in the crop UI, ignores a late start/failure after restoration,
and makes explicit Open Cod override delayed navigation. Restoring selection
bypasses Instant Float so it cannot automatically reopen PiP in a loop. iOS's
native restore gesture can still close PiP; it should no longer trigger a second
app switch or discard the image. Single-tap versus double-tap/button behavior
still needs clarification and physical verification.

The Spotify screenshot shares exposed only `com.apple.ScreenshotServicesService`.
The Home fallback therefore behaved as implemented; returning to the app under
the preview remains unresolved. Inspected
[screenshot environment runtime headers](https://raw.githubusercontent.com/qingralf/iOS26-Runtime-Headers/master/PrivateFrameworks/ScreenshotServices.framework/SSEnvironmentDescription.h)
contain `currentApplicationBundleID`, but the published
[screenshot image-sharing implementation](https://github.com/EthanArbuckle/iPhone18-3_26.1_23B85_Restore/blob/main/Applications/ScreenshotServicesService.app/SSSScreenshotItemProviderImage.mm)
does not establish that this environment is forwarded to Cod.

Cod now performs a bounded check for that exact environment object in the
current share's item/provider metadata. It logs only metadata class names when
missing, not content, titles or URLs. It never assumes Spotify, reuses a previous
Photos source, queries global foreground apps or reopens the temporary service.
Absent reliable metadata, the safe Home fallback remains. The physical test
at 21:52:55 found no screenshot environment in the inspected share metadata;
only the temporary service was identified. This approach did not recover
Spotify, and the user reported that neither symptom changed.

The follow-up passed all 50 simulator tests and built for device. The physical
test at 21:52:22 still produced a native restore/stop request after PiP started.
No competing automatic activation appeared after that restoration, but native
PiP closure was still unresolved in that build. Controls were still in hidden
style `2`, prompting an A/B test with Open without controls disabled. The
automated race-policy tests alone did not fix the user's tap issue.

The user then confirmed that disabling Open without controls fixes early
tapping. Native controls are now the default for fresh preferences, with an
explicit warning on the experimental hiding option. Existing preferences are
preserved; this phone already has the safer setting disabled by the user.
Screenshot-preview return to Spotify still fails and is not claimed fixed.
The safer-default update passed all 51 simulator tests and the device build.
It was not immediately reinstalled because the user's setting already selected
native controls; it is included in the later research and clean installations.
The inspected screenshot-service implementation routes share completion and
preview dismissal through its own controllers, not a return token provided to
Cod. No new screenshot-routing change is being shipped without a reliable
original-app identity or a verified system return action.

The next research sweep tested the foreground-app query in the simulator,
the phone app, and twice in a screenshot-hosted share extension: every query
returned nil. The phone PNG had no explicit application-ID field, and a
read-only observer found no delayed Back-to token during the tested warm
screenshot-share launch. Published authentication code is consistent with
the query being restricted to system clients. Modern Back-to uses the same
missing navigation token, not an independent mechanism. No privileged access
was attempted. See [the research report](RETURN_RESEARCH.md) for observations,
limits and primary sources. Universal screenshot-origin return is unresolved.
The clean build passed all 52 simulator tests with no failures or skips and
was installed after removing the temporary automatic share probes. Its
unsigned Release build also passed, with explicit diagnostics excluded.

## Hardening in this sweep

- Delayed start/failure/stop/restore callbacks only affect the currently owned
  PiP controller. Old eligibility and foreground notifications are ignored.
- Readiness waits have independent ownership, immediate cancellation, one-shot
  completion, and a bounded timeout. Old waits cannot clear newer observations.
- A new float cancels old retry/timeout/foreground monitoring. Teardown clears
  the old background timestamp so it cannot mislabel a later window closure.
- Corrupt image handoffs are consumed once, preserving unrelated clipboard
  representations. Tests use disposable, named pasteboards, not the Mac clipboard.
- Very narrow/tall images retain at least one pixel when downsampled.
- Encoding checks frame-append failures and removes partial clips on error.
  Tests decode actual generated H.264 frames, check image color and dimensions,
  and verify odd dimensions become even.
- Share imports time out after 20 seconds with Retry available. Late callbacks
  cannot overwrite a retried or dismissed session. Responder traversal is bounded.
- The early-close message describes an observation, not a proven audio failure.

## Physical acceptance checks

The automated tests cannot establish actual PiP visibility, controls, duration,
source-screen restoration, music mixing, or interactions with another app's PiP.
The simulator's native screen-control service was unavailable during this sweep;
no new simulator UI pass is claimed.

- [x] Crop mode: share a photo, choose a small region, Float; user reported no issues.
- [ ] Cancel a separate crop without floating.
- [x] One tap float: enable it, share a photo, verify no crop menu; disable it
  afterward and verify the menu returns.
- [ ] One tap float setting survives a physical-device app restart.
- [x] Share another photo while PiP is active: the existing window updates,
  without gray frames, a second window, or an unexpected destination.
- [x] Close PiP, then float again; user reported no issues.
- [ ] Repeat several times, including a first float after Cod has been fully
  closed and reopened.
- [ ] Immediate screenshot preview: float successfully and land on Home, never
  a black Screenshots app. Saved screenshot shared from Photos returns to Photos.
- [ ] Other sources: Messages, Safari image sharing, Files image sharing.
  Confirm image and destination visually, including cropped/one-tap variants.
- [ ] Portrait/landscape, rotated JPEG/HEIC, transparent PNG, large camera photo,
  and very thin image; native PiP movement and all available resize positions.
- [ ] PiP restore, dismissal, app switching, rotation and lock/unlock; no false
  error message or automatic reopening after the user closes it.
- [x] Float with music playing: verify music continues and the window remains
  visible for at least one minute with the mixing setting enabled.
- [ ] Another app already owns PiP: verify successful takeover or understandable
  failure, recovery and no silent image loss.
- [ ] Shortcut whole-image / latest-screenshot actions on cold and warm launch.
  Arbitrary Shortcut-origin exact-screen return is not yet solved.
- [ ] Permission-denied screenshot capture and slow/cloud-only import offer
  useful errors/retry. The new share-import timeout needs an integration check.
- [ ] Tap Open Cod while floating is preparing: check whether automatic return
  later interrupts the user's deliberate decision to stay in the app.

## Next release work

- Complete the physical acceptance checks before calling this a stable MVP.
- Refresh onboarding/documentation around the share-first workflow and known
  fallback behavior. Preserve optional Shortcuts; do not require their setup.
- A core-flow source checkpoint is saved locally as
  `.checkpoints/image-float-core-20261006.tar.gz`. It preserves current source,
  project configuration, tests and documentation without committing, staging or
  discarding existing repository changes. This is not full MVP acceptance;
  save the final stable checkpoint after the remaining physical checks pass.
- Clarify distribution: current share launching and source-app return rely on
  unsupported/private behavior for personal sideloading, not an App Store-ready
  architecture. New iOS versions can require revalidation.
- Floating videos remains a separate, unimplemented backlog item.
