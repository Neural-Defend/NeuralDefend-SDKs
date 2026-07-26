#!/usr/bin/env python3
"""Validate the public OpenAPI contract and its provenance."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

from spec_tools import (
    SOURCE_PATH,
    SPEC_JSON,
    SPEC_SOURCE,
    SPEC_YAML,
    SpecError,
    sha256_bytes,
    validate_spec_bytes,
)


SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")
PROVENANCE_FIELDS = {
    "schema_version",
    "source_repo",
    "source_ref",
    "resolved_commit",
    "source_path",
    "source_blob_sha",
    "source_raw_sha256",
    "local_normalized_sha256",
    "derived_json_sha256",
    "spec_version",
    "source_timestamp",
    "synced_at",
}


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise SpecError(message)


def validate_provenance(
    path: Path,
    yaml_bytes: bytes,
    json_bytes: bytes,
    spec_version: str,
) -> None:
    try:
        provenance: Any = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise SpecError(f"missing provenance file: {path}") from exc
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise SpecError(f"invalid provenance JSON: {exc}") from exc

    _require(isinstance(provenance, dict), "provenance must be a JSON object")
    _require(
        set(provenance) == PROVENANCE_FIELDS,
        "provenance fields do not match schema version 1",
    )
    _require(provenance["schema_version"] == 1, "unsupported provenance schema")
    for field in (
        "source_repo",
        "source_ref",
        "source_timestamp",
        "synced_at",
    ):
        _require(
            isinstance(provenance[field], str) and bool(provenance[field]),
            f"provenance {field} must be a non-empty string",
        )
    _require(provenance["source_path"] == SOURCE_PATH, "unexpected provenance source_path")
    _require(
        isinstance(provenance["resolved_commit"], str)
        and COMMIT_RE.fullmatch(provenance["resolved_commit"]) is not None,
        "provenance resolved_commit must be a lowercase 40-character SHA",
    )
    _require(
        isinstance(provenance["source_blob_sha"], str)
        and COMMIT_RE.fullmatch(provenance["source_blob_sha"]) is not None,
        "provenance source_blob_sha must be a lowercase 40-character SHA",
    )
    for field in (
        "source_raw_sha256",
        "local_normalized_sha256",
        "derived_json_sha256",
    ):
        _require(
            isinstance(provenance[field], str)
            and SHA256_RE.fullmatch(provenance[field]) is not None,
            f"provenance {field} must be a lowercase SHA-256",
        )
    _require(
        provenance["local_normalized_sha256"] == sha256_bytes(yaml_bytes),
        "provenance local_normalized_sha256 does not match spec/public.yaml",
    )
    _require(
        provenance["derived_json_sha256"] == sha256_bytes(json_bytes),
        "provenance derived_json_sha256 does not match spec/public.json",
    )
    _require(
        provenance["spec_version"] == spec_version,
        "provenance spec_version does not match info.version",
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--yaml", type=Path, default=SPEC_YAML)
    parser.add_argument("--json", type=Path, default=SPEC_JSON)
    parser.add_argument("--provenance", type=Path, default=SPEC_SOURCE)
    parser.add_argument(
        "--skip-provenance",
        action="store_true",
        help="validate only the YAML/JSON contract pair",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        yaml_bytes = args.yaml.read_bytes()
        json_bytes = args.json.read_bytes()
        document = validate_spec_bytes(yaml_bytes, json_bytes)
        if not args.skip_provenance:
            info = document.get("info")
            if not isinstance(info, dict) or not isinstance(info.get("version"), str):
                raise SpecError("info.version must be a string")
            validate_provenance(
                args.provenance,
                yaml_bytes,
                json_bytes,
                info["version"],
            )
    except (OSError, SpecError) as exc:
        print(f"spec validation failed: {exc}", file=sys.stderr)
        return 1
    print("spec validation passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
