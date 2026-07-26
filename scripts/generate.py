#!/usr/bin/env python3
"""Generate private Python and TypeScript cores with pinned Docker tooling."""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

from spec_tools import REPO_ROOT, SPEC_YAML, SpecError, replace_directory


GENERATOR_CONFIG = REPO_ROOT / "generator" / "config.json"
PYTHON_CONFIG = REPO_ROOT / "generator" / "python.json"
TYPESCRIPT_CONFIG = REPO_ROOT / "generator" / "typescript.json"
PYTHON_DESTINATION = REPO_ROOT / "packages" / "python" / "src" / "neuraldefend" / "_core"
TYPESCRIPT_DESTINATION = REPO_ROOT / "packages" / "typescript" / "src" / "core"
DIGEST_RE = re.compile(r"^sha256:[0-9a-f]{64}$")


def _load_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise SpecError(f"cannot load generator config {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise SpecError(f"generator config must be a JSON object: {path}")
    return value


def pinned_image() -> str:
    config = _load_object(GENERATOR_CONFIG)
    if config.get("schema_version") != 1:
        raise SpecError("unsupported generator config schema")
    if config.get("generator_version") != "7.14.0":
        raise SpecError("OpenAPI Generator must remain pinned to version 7.14.0")
    repository = config.get("image_repository")
    digest = config.get("image_digest")
    if not isinstance(repository, str) or not repository:
        raise SpecError("generator image_repository is missing")
    if not isinstance(digest, str) or DIGEST_RE.fullmatch(digest) is None:
        raise SpecError(
            "generator image digest is not pinned; resolve the published digest before generation"
        )
    return f"{repository}@{digest}"


def _run(arguments: list[str]) -> bytes:
    try:
        completed = subprocess.run(
            arguments,
            cwd=REPO_ROOT,
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
            f"{arguments[0]} command failed"
            + (f": {detail}" if detail else "")
        ) from exc
    return completed.stdout


def verify_local_image(image: str) -> None:
    try:
        raw = _run(["docker", "image", "inspect", image, "--format", "{{json .RepoDigests}}"])
    except SpecError as exc:
        raise SpecError(
            f"pinned generator image is unavailable locally: {image}. "
            f"Pull that exact digest outside this script before generating. ({exc})"
        ) from exc
    try:
        repo_digests = json.loads(raw.decode("utf-8").strip())
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise SpecError("Docker returned invalid image metadata") from exc
    if not isinstance(repo_digests, list) or image not in repo_digests:
        raise SpecError(f"local Docker image does not attest the configured digest: {image}")


def _docker_generate(
    *,
    image: str,
    generator: str,
    config_path: str,
    output: Path,
) -> None:
    output.mkdir(parents=True, exist_ok=True)
    root_mount = f"type=bind,source={REPO_ROOT},target=/local,readonly"
    output_mount = f"type=bind,source={output},target=/output"
    _run(
        [
            "docker",
            "run",
            "--rm",
            "--network",
            "none",
            "--mount",
            root_mount,
            "--mount",
            output_mount,
            image,
            "generate",
            "-i",
            "/local/spec/public.yaml",
            "-g",
            generator,
            "-o",
            "/output",
            "-c",
            f"/local/{config_path}",
        ]
    )


def _combined_text(root: Path) -> str:
    chunks: list[str] = []
    for path in sorted(root.rglob("*")):
        if path.is_file():
            try:
                chunks.append(path.read_text(encoding="utf-8"))
            except UnicodeDecodeError:
                continue
    return "\n".join(chunks)


def _assert_generated_contract(python_source: Path, typescript_source: Path) -> None:
    python_text = _combined_text(python_source)
    typescript_text = _combined_text(typescript_source)
    checks = {
        "Python detect_image operation": "detect_image" in python_text,
        "Python detect_video operation": "detect_video" in python_text,
        "TypeScript detectImage operation": "detectImage" in typescript_text,
        "TypeScript detectVideo operation": "detectVideo" in typescript_text,
        "Python x-api-key authentication": "x-api-key" in python_text,
        "TypeScript x-api-key authentication": "x-api-key" in typescript_text,
        "Python multipart file field": "file" in python_text,
        "TypeScript multipart file field": "file" in typescript_text,
    }
    missing = [name for name, present in checks.items() if not present]
    if missing:
        raise SpecError("generated contract verification failed: " + ", ".join(missing))
    for model in (
        "DetectImageResponse",
        "DetectVideoResponse",
        "UnifiedFaceAuthenticityScore",
        "UnifiedVideoAuthenticityScore",
        "ApiError",
    ):
        if model not in python_text or model not in typescript_text:
            raise SpecError(f"generated model is missing: {model}")


def generate_snapshot(snapshot: Path) -> None:
    if not SPEC_YAML.is_file():
        raise SpecError(f"authoritative input is missing: {SPEC_YAML}")
    image = pinned_image()
    verify_local_image(image)
    with tempfile.TemporaryDirectory(prefix="neuraldefend-generator-") as temporary:
        build = Path(temporary) / "build"
        python_build = build / "python"
        typescript_build = build / "typescript"
        _docker_generate(
            image=image,
            generator="python",
            config_path="generator/python.json",
            output=python_build,
        )
        _docker_generate(
            image=image,
            generator="typescript-fetch",
            config_path="generator/typescript.json",
            output=typescript_build,
        )
        python_source = python_build / "neuraldefend" / "_core"
        typescript_source = typescript_build / "src"
        if not python_source.is_dir():
            raise SpecError(f"Python generator output is missing: {python_source}")
        if not typescript_source.is_dir():
            raise SpecError(f"TypeScript generator output is missing: {typescript_source}")
        _assert_generated_contract(python_source, typescript_source)
        leaked_generated_artifacts = [
            path
            for path in (python_source / "test", python_source / "docs")
            if path.exists()
        ]
        if leaked_generated_artifacts:
            rendered = ", ".join(str(path) for path in leaked_generated_artifacts)
            raise SpecError(
                "generated Python tests/docs must not be copied into the SDK core: "
                + rendered
            )

        if snapshot.exists():
            shutil.rmtree(snapshot)
        snapshot.mkdir(parents=True)
        shutil.copytree(python_source, snapshot / "python")
        shutil.copytree(typescript_source, snapshot / "typescript")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--snapshot-dir",
        type=Path,
        help="write generated source to this directory instead of package destinations",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if args.snapshot_dir is not None:
            generate_snapshot(args.snapshot_dir.resolve())
            print(f"generated snapshot at {args.snapshot_dir.resolve()}")
            return 0
        with tempfile.TemporaryDirectory(prefix="neuraldefend-snapshot-") as temporary:
            snapshot = Path(temporary)
            generate_snapshot(snapshot)
            replace_directory(snapshot / "python", PYTHON_DESTINATION)
            replace_directory(snapshot / "typescript", TYPESCRIPT_DESTINATION)
        print("generated Python and TypeScript private cores")
        return 0
    except (OSError, SpecError) as exc:
        print(f"generation failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
