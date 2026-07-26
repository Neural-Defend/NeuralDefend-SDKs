#!/usr/bin/env python3
"""Synchronize the authoritative public spec and record its provenance."""

from __future__ import annotations

import argparse
import base64
import binascii
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from spec_tools import (
    REPO_ROOT,
    SOURCE_PATH,
    SPEC_JSON,
    SPEC_SOURCE,
    SPEC_YAML,
    SpecError,
    atomic_write_files,
    deterministic_json,
    load_yaml_bytes,
    normalize_yaml_bytes,
    provenance_bytes,
    sha256_bytes,
    validate_spec_bytes,
)


COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")
PUBLIC_SOURCE_REPO = "private NeuroVerify API repository"


@dataclass(frozen=True)
class Source:
    repository: str
    reference: str
    resolved_commit: str
    timestamp: str
    raw_bytes: bytes
    blob_sha: str


def _run(arguments: list[str], *, cwd: Path | None = None) -> bytes:
    try:
        completed = subprocess.run(
            arguments,
            cwd=cwd,
            check=True,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except FileNotFoundError as exc:
        raise SpecError(f"required command not found: {arguments[0]}") from exc
    except subprocess.CalledProcessError as exc:
        detail = exc.stderr.decode("utf-8", errors="replace").strip()
        raise SpecError(
            f"{arguments[0]} command failed" + (f": {detail}" if detail else "")
        ) from exc
    return completed.stdout


def _text(arguments: list[str], *, cwd: Path | None = None) -> str:
    return _run(arguments, cwd=cwd).decode("utf-8").strip()


def _normalize_repository_url(remote: str) -> str:
    value = remote.strip()
    if value.startswith("git@github.com:"):
        value = value.removeprefix("git@github.com:")
    elif value.startswith("ssh://git@github.com/"):
        value = value.removeprefix("ssh://git@github.com/")
    elif value.startswith("https://github.com/"):
        value = value.removeprefix("https://github.com/")
    return value.removesuffix(".git").strip("/")


def source_from_path(checkout: Path) -> Source:
    checkout = checkout.resolve()
    if not (checkout / ".git").exists():
        raise SpecError(f"local source is not a Git checkout: {checkout}")
    dirty = _text(
        ["git", "status", "--porcelain", "--untracked-files=normal"],
        cwd=checkout,
    )
    if dirty:
        raise SpecError(
            "local source checkout is dirty; commit or clean it before syncing"
        )
    commit = _text(["git", "rev-parse", "HEAD"], cwd=checkout).lower()
    if COMMIT_RE.fullmatch(commit) is None:
        raise SpecError("local source HEAD did not resolve to an immutable commit")
    try:
        reference = _text(
            ["git", "symbolic-ref", "--quiet", "--short", "HEAD"],
            cwd=checkout,
        )
    except SpecError:
        reference = commit
    remote = _text(["git", "remote", "get-url", "origin"], cwd=checkout)
    repository = _normalize_repository_url(remote)
    timestamp = _text(["git", "show", "-s", "--format=%cI", commit], cwd=checkout)
    blob_sha = _text(
        ["git", "rev-parse", f"{commit}:{SOURCE_PATH}"],
        cwd=checkout,
    ).lower()
    if COMMIT_RE.fullmatch(blob_sha) is None:
        raise SpecError("local source spec did not resolve to a Git blob")
    try:
        raw = _run(["git", "show", f"{commit}:{SOURCE_PATH}"], cwd=checkout)
    except SpecError as exc:
        raise SpecError(f"cannot read local source spec from commit {commit}") from exc
    return Source(repository, reference, commit, timestamp, raw, blob_sha)


def _gh_json(endpoint: str, *extra: str) -> dict[str, Any]:
    raw = _run(["gh", "api", endpoint, *extra])
    try:
        result = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise SpecError(f"GitHub returned invalid JSON for {endpoint}") from exc
    if not isinstance(result, dict):
        raise SpecError(f"GitHub returned an unexpected response for {endpoint}")
    return result


def source_from_github(value: str) -> Source:
    try:
        repository, reference = value.rsplit("@", 1)
    except ValueError as exc:
        raise SpecError("--from-github must use owner/repo@ref") from exc
    if repository.count("/") != 1 or not reference:
        raise SpecError("--from-github must use owner/repo@ref")

    commit_data = _gh_json(f"repos/{repository}/commits/{reference}")
    commit = commit_data.get("sha")
    if not isinstance(commit, str) or COMMIT_RE.fullmatch(commit.lower()) is None:
        raise SpecError("GitHub did not resolve the ref to a 40-character commit SHA")
    commit = commit.lower()
    try:
        timestamp = commit_data["commit"]["committer"]["date"]
    except (KeyError, TypeError) as exc:
        raise SpecError(
            "GitHub commit metadata omitted the committer timestamp"
        ) from exc
    if not isinstance(timestamp, str) or not timestamp:
        raise SpecError("GitHub commit timestamp is invalid")

    content_data = _gh_json(
        f"repos/{repository}/contents/{SOURCE_PATH}",
        "-X",
        "GET",
        "-f",
        f"ref={commit}",
    )
    encoding = content_data.get("encoding")
    content = content_data.get("content")
    blob_sha = content_data.get("sha")
    if encoding != "base64" or not isinstance(content, str):
        raise SpecError("GitHub source spec was not returned as base64 content")
    if not isinstance(blob_sha, str) or COMMIT_RE.fullmatch(blob_sha.lower()) is None:
        raise SpecError("GitHub source spec omitted its Git blob SHA")
    try:
        raw = base64.b64decode("".join(content.split()), validate=True)
    except (ValueError, binascii.Error) as exc:
        raise SpecError("GitHub source spec contained invalid base64") from exc
    return Source(repository, reference, commit, timestamp, raw, blob_sha.lower())


def _utc_now() -> str:
    return (
        datetime.now(timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z")
    )


def _preserved_synced_at(proposed: bytes) -> str | None:
    if not SPEC_SOURCE.exists():
        return None
    try:
        old = json.loads(SPEC_SOURCE.read_text(encoding="utf-8"))
        new = json.loads(proposed.decode("utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        return None
    if not isinstance(old, dict) or not isinstance(new, dict):
        return None
    old_without_time = {key: value for key, value in old.items() if key != "synced_at"}
    new_without_time = {key: value for key, value in new.items() if key != "synced_at"}
    synced_at = old.get("synced_at")
    if old_without_time == new_without_time and isinstance(synced_at, str):
        return synced_at
    return None


def build_outputs(source: Source) -> dict[Path, bytes]:
    normalized = normalize_yaml_bytes(source.raw_bytes)
    document = load_yaml_bytes(normalized)
    derived_json = deterministic_json(document)
    validate_spec_bytes(normalized, derived_json)

    info = document.get("info")
    if not isinstance(info, dict) or not isinstance(info.get("version"), str):
        raise SpecError("info.version must be a string")
    provisional = provenance_bytes(
        source_repo=PUBLIC_SOURCE_REPO,
        source_ref=source.reference,
        resolved_commit=source.resolved_commit,
        source_blob_sha=source.blob_sha,
        source_raw_sha256=sha256_bytes(source.raw_bytes),
        local_normalized_sha256=sha256_bytes(normalized),
        derived_json_sha256=sha256_bytes(derived_json),
        spec_version=info["version"],
        source_timestamp=source.timestamp,
        synced_at=_utc_now(),
    )
    synced_at = _preserved_synced_at(provisional)
    provenance = (
        provenance_bytes(
            source_repo=PUBLIC_SOURCE_REPO,
            source_ref=source.reference,
            resolved_commit=source.resolved_commit,
            source_blob_sha=source.blob_sha,
            source_raw_sha256=sha256_bytes(source.raw_bytes),
            local_normalized_sha256=sha256_bytes(normalized),
            derived_json_sha256=sha256_bytes(derived_json),
            spec_version=info["version"],
            source_timestamp=source.timestamp,
            synced_at=synced_at,
        )
        if synced_at is not None
        else provisional
    )
    return {
        SPEC_YAML: normalized,
        SPEC_JSON: derived_json,
        SPEC_SOURCE: provenance,
    }


def _reject_dirty_destinations() -> None:
    relative_paths = [
        str(path.relative_to(REPO_ROOT)).replace("\\", "/")
        for path in (SPEC_YAML, SPEC_JSON, SPEC_SOURCE)
    ]
    dirty = _text(
        ["git", "status", "--porcelain", "--", *relative_paths],
        cwd=REPO_ROOT,
    )
    if dirty:
        raise SpecError("destination spec files are dirty; refusing to overwrite them")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--from-path", type=Path, metavar="CHECKOUT")
    source.add_argument("--from-github", metavar="OWNER/REPO@REF")
    parser.add_argument(
        "--check",
        action="store_true",
        help="exit non-zero instead of writing when synchronized files differ",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        source = (
            source_from_path(args.from_path)
            if args.from_path is not None
            else source_from_github(args.from_github)
        )
        outputs = build_outputs(source)
        differing = [
            path
            for path, expected in outputs.items()
            if not path.exists() or path.read_bytes() != expected
        ]
        if args.check:
            if differing:
                for path in differing:
                    print(
                        f"out of sync: {path.relative_to(REPO_ROOT)}", file=sys.stderr
                    )
                return 1
            print("spec is synchronized")
            return 0
        if not differing:
            print("spec is already synchronized; no files rewritten")
            return 0
        _reject_dirty_destinations()
        changed = atomic_write_files(outputs)
        for path in changed:
            print(f"updated {path.relative_to(REPO_ROOT)}")
        return 0
    except (OSError, SpecError) as exc:
        print(f"spec sync failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
