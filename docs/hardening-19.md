# Cod Test 1.0 (19) — bounded reliability/performance audit

Completed October 29, 2026. No phone installation, GitHub push or App Store
submission was performed. Build 17 remains the last installed phone version.
Artifacts: `/private/tmp/cod-hardening19.GOEcHT`; DerivedData reuses build 18 paths.

## Findings and changes

- Missing Library thumbnails previously fell back to decoding the full original.
  The fallback now decodes at 400 pixels and leaves the stored original unchanged.
- Image imports advertised 50 MB but went through a Share-extension decoder with
  a 32 MB ceiling. Reference decoding now consistently allows 50 MB, checks finite
  dimensions, honors orientation, and bounds output to 16 megapixels, 4,096 pixels
  wide and 12,000 high. Owned lossless comparison PNGs have a separate 75 MB encoded
  limit because re-encoding a bounded JPEG can increase file size; reads still
  use the same decoded-pixel budget and require local files.
- PDF scrolling previously retained all source rasters while allocating the
  playback rasters. It now loads/releases one source page at a time and stops
  loading as soon as the existing 24,000-pixel canvas limit is exceeded.
- A saved-reference editor could recreate a deleted item. Update now requires
  its identifier to remain present. Failed index writes retain previous in-memory
  content and remove the newly created original. Asset references must be valid
  owned UUID PNGs and cannot attach another card's original or target the index.
- Corrupt Library indexes are preserved and edits paused. A reload is offered
  before any destructive reset. Asynchronous storage failures are surfaced in
  Library and a toast, rather than silently implying durable persistence.
  These writes remain asynchronous: a warning is not a new transactional database
  or a guarantee that a new item survived disk failure. Confirm important saves
  after relaunch; originals in Photos/Files are unchanged.
- Explicit Delete Everything can reset damaged saved data and remove recognized
  orphaned payloads. Unknown files/subdirectories and originals aren't swept.
  Clear Recent History still preserves favorites and saved references. UI tests
  clear only disposable simulator data; no phone data was removed.
- Temporary imports, GIF videos and new video crops have scoped owned folders.
  Process-start cleanup removes only recognized UUID video files there, without
  following symlinks. Legacy anonymous crops in the temp root are not guessed at
  or broadly deleted; normal OS temporary-file reclamation still applies.
- Copy failures clean partial owned video destinations. Existing cancellation
  output guards remain; GIF cancellation is cooperative, not a promise that an
  in-progress codec/provider operation stops immediately.
- App and Share-extension diagnostic files use one shared writer. Lines are
  byte-bounded/flattened and each file is capped at
  128 KiB; writes mark the log excluded from backup. No image pixels or recognized
  text are added to logs and no developer upload path was introduced. Favorites
  catalogs/widgets no longer reload for every unchanged non-favorite history edit.
- The full test run exposed an existing end-seek race: a still-running timebase
  could advance past the finite range between repositioning and pausing. Freeze
  it before setting the new position, then resume only if actually playing.

## Verification

- **213/213 unit tests passed** (`units19signedoff.xcresult`): 18 new storage,
  image-budget, cleanup, diagnostic-bound and repeated end-seek checks, plus two
  performance tests, on top of the prior 193. Actual large/rotated image decoding,
  failed writes, damaged-index preservation/reload/reset, missing-thumbnail
  fallback, stale edits, update/relaunch and source-file preservation are covered.
- Initial `units19.xcresult` passed 208 tests. `units19final.xcresult` recorded the
  pre-existing end-seek failure; after the clock fix, `units19verified.xcresult`
  passed 211, `units19complete.xcresult` passed 212, and the final shared-writer
  suite passed 213, including actual file-size and backup-exclusion checks. Failures are retained,
  not relabelled as successful physical playback.
- iPhone `ui19.xcresult` passed GIF picker/import, finite PDF range/playback,
  video crop/reset and signed Share Shortcut delivery. Two older checks needed
  correction: Library expected obsolete counted button text, and the saved-card
  fixture tried deleting text from an undefined cursor position. They now use
  current labels and the actual Clear action.
- `ui19final.xcresult` passed saved-card creation/edit/update/relaunch, finite PDF
  playback and cold/warm signed Share Shortcut delivery. Its old PiP-dependent
  Library fixture was explicitly skipped when native PiP was unavailable.
  `library19.xcresult` then **passed** favorites-above-new-history, Clear Recent
  History preservation and explicit Delete Everything, using two video imports
  whose archival does not require simulator PiP. This is storage acceptance, not
  a workaround claimed to prove native PiP quality.
- Signed Debug and unsigned Release builds passed (`device19signedoff.log`,
  `release19signedoff.log`). Development signature, supported-source, Release
  artifact and whitespace audits passed. Distribution/TestFlight validation and
  App Review remain separate gates.

The shared-logger Share check initially failed in test setup before invoking the
extension: its Settings tab tap left the app on Float. The test now starts an
explicit fresh process and waits for the Settings destination. The corrected
check passed (`share19verified.xcresult`), confirming actual extension preparation
and correct-image receipt after explicit app activation. Final Release/source
audits and development-signature verification passed. Selected saved-card and
Library screenshots were visually inspected. This bounded local pass is complete.

Ready development package:
`/private/tmp/cod-release18.yvrqrB/DeviceData/Build/Products/Debug-iphoneos/Cod.app`
(`com.josh.cod.store`, Cod Test, build 19). It has not been installed on the phone.

## Performance measurements — simulator evidence only

Twelve original vector PDF pages, five samples per implementation in a fresh
test process (`performance19.xcresult`):

| Measurement | Previous eager fixture | Streamed preparation |
| --- | ---: | ---: |
| Average measured peak physical memory | 91.7 MB | 47.2 MB |
| Average preparation time | 45 ms | 43 ms |

These are whole test-process metrics, not just raster storage or a device memory
ceiling. The eager memory readings varied by 13.7%. In the earlier full-suite
run the peaks were 182.6 vs 158.5 MB, and timing was 52 vs 66 ms. Cache state,
simulator load and the test harness change absolute results. The consistent
structural benefit is that all source-page rasters are no longer retained
alongside all output rasters; no universal speed, energy or phone-memory claim
is made. Large-image output bounds and video/GIF size/frame limits are separately
tested/reviewed, not described as a physical-device power profile.

## Remaining boundaries

- Phone PiP picture quality, resizing/restore/early interactions, music mixing,
  delayed alarm sound and real media/lock-screen behavior still need device tests.
- Real provider/cloud downloads, low-storage conditions and assistive-technology
  coverage are not replaced by injected write failures or simulator checks.
- Corrupt indexes aren't reconstructed automatically. User-created originals,
  unknown files and backups aren't erased by a normal save or startup repair.
- Only documented Apple APIs are used. Share-extension launch policy, app/team
  identity, signed Shortcut bindings and approval caveats are unchanged.
