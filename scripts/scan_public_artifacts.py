#!/usr/bin/env python3
"""Scan publishable source trees and package archives for forbidden content."""

from __future__ import annotations

import argparse
import os
import re
import sys
import tarfile
import zipfile
from collections.abc import Iterable, Iterator
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PATHS = (
    REPO_ROOT / ".github",
    REPO_ROOT / "README.md",
    REPO_ROOT / "CHANGELOG.md",
    REPO_ROOT / "CONTRIBUTING.md",
    REPO_ROOT / "SECURITY.md",
    REPO_ROOT / "docs" / "client",
    REPO_ROOT / "examples",
    REPO_ROOT / "packages",
    REPO_ROOT / "skills",
    REPO_ROOT / "spec",
)
SKIPPED_DIRECTORIES = {
    ".git",
    ".mypy_cache",
    ".pytest_cache",
    ".ruff_cache",
    ".venv",
    "__pycache__",
    "build",
    "dist",
    "node_modules",
    "venv",
}
TEXT_SUFFIXES = {
    "",
    ".cjs",
    ".cts",
    ".html",
    ".js",
    ".json",
    ".md",
    ".mjs",
    ".py",
    ".toml",
    ".ts",
    ".txt",
    ".yaml",
    ".yml",
}
FORBIDDEN_TERMS = (
    "prediction_tag",
    "scrfd",
    "mediapipe",
    "insightface",
    "cosmos",
    "azure",
    ".pth",
    "/internal/",
    "neuroverify_db_s3_mcc",
)
SECRET_PATTERNS = {
    "AWS access key": re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
    "GitHub token": re.compile(r"\bgh[pousr]_[A-Za-z0-9_]{20,}\b"),
    "OpenAI-style key": re.compile(r"\bsk-[A-Za-z0-9]{20,}\b"),
    "private key": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
}


def _source_files(path: Path) -> Iterator[Path]:
    if path.is_file():
        yield path
        return
    if not path.exists():
        return
    for current, directories, filenames in os.walk(path):
        current_path = Path(current)
        directories[:] = sorted(
            name
            for name in directories
            if name not in SKIPPED_DIRECTORIES
            and not (current_path / name).is_symlink()
        )
        for filename in sorted(filenames):
            candidate = current_path / filename
            if not candidate.is_symlink():
                yield candidate


def _archive_members(path: Path) -> Iterator[tuple[str, bytes]]:
    lower_name = path.name.casefold()
    if zipfile.is_zipfile(path):
        with zipfile.ZipFile(path) as archive:
            for member in archive.infolist():
                if not member.is_dir():
                    yield f"{path}!{member.filename}", archive.read(member)
        return
    if lower_name.endswith((".tar.gz", ".tgz")):
        with tarfile.open(path, "r:gz") as archive:
            for member in archive.getmembers():
                if member.isfile():
                    stream = archive.extractfile(member)
                    if stream is not None:
                        yield f"{path}!{member.name}", stream.read()


def _text_payloads(paths: Iterable[Path]) -> Iterator[tuple[str, bytes]]:
    for root in paths:
        for path in _source_files(root):
            lower_name = path.name.casefold()
            if zipfile.is_zipfile(path) or lower_name.endswith((".tar.gz", ".tgz")):
                yield from _archive_members(path)
            elif path.suffix.casefold() in TEXT_SUFFIXES:
                yield str(path), path.read_bytes()


def scan(paths: Iterable[Path]) -> list[str]:
    findings: list[str] = []
    for name, payload in _text_payloads(paths):
        if b"\0" in payload:
            continue
        try:
            text = payload.decode("utf-8")
        except UnicodeDecodeError:
            continue
        lowered = text.casefold()
        for term in FORBIDDEN_TERMS:
            if term.casefold() in lowered:
                findings.append(f"{name}: forbidden internal term {term!r}")
        for label, pattern in SECRET_PATTERNS.items():
            if pattern.search(text):
                findings.append(f"{name}: possible {label}")
    return findings


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", type=Path)
    args = parser.parse_args(argv)
    paths = (
        tuple(path.resolve() for path in args.paths) if args.paths else DEFAULT_PATHS
    )
    try:
        findings = scan(paths)
    except OSError as exc:
        print(f"public artifact scan failed: {exc}", file=sys.stderr)
        return 1
    if findings:
        for finding in findings:
            print(finding, file=sys.stderr)
        return 1
    print(f"public artifact scan passed ({len(paths)} roots)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
