from __future__ import annotations

import stat
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

import setup_dart_toolchain as toolchain

INDEX = {
    "current_release": {"stable": "c3"},
    "releases": [
        {
            "hash": "b1",
            "channel": "beta",
            "version": "3.26.0-0.1.pre",
            "dart_sdk_arch": "x64",
        },
        {
            "hash": "c3",
            "channel": "stable",
            "version": "3.27.1",
            "dart_sdk_arch": "x64",
        },
        {
            "hash": "c3a",
            "channel": "stable",
            "version": "3.27.1",
            "dart_sdk_arch": "arm64",
        },
        {
            "hash": "c2",
            "channel": "stable",
            "version": "3.24.5",
            "dart_sdk_arch": "x64",
        },
        {
            "hash": "c1",
            "channel": "stable",
            "version": "3.24.4",
            "dart_sdk_arch": "x64",
        },
    ],
}


class FlutterReleaseSelectionTests(unittest.TestCase):
    def test_stable_selects_the_current_release_for_the_architecture(self) -> None:
        self.assertEqual(
            toolchain.select_flutter_release(INDEX, "stable", "x64")["hash"], "c3"
        )

    def test_minor_wildcard_selects_the_newest_patch(self) -> None:
        self.assertEqual(
            toolchain.select_flutter_release(INDEX, "3.24.x", "x64")["hash"], "c2"
        )

    def test_exact_version_respects_architecture(self) -> None:
        self.assertEqual(
            toolchain.select_flutter_release(INDEX, "3.27.1", "arm64")["hash"], "c3a"
        )

    def test_unknown_or_invalid_versions_fail(self) -> None:
        with self.assertRaisesRegex(
            toolchain.ToolchainError, "no stable Flutter release"
        ):
            toolchain.select_flutter_release(INDEX, "3.24.x", "arm64")
        with self.assertRaisesRegex(toolchain.ToolchainError, "must be"):
            toolchain.select_flutter_release(INDEX, "latest", "x64")


class ChecksumTests(unittest.TestCase):
    def test_sha256sum_file_is_parsed(self) -> None:
        digest = "8d0c5e34f2a9d6b9f5ebf05252ae1703893f6087d547c631b390aef2d0cd6967"
        self.assertEqual(
            toolchain.parse_sha256sum(
                f"{digest.upper()} *dartsdk-linux-x64-release.zip\n"
            ),
            digest,
        )

    def test_malformed_checksum_is_rejected(self) -> None:
        with self.assertRaises(toolchain.ToolchainError):
            toolchain.parse_sha256sum("not-a-digest file.zip")
        with self.assertRaises(toolchain.ToolchainError):
            toolchain.parse_sha256sum("")

    def test_dart_version_must_be_exact_or_stable(self) -> None:
        self.assertEqual(toolchain.resolve_dart_version("3.5.4"), "3.5.4")
        with self.assertRaises(toolchain.ToolchainError):
            toolchain.resolve_dart_version("3.5")


class ZipExtractionTests(unittest.TestCase):
    def _zip(self, directory: Path, members: dict[str, int]) -> Path:
        archive = directory / "sdk.zip"
        with zipfile.ZipFile(archive, "w") as bundle:
            for name, mode in members.items():
                info = zipfile.ZipInfo(name)
                info.external_attr = (stat.S_IFREG | mode) << 16
                bundle.writestr(info, b"#!/bin/sh\n")
        return archive

    @unittest.skipIf(sys.platform == "win32", "POSIX permissions")
    def test_executable_bits_are_preserved(self) -> None:
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            archive = self._zip(
                root, {"dart-sdk/bin/dart": 0o755, "dart-sdk/README": 0o644}
            )
            toolchain._extract_zip(archive, root / "out")
            self.assertTrue(
                (root / "out/dart-sdk/bin/dart").stat().st_mode & stat.S_IXUSR
            )
            self.assertFalse(
                (root / "out/dart-sdk/README").stat().st_mode & stat.S_IXUSR
            )

    def test_path_traversal_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            archive = self._zip(root, {"../escape": 0o644})
            with self.assertRaisesRegex(
                toolchain.ToolchainError, "escapes destination"
            ):
                toolchain._extract_zip(archive, root / "out")
            self.assertFalse((root / "escape").exists())


if __name__ == "__main__":
    unittest.main()
