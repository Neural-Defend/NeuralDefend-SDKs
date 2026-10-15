#!/usr/bin/env python3
"""Install a checksum-verified Dart or Flutter SDK for CI from Google's release archives.

The repository's Actions policy allows only approved third-party actions, so CI installs
the toolchains with this script instead of `dart-lang/setup-dart` or
`subosito/flutter-action`. On GitHub Actions the SDK `bin` directory is appended to
`GITHUB_PATH`.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import stat
import sys
import tarfile
import tempfile
import urllib.request
import zipfile
from pathlib import Path

DART_RELEASES = "https://storage.googleapis.com/dart-archive/channels/stable/release"
FLUTTER_RELEASES = "https://storage.googleapis.com/flutter_infra_release/releases"
EXACT_VERSION = re.compile(r"^\d+\.\d+\.\d+$")
VERSION_PREFIX = re.compile(r"^\d+\.\d+\.x$")


class ToolchainError(RuntimeError):
    pass


def host_os() -> str:
    names = {"Linux": "linux", "Darwin": "macos", "Windows": "windows"}
    try:
        return names[platform.system()]
    except KeyError:
        raise ToolchainError(f"unsupported OS: {platform.system()}") from None


def host_arch() -> str:
    return "arm64" if platform.machine().lower() in {"arm64", "aarch64"} else "x64"


def _fetch(url: str) -> bytes:
    with urllib.request.urlopen(url, timeout=300) as response:
        return response.read()


def parse_sha256sum(text: str) -> str:
    digest = text.strip().split(maxsplit=1)[0].lower() if text.strip() else ""
    if not re.fullmatch(r"[0-9a-f]{64}", digest):
        raise ToolchainError(f"invalid SHA-256 checksum file: {text!r}")
    return digest


def _verify(data: bytes, expected: str, label: str) -> None:
    actual = hashlib.sha256(data).hexdigest()
    if actual != expected:
        raise ToolchainError(f"{label}: SHA-256 {actual} does not match {expected}")


def resolve_dart_version(requested: str) -> str:
    if requested == "stable":
        return str(json.loads(_fetch(f"{DART_RELEASES}/latest/VERSION"))["version"])
    if not EXACT_VERSION.match(requested):
        raise ToolchainError("Dart version must be 'stable' or an exact X.Y.Z version")
    return requested


def select_flutter_release(
    index: dict[str, object], requested: str, arch: str
) -> dict[str, str]:
    """Pick a stable release from a `releases_<os>.json` index.

    `requested` is `stable` (the current stable release), an exact `X.Y.Z`, or `X.Y.x` for
    the newest stable patch of that minor version.
    """
    releases = [
        release
        for release in index["releases"]  # type: ignore[union-attr]
        if release["channel"] == "stable"
        and release.get("dart_sdk_arch", "x64") == arch
    ]
    if requested == "stable":
        current = index["current_release"]["stable"]  # type: ignore[index]
        matches = [release for release in releases if release["hash"] == current]
    elif EXACT_VERSION.match(requested):
        matches = [release for release in releases if release["version"] == requested]
    elif VERSION_PREFIX.match(requested):
        prefix = requested[:-1]
        matches = [
            release for release in releases if release["version"].startswith(prefix)
        ]
    else:
        raise ToolchainError("Flutter version must be 'stable', X.Y.Z, or X.Y.x")
    if not matches:
        raise ToolchainError(
            f"no stable Flutter release matches {requested!r} for {arch}"
        )
    return matches[0]


def _extract_zip(archive: Path, destination: Path) -> None:
    with zipfile.ZipFile(archive) as bundle:
        for member in bundle.infolist():
            target = destination / member.filename
            if not target.resolve().is_relative_to(destination.resolve()):
                raise ToolchainError(
                    f"archive member escapes destination: {member.filename}"
                )
            bundle.extract(member, destination)
            mode = (member.external_attr >> 16) & 0o777
            if mode and not member.is_dir():
                target.chmod(mode | stat.S_IRUSR)


def _extract_tar(archive: Path, destination: Path) -> None:
    with tarfile.open(archive) as bundle:
        if sys.version_info >= (3, 12):
            bundle.extractall(destination, filter="tar")
        else:
            for member in bundle.getmembers():
                target = (destination / member.name).resolve()
                if not target.is_relative_to(destination.resolve()):
                    raise ToolchainError(
                        f"archive member escapes destination: {member.name}"
                    )
            bundle.extractall(destination)


def _download_and_extract(url: str, sha256: str, destination: Path) -> None:
    print(f"downloading {url}", flush=True)
    data = _fetch(url)
    _verify(data, sha256, url)
    destination.mkdir(parents=True, exist_ok=True)
    suffix = ".zip" if url.endswith(".zip") else ".tar.xz"
    with tempfile.TemporaryDirectory() as scratch:
        archive = Path(scratch) / f"sdk{suffix}"
        archive.write_bytes(data)
        if suffix == ".zip":
            _extract_zip(archive, destination)
        else:
            _extract_tar(archive, destination)


def install_dart(requested: str, root: Path) -> Path:
    version = resolve_dart_version(requested)
    name = f"dartsdk-{host_os()}-{host_arch()}-release.zip"
    base = f"{DART_RELEASES}/{version}/sdk/{name}"
    digest = parse_sha256sum(_fetch(f"{base}.sha256sum").decode("utf-8"))
    destination = root / f"dart-{version}"
    _download_and_extract(base, digest, destination)
    print(f"installed Dart {version}", flush=True)
    return destination / "dart-sdk" / "bin"


def install_flutter(requested: str, root: Path) -> Path:
    index = json.loads(_fetch(f"{FLUTTER_RELEASES}/releases_{host_os()}.json"))
    release = select_flutter_release(index, requested, host_arch())
    destination = root / f"flutter-{release['version']}"
    _download_and_extract(
        f"{FLUTTER_RELEASES}/{release['archive']}",
        str(release["sha256"]).lower(),
        destination,
    )
    print(f"installed Flutter {release['version']}", flush=True)
    return destination / "flutter" / "bin"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--dart", metavar="VERSION", help="'stable' or an exact X.Y.Z")
    group.add_argument("--flutter", metavar="VERSION", help="'stable', X.Y.Z, or X.Y.x")
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(os.environ.get("RUNNER_TOOL_CACHE") or tempfile.gettempdir()),
    )
    args = parser.parse_args(argv)
    try:
        if args.dart:
            bin_dir = install_dart(args.dart, args.root)
        else:
            bin_dir = install_flutter(args.flutter, args.root)
    except (ToolchainError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    github_path = os.environ.get("GITHUB_PATH")
    if github_path:
        with open(github_path, "a", encoding="utf-8") as stream:
            stream.write(f"{bin_dir}\n")
    print(bin_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
