# Verifier and temporary rendering · 1.0 (23)

November 3, 2026. Branch: `codex/verifier-rendering-23`.
At the owner's subsequent request, Cod Test 1.0 (23) was installed and launched
on Jay (iPhone 16 Pro Max) on November 3. Apple's device tool confirmed both the
installed version and successful launch. Only `com.josh.cod.store` was targeted;
the original Cod app/data, supported entry points and permissions are unchanged.
This confirms installation/launch, not physical feature acceptance. Candidate 23
is not submission-ready while the test/release gates remain open.

## Verifier

`verify-store-build.sh` now uses stock macOS tools with absolute paths. It no
longer needs ripgrep. Each pattern search distinguishes a match, no match and
an actual scan error; errors abort the audit. Main executables are mandatory,
optional debug dylibs are inspected when present, and malformed/empty binaries
are rejected. Mach-O inspection is checked independently before its output is
parsed, so a failed upstream command cannot look like an absent framework.
The separate source guard still uses ripgrep, but now requires it up front and
rejects scan errors rather than reporting a clean source tree on failure.

Patterns are searched directly in byte-oriented binary input. Apple `strings`
can skip data outside its recognized Mach-O sections; the regression fixtures
exercise markers appended to a disposable executable as well as both extensions
and the optional debug binary. All temporary audit files are cleaned up.

The previous report's claim that missing ripgrep allowed an overall successful
audit was overstated: its later intent-metadata check already failed. This pass
removes the dependency and closes the individual failed-scan/absent-match ambiguity.
The guard still checks only known implementation markers and configuration;
passing it is not an App Review, distribution-signing or hosted-policy validation.

## Temporary images

- PiP gets a single render at its final bounded size, using the standard color
  range and even dimensions required by H.264. This replaces the sequence of
  orientation redraw, resize and possible even-size redraw. Only this disposable
  frame uses the narrower range. Transparency is explicitly composited on black
  for the opaque video; the source image/alpha aren't modified.
- Library thumbnail rendering explicitly requests the standard range, including
  source images already smaller than 400 pixels. General normalization, cropping
  and default resize behavior retain their existing color policy. Photos/Files
  originals are never rewritten.
- This limits the temporary output format and intermediate allocations; it
  doesn't establish measured peak-memory savings or remove every wide-color
  buffer in the import/crop pipeline. Synchronous drawing already in progress
  still cannot be interrupted halfway through.

Apple documents that the [standard range](https://developer.apple.com/documentation/uikit/uigraphicsimagerendererformat/range/standard)
may lose extended-color information. It is intentional for the temporary SDR
video/thumbnail output and is not applied globally to original normalization.

## Verification

Artifacts: `/private/tmp/cod-release23.wu0z964i`.

- Fourteen host-side audit regression tests pass, with no skips. The suite uses
  disposable copies of the real Release app and a stock macOS PATH, without
  modifying the supplied app. It covers all forbidden-marker families, both
  extensions, optional debug code, missing/empty/malformed executables, metadata
  read failures, invalid configuration and the still-required hosted-policy gate.
  Three cases cover the source guard's normal run, absent tool and input error.
  Run: `python3 Tools/test-verify-store-build.py /absolute/path/Cod.app -v`.
- Cod / Debug simulator and unit-test bundle compilation passed. Six focused
  rendering tests were added for extended-color precision, source preservation,
  dimensions, small/thin images, invalid limits and alpha. XCTest execution
  again failed before the first case with the known Apple test-service error.
  These six tests and the earlier build-22 tests are not counted as passed.
- Signed Cod / Debug device build and deep/strict signature verification passed
  (`device23.log`). Cod / Release device
  archive passed (`archive23.log`); this is an unsigned local archive, not
  distribution/TestFlight validation.
- The hardened verifier passes on the candidate-23 Release app using only stock
  PATH tools (`archive-audit23.log`). Supported-source and whitespace checks pass.

The Xcode/macOS compatibility and test-service failures documented in
[build 22](release-hardening-22.md) remain unresolved. Complete the unit suite,
affected UI flows and physical image/rotation/transparency acceptance before
calling this candidate validated. Privacy/support hosting and distribution
signing remain owner/release gates in the [MVP checklist](../MVP_CHECKLIST.md).
