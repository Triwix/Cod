# Cod Test 1.0 (18) — independent release polish

## Changes

- First-run Float shows a skippable introduction card, not a blocking modal.
  The user-opened tour explains media/text/tools, the preconfigured Share Shortcut,
  why Share → Cod needs a notification tap or manual open, and optional system
  controls via the full guide. Start Floating, Skip and Not now persist locally.
  Settings can replay it. No permission requests or Shortcut installation happen
  merely by reading/skipping the introduction. It doesn't claim setup is installed.
- Photos no longer silently ignores a nil transfer result. A common decoder
  distinguishes unavailable, unreadable and oversized images. Text's photo import
  uses the same errors instead of reporting an unrelated PDF/scroll-range error.
- Home shows loading/cancel feedback and an import error until dismissed or a new
  selection starts. Cancelling Files is not a failure. Loading tasks are owned by
  their selections; identity guards prevent old/cancelled results from replacing
  newer ones. Cancellation is cooperative: providers/encoders may finish work
  internally, but their late output isn't presented.
- Direct document-open work checks cancellation and the latest explicit input;
  newer documents, Shortcuts or user input win. Source files aren't deleted or
  edited. Existing five-minute Share expiry/retry behavior is unchanged.
- Color-selector rows have at least 44-point touch targets. The editable text
  field explains its placeholder/preview behavior to assistive technology.
  Removed the unreferenced Home `actionRow` helper; retained compatibility readers
  and legacy drafts, rather than deleting user-data migration paths.
- Refined listing copy and added concise reviewer notes plus a separate
  [screenshot/owner-handoff plan](submission-package-18.md). Updated privacy wording
  for the local introduction flag and unified text draft. No account answers,
  enrollment, publication, purchase or upload has been performed.

## Verification

Artifacts: `/private/tmp/cod-release18.yvrqrB`. Simulator tests change only their
disposable preferences/data. Original Cod and the phone's installed build 17
are untouched; build 18 has not been installed on the phone.

- Initial unit suite: **193 passed**, including 11 new setup/import tests
  (`units18.xcresult`). Checks cover retained preferences, stale/cancelled imports,
  recoverable errors, nil/corrupt/oversized images, unsupported files/directories,
  corrupt PDFs, invalid video-copy cleanup and subsequent valid import.
- iPhone checks passed for PDF toggle/crop visibility, photo import and bitmap
  scrolling, Files-picker cancellation and the existing setup installer
  (`ui18.xcresult`, individual results). That initial bundle also records failures:
  the new welcome container overrode its children's accessibility identifiers,
  and an older text test assumed the persisted Teleprompter mode was off. The
  container identifier was removed and the test now explicitly selects still text.
- iPad PDF and landscape/dark checks passed (`ipad18.xcresult`, individual results).
  Corrected normal/maximum-text introduction, Skip/relaunch and Settings replay
  checks passed (`ipad18intro.xcresult`). Selected screenshots were inspected.
- Final signed Debug and unsigned Release builds passed (`device18final.log`,
  `release18final.log`). Source and Release artifact audits passed, including
  exclusion of the new debug-only introduction test flag. This isn't a signed
  distribution/archive validation or a promise of App Review acceptance.

- Final iPhone suite: **7/7 passed** (`ui18final.xcresult`): largest-text editor
  with keyboard, supported Share/manual activation, Files cancellation, corrupt
  PDF followed by valid-document recovery, normal/maximum-text introduction,
  Skip/relaunch/Settings replay and signed Share Shortcut cold/warm image delivery.
  PDF/photo/setup tests that passed in the initial bundle remain recorded above.
- Final-source unit suite: **193/193 passed** on iPad (`units18final.xcresult`),
  in addition to the iPhone run. The final signature, source/Release artifact
  checks and whitespace check passed. Selected normal/large-text phone screenshots
  and iPad PDF/landscape screenshots were visually inspected. Local verification
  is complete; physical-device acceptance and distribution validation are not.

Ready-to-install development app:
`/private/tmp/cod-release18.yvrqrB/DeviceData/Build/Products/Debug-iphoneos/Cod.app`
(`com.josh.cod.store`, Cod Test, build 18). Installation was not attempted in this
independent simulator pass. The original Cod app and phone data remain untouched.

## Remaining acceptance

Actual PiP picture quality, sound/repeat/lock-screen behavior, delayed alarm sound,
real cloud-provider cancellation/permission recovery, full assistive-technology
coverage and iPad window-resizing remain separate checks. No simulator control
or black PiP frame is counted as physical-device playback acceptance.
