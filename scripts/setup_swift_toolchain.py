#!/usr/bin/env python3
"""Install a signature-verified Swift toolchain for Linux CI from swift.org.

The repository's Actions policy allows only approved third-party actions, so CI installs
Swift with this script instead of a marketplace action. The tarball's detached GPG
signature must be valid and made by a pinned Swift release-signing key; the keyring is
fetched from swift.org, but only the pinned fingerprints are trusted. On GitHub Actions the
toolchain `usr/bin` directory is appended to `GITHUB_PATH`.
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import re
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
from pathlib import Path

RELEASES_URL = "https://www.swift.org/api/v1/install/releases.json"
DOWNLOADS = "https://download.swift.org"
KEYS_URL = "https://swift.org/keys/all-keys.asc"
# Primary-key fingerprints of the "Swift 6.x Release Signing Key". Add a fingerprint here
# only after checking it against https://www.swift.org/install/linux/#installation-via-tarball.
TRUSTED_FINGERPRINTS = frozenset({"52BB7E3DE28A71BE22EC05FFEF80A866B47A981F"})
EXACT_VERSION = re.compile(r"^\d+\.\d+(?:\.\d+)?$")


class ToolchainError(RuntimeError):
    pass


def _fetch(url: str) -> bytes:
    with urllib.request.urlopen(url, timeout=600) as response:
        return response.read()


def resolve_version(requested: str, releases: list[dict[str, object]] | None = None) -> str:
    """Return an exact release name. `latest` is the newest release on swift.org."""

    if requested != "latest":
        if not EXACT_VERSION.match(requested):
            raise ToolchainError("Swift version must be 'latest' or an exact X.Y or X.Y.Z")
        return requested
    if releases is None:
        releases = json.loads(_fetch(RELEASES_URL))
    names = [str(release["name"]) for release in releases]
    if not names:
        raise ToolchainError("swift.org listed no releases")
    return max(names, key=lambda name: tuple(int(part) for part in name.split(".")))


def linux_platform() -> tuple[str, str]:
    """Return swift.org's (directory, file suffix) for this Ubuntu host, for example
    ("ubuntu2404", "ubuntu24.04")."""

    if platform.system() != "Linux":
        raise ToolchainError("this installer supports Linux; macOS uses the Xcode toolchain")
    release: dict[str, str] = {}
    for line in Path("/etc/os-release").read_text(encoding="utf-8").splitlines():
        key, _, value = line.partition("=")
        release[key] = value.strip().strip('"')
    if release.get("ID") != "ubuntu" or not release.get("VERSION_ID"):
        raise ToolchainError("only Ubuntu hosts are supported")
    version = release["VERSION_ID"]
    return f"ubuntu{version.replace('.', '')}", f"ubuntu{version}"


def toolchain_url(version: str, directory: str, suffix: str, machine: str) -> str:
    arch = "-aarch64" if machine.lower() in {"aarch64", "arm64"} else ""
    name = f"swift-{version}-RELEASE"
    return (
        f"{DOWNLOADS}/swift-{version}-release/{directory}{arch}/{name}/"
        f"{name}-{suffix}{arch}.tar.gz"
    )


def signing_fingerprint(status: str) -> str | None:
    """Extract the primary-key fingerprint from `gpg --status-fd` output of a good signature."""

    good = any(line.startswith("[GNUPG:] GOODSIG ") for line in status.splitlines())
    for line in status.splitlines():
        if line.startswith("[GNUPG:] VALIDSIG "):
            fields = line.split()
            # VALIDSIG <fingerprint> <date> <timestamp> <expire> <version> <reserved>
            #          <pubkey-algo> <hash-algo> <sig-class> <primary-key-fingerprint>
            if good and len(fields) >= 12:
                return fields[11].upper()
    return None


def verify_signature(archive: Path, signature: Path, keys: bytes) -> str:
    with tempfile.TemporaryDirectory() as home:
        env = {**os.environ, "GNUPGHOME": home}
        subprocess.run(
            ["gpg", "--batch", "--quiet", "--import"],
            input=keys,
            env=env,
            check=True,
            capture_output=True,
        )
        result = subprocess.run(
            ["gpg", "--batch", "--status-fd", "1", "--verify", str(signature), str(archive)],
            env=env,
            capture_output=True,
            text=True,
        )
    fingerprint = signing_fingerprint(result.stdout)
    if result.returncode != 0 or fingerprint is None:
        raise ToolchainError(f"invalid signature for {archive.name}: {result.stderr.strip()}")
    if fingerprint not in TRUSTED_FINGERPRINTS:
        raise ToolchainError(f"{archive.name} is signed by untrusted key {fingerprint}")
    return fingerprint


def _extract(archive: Path, destination: Path) -> None:
    with tarfile.open(archive) as bundle:
        if sys.version_info >= (3, 12):
            bundle.extractall(destination, filter="tar")
            return
        for member in bundle.getmembers():
            target = (destination / member.name).resolve()
            if not target.is_relative_to(destination.resolve()):
                raise ToolchainError(f"archive member escapes destination: {member.name}")
        bundle.extractall(destination)


def install(requested: str, root: Path) -> Path:
    version = resolve_version(requested)
    directory, suffix = linux_platform()
    url = toolchain_url(version, directory, suffix, platform.machine())
    destination = root / f"swift-{version}"
    with tempfile.TemporaryDirectory() as scratch:
        archive = Path(scratch) / "swift.tar.gz"
        signature = Path(scratch) / "swift.tar.gz.sig"
        print(f"downloading {url}", flush=True)
        archive.write_bytes(_fetch(url))
        signature.write_bytes(_fetch(f"{url}.sig"))
        fingerprint = verify_signature(archive, signature, _fetch(KEYS_URL))
        print(f"verified signature from {fingerprint}", flush=True)
        destination.mkdir(parents=True, exist_ok=True)
        _extract(archive, destination)
    bin_dirs = list(destination.glob("*/usr/bin"))
    if len(bin_dirs) != 1:
        raise ToolchainError(f"unexpected toolchain layout in {destination}")
    print(f"installed Swift {version}", flush=True)
    return bin_dirs[0]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version", help="'latest' or an exact version such as 6.0.3")
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(os.environ.get("RUNNER_TOOL_CACHE") or tempfile.gettempdir()),
    )
    args = parser.parse_args(argv)
    try:
        bin_dir = install(args.version, args.root)
    except (ToolchainError, OSError, subprocess.CalledProcessError) as error:
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
