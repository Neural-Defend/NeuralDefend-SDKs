#!/usr/bin/env python3
"""Regenerate private cores and compare complete file manifests."""

from __future__ import annotations

import argparse
import sys
import tempfile
from pathlib import Path

from generate import (
    GO_DESTINATION,
    JAVA_DESTINATION,
    PYTHON_DESTINATION,
    TYPESCRIPT_DESTINATION,
    generate_snapshot,
)
from spec_tools import SpecError, file_manifest


def _compare(
    label: str,
    generated_root: Path,
    committed_root: Path,
) -> bool:
    generated = file_manifest(generated_root)
    committed = file_manifest(committed_root)
    added = sorted(generated.keys() - committed.keys())
    deleted = sorted(committed.keys() - generated.keys())
    changed = sorted(
        path
        for path in generated.keys() & committed.keys()
        if generated[path] != committed[path]
    )
    if not (added or deleted or changed):
        print(f"{label}: generated source is current")
        return True
    for path in added:
        print(f"{label}: ADD {path}", file=sys.stderr)
    for path in deleted:
        print(f"{label}: DELETE {path}", file=sys.stderr)
    for path in changed:
        print(f"{label}: CHANGE {path}", file=sys.stderr)
    return False


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--python-dir",
        type=Path,
        default=PYTHON_DESTINATION,
        help="committed Python generated-source directory",
    )
    parser.add_argument(
        "--typescript-dir",
        type=Path,
        default=TYPESCRIPT_DESTINATION,
        help="committed TypeScript generated-source directory",
    )
    parser.add_argument(
        "--go-dir",
        type=Path,
        default=GO_DESTINATION,
        help="committed Go generated-source directory",
    )
    parser.add_argument(
        "--java-dir",
        type=Path,
        default=JAVA_DESTINATION,
        help="committed Java generated-source directory",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        with tempfile.TemporaryDirectory(prefix="neuraldefend-check-") as temporary:
            snapshot = Path(temporary)
            generate_snapshot(snapshot)
            python_current = _compare(
                "python",
                snapshot / "python",
                args.python_dir.resolve(),
            )
            typescript_current = _compare(
                "typescript",
                snapshot / "typescript",
                args.typescript_dir.resolve(),
            )
            go_current = _compare(
                "go",
                snapshot / "go",
                args.go_dir.resolve(),
            )
            java_current = _compare(
                "java",
                snapshot / "java",
                args.java_dir.resolve(),
            )
    except (OSError, SpecError) as exc:
        print(f"generated-source check failed: {exc}", file=sys.stderr)
        return 1
    return (
        0
        if python_current and typescript_current and go_current and java_current
        else 1
    )


if __name__ == "__main__":
    raise SystemExit(main())
