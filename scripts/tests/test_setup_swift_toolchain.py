from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

import setup_swift_toolchain as toolchain

TRUSTED = "52BB7E3DE28A71BE22EC05FFEF80A866B47A981F"


class SwiftToolchainTests(unittest.TestCase):
    def test_latest_picks_the_highest_release_numerically(self) -> None:
        releases = [{"name": "6.0.3"}, {"name": "6.10"}, {"name": "6.4.1"}, {"name": "6.9.2"}]
        self.assertEqual(toolchain.resolve_version("latest", releases), "6.10")

    def test_exact_versions_pass_through_and_others_are_rejected(self) -> None:
        self.assertEqual(toolchain.resolve_version("6.0.3"), "6.0.3")
        self.assertEqual(toolchain.resolve_version("6.1"), "6.1")
        for invalid in ("6", "6.x", "main", "6.0.3; rm -rf /"):
            with self.assertRaises(toolchain.ToolchainError):
                toolchain.resolve_version(invalid)

    def test_download_urls_match_swift_org_layout(self) -> None:
        self.assertEqual(
            toolchain.toolchain_url("6.0.3", "ubuntu2404", "ubuntu24.04", "x86_64"),
            "https://download.swift.org/swift-6.0.3-release/ubuntu2404/swift-6.0.3-RELEASE/"
            "swift-6.0.3-RELEASE-ubuntu24.04.tar.gz",
        )
        self.assertEqual(
            toolchain.toolchain_url("6.4.1", "ubuntu2404", "ubuntu24.04", "aarch64"),
            "https://download.swift.org/swift-6.4.1-release/ubuntu2404-aarch64/"
            "swift-6.4.1-RELEASE/swift-6.4.1-RELEASE-ubuntu24.04-aarch64.tar.gz",
        )

    def test_fingerprint_requires_a_good_and_valid_signature(self) -> None:
        valid = (
            "[GNUPG:] GOODSIG EF80A866B47A981F Swift 6.x Release Signing Key\n"
            f"[GNUPG:] VALIDSIG SUBKEY 2024-10-01 1727740800 0 4 0 1 10 00 {TRUSTED}\n"
        )
        self.assertEqual(toolchain.signing_fingerprint(valid), TRUSTED)
        self.assertIsNone(toolchain.signing_fingerprint(valid.splitlines()[1]))
        self.assertIsNone(toolchain.signing_fingerprint("[GNUPG:] BADSIG EF80A866B47A981F x\n"))

    def test_the_pinned_key_is_the_swift_6_release_key(self) -> None:
        self.assertEqual(toolchain.TRUSTED_FINGERPRINTS, frozenset({TRUSTED}))

    @unittest.skipIf(shutil.which("gpg") is None, "gpg is not installed")
    def test_a_valid_signature_from_an_unpinned_key_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            home = root / "gnupg"
            home.mkdir(mode=0o700)
            env = {**os.environ, "GNUPGHOME": str(home)}

            def gpg(*arguments: str) -> bytes:
                return subprocess.run(
                    ["gpg", "--batch", "--pinentry-mode", "loopback", "--passphrase", "", *arguments],
                    env=env,
                    check=True,
                    capture_output=True,
                ).stdout

            gpg("--quick-gen-key", "Untrusted Test <test@example.invalid>", "ed25519", "sign", "never")
            archive = root / "swift.tar.gz"
            archive.write_bytes(b"not really a toolchain")
            signature = root / "swift.tar.gz.sig"
            gpg("--detach-sign", "--output", str(signature), str(archive))
            keys = gpg("--armor", "--export")

            with self.assertRaisesRegex(toolchain.ToolchainError, "untrusted key"):
                toolchain.verify_signature(archive, signature, keys)

            archive.write_bytes(b"tampered")
            with self.assertRaisesRegex(toolchain.ToolchainError, "invalid signature"):
                toolchain.verify_signature(archive, signature, keys)


    @unittest.skipIf(shutil.which("gpg") is None, "gpg is not installed")
    def test_the_vendored_key_file_holds_only_the_pinned_key(self) -> None:
        with tempfile.TemporaryDirectory() as home:
            listing = subprocess.run(
                ["gpg", "--batch", "--with-colons", "--import-options", "show-only", "--import"],
                input=toolchain.KEYS_FILE.read_text(encoding="ascii"),
                env={**os.environ, "GNUPGHOME": home},
                check=True,
                capture_output=True,
                text=True,
            ).stdout
        primaries = []
        lines = listing.splitlines()
        for index, line in enumerate(lines):
            if line.startswith("pub:"):
                primaries.append(lines[index + 1].split(":")[9])
        self.assertEqual(set(primaries), toolchain.TRUSTED_FINGERPRINTS)

if __name__ == "__main__":
    unittest.main()
