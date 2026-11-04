#!/usr/bin/env python3
"""Exercise the read-only verifier against disposable copies of a Release app.

Usage: python3 Tools/test-verify-store-build.py /absolute/path/Cod.app
No signing, installation, downloads or changes to the supplied app occur.
"""
import argparse
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest


class StoreVerifierTests(unittest.TestCase):
    source_app: Path
    verifier = Path(__file__).resolve().with_name("verify-store-build.sh")

    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="cod-verifier-test-")
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.app = self.directory / "Cod.app"
        shutil.copytree(self.source_app, self.app, symlinks=True)

    def binary(self, bundle=None):
        bundle = bundle or self.app
        info = plistlib.loads((bundle / "Info.plist").read_bytes())
        return bundle / info["CFBundleExecutable"]

    def audit(self, *options):
        environment = os.environ.copy()
        environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["TMPDIR"] = str(self.directory) + "/"
        result = subprocess.run(
            ["/bin/zsh", "-f", str(self.verifier), str(self.app), *options],
            capture_output=True, text=True, timeout=30, env=environment,
        )
        self.assertEqual(list(self.directory.glob("cod-store-audit.*")), [], "Audit scratch files must be removed")
        return result.returncode, result.stdout + result.stderr

    def assert_rejected(self, expected=None, *options):
        code, output = self.audit(*options)
        self.assertNotEqual(code, 0, output)
        self.assertNotIn("Local checks passed.", output)
        if expected:
            self.assertIn(expected, output)

    def test_valid_release_passes_with_stock_mac_path(self):
        code, output = self.audit()
        self.assertEqual(code, 0, output)
        for identifier in ["com.josh.cod.store:", "com.josh.cod.store.share:", "com.josh.cod.store.controls:"]:
            self.assertIn(identifier, output)

    def test_each_forbidden_marker_family_is_rejected(self):
        binary = self.binary()
        original = binary.read_bytes()
        markers = {
            b"LSApplicationWorkspace": "Removed implementation",
            b"FloatPendingWithCodIntent": "launch-probe code",
            b"SimulatorQATraits": "Debug-only UI testing code",
            b"FastShareAppLauncher": "Fast-share workaround",
            b"cod-diagnostics.log": "Debug diagnostic logging",
        }
        for marker, message in markers.items():
            with self.subTest(marker=marker):
                binary.write_bytes(original + b"\n" + marker + b"\n")
                self.assert_rejected(message)
        binary.write_bytes(original)

    def test_extension_binaries_are_scanned(self):
        for extension in ["CodShare.appex", "CodControls.appex"]:
            with self.subTest(extension=extension):
                binary = self.binary(self.app / "PlugIns" / extension)
                original = binary.read_bytes()
                binary.write_bytes(original + b"\n[CodShare]\n")
                self.assert_rejected("Debug diagnostic logging")
                binary.write_bytes(original)

    def test_missing_executable_is_not_skipped(self):
        self.binary().unlink()
        self.assert_rejected("Missing or unreadable executable")

    def test_empty_executable_is_not_skipped(self):
        self.binary().write_bytes(b"")
        self.assert_rejected("Missing or unreadable executable")

    def test_non_macho_executable_is_rejected(self):
        self.binary().write_bytes(b"This is not an executable.\n")
        self.assert_rejected()

    def test_optional_debug_binary_is_scanned(self):
        binary = self.binary()
        debug = binary.with_name(binary.name + ".debug.dylib")
        debug.write_bytes(binary.read_bytes() + b"\n[CodPiP]\n")
        self.assert_rejected("Debug diagnostic logging")

    def test_metadata_directory_is_not_accepted_as_a_file(self):
        metadata = self.app / "Metadata.appintents" / "extract.actionsdata"
        metadata.unlink()
        metadata.mkdir()
        self.assert_rejected("Saved-reference intent metadata is missing")

    def test_search_read_error_is_not_treated_as_no_match(self):
        if os.geteuid() == 0:
            self.skipTest("Root can read files regardless of their mode")
        metadata = self.app / "Metadata.appintents" / "extract.actionsdata"
        metadata.chmod(0)
        self.addCleanup(lambda: metadata.chmod(0o600))
        self.assert_rejected("Couldn't search audit input")

    def test_unknown_bundle_is_rejected(self):
        info_path = self.app / "Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        info["CFBundleIdentifier"] = "example.invalid.fixture"
        info_path.write_bytes(plistlib.dumps(info))
        self.assert_rejected("Not the store configuration")

    def test_submission_still_requires_a_hosted_policy(self):
        info_path = self.app / "Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        info["CFBundleDisplayName"] = "Cod"
        info["CodPrivacyPolicyURL"] = ""
        info_path.write_bytes(plistlib.dumps(info))
        self.assert_rejected("A real hosted HTTPS privacy policy", "--submission")

    def test_encryption_declaration_must_be_explicit(self):
        path = self.app / "Info.plist"
        original = plistlib.loads(path.read_bytes())
        for value in [None, True]:
            info = dict(original)
            if value is None:
                info.pop("ITSAppUsesNonExemptEncryption", None)
            else:
                info["ITSAppUsesNonExemptEncryption"] = value
            path.write_bytes(plistlib.dumps(info))
            self.assert_rejected()

    def test_source_guard_rejects_short_markers_that_swift_may_inline(self):
        root = self.directory / "Source"
        tools = root / "Tools"
        tools.mkdir(parents=True)
        guard = tools / "verify-supported-source.sh"
        shutil.copyfile(self.verifier.with_name(guard.name), guard)
        for name in ["Cod", "CodShare", "CodControls", "CodTests", "CodLaunchUITests", "Cod.xcodeproj"]:
            (root / name).mkdir()
        (root / "project.yml").write_text("name: Fixture\n")
        fixture = root / "Cod" / "Fixture.swift"
        for marker in ["controlsStyle", "_FBSScene", "BSProcessHandle"]:
            fixture.write_text(f'let value = "{marker}"\n')
            result = subprocess.run(["/bin/zsh", "-f", str(guard)], capture_output=True, text=True, timeout=30)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("unsupported entry point", result.stderr)

    def test_source_guard_also_rejects_a_missing_search_tool(self):
        environment = os.environ.copy()
        environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        result = subprocess.run(["/bin/zsh", "-f", str(self.verifier.with_name("verify-supported-source.sh"))],
            capture_output=True, text=True, timeout=30, env=environment)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Required source-audit tool is unavailable", result.stderr)

    def test_source_guard_accepts_the_current_source(self):
        result = subprocess.run(["/bin/zsh", "-f", str(self.verifier.with_name("verify-supported-source.sh"))],
            capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_source_guard_does_not_ignore_a_scan_error(self):
        root = self.directory / "Source"
        tools = root / "Tools"
        tools.mkdir(parents=True)
        source_guard = tools / "verify-supported-source.sh"
        shutil.copyfile(self.verifier.with_name(source_guard.name), source_guard)
        # Missing CodShare is a real rg input error, not a clean no-match result.
        for directory in ["Cod", "CodControls", "CodTests", "CodLaunchUITests", "Cod.xcodeproj"]:
            (root / directory).mkdir()
        (root / "project.yml").write_text("name: Fixture\n")
        result = subprocess.run(["/bin/zsh", "-f", str(source_guard)],
            capture_output=True, text=True, timeout=30)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("could not read all requested inputs", result.stderr)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    args, remaining = parser.parse_known_args()
    StoreVerifierTests.source_app = args.app.resolve(strict=True)
    unittest.main(argv=[__file__, *remaining])
