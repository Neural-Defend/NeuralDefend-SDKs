#!/usr/bin/env python3
"""Generate private Python and TypeScript cores with pinned Docker tooling."""

from __future__ import annotations

import argparse
import json
import os
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
GO_CONFIG = REPO_ROOT / "generator" / "go.json"
GO_DESTINATION = REPO_ROOT / "packages" / "go" / "internal" / "core"
JAVA_CONFIG = REPO_ROOT / "generator" / "java.json"
JAVA_DESTINATION = (
    REPO_ROOT
    / "packages"
    / "java"
    / "src"
    / "main"
    / "java"
    / "com"
    / "neuraldefend"
    / "internal"
    / "core"
)
OPENAPI_GENERATOR_JAR = Path("/tmp/openapi-generator-cli-7.14.0.jar")
_GO_GENERATED_SKIP = frozenset(
    {
        "go.mod",
        "go.sum",
        "README.md",
        ".travis.yml",
        "git_push.sh",
        ".gitignore",
        ".openapi-generator-ignore",
    }
)
DIGEST_RE = re.compile(r"^sha256:[0-9a-f]{64}$")
_TO_JSON_LEGACY = (
    "        # TODO: pydantic v2: use .model_dump_json(by_alias=True, exclude_unset=True) instead\n"
    "        return json.dumps(self.to_dict())"
)
_TO_JSON_PYDANTIC_V2 = (
    "        return self.model_dump_json(by_alias=True, exclude_unset=True)"
)
_LONG_LEGACY = "'long': int, # TODO remove as only py3 is supported?"
_LONG_CLEAN = "'long': int,"


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


def _docker_user_arguments() -> list[str]:
    """Keep bind-mounted generator output owned by the invoking Linux user."""

    if not sys.platform.startswith("linux"):
        return []
    getuid = getattr(os, "getuid", None)
    getgid = getattr(os, "getgid", None)
    if not callable(getuid) or not callable(getgid):
        return []
    return ["--user", f"{getuid()}:{getgid()}"]


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
            *_docker_user_arguments(),
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


def _jar_generate(
    *,
    generator: str,
    config_path: str,
    output: Path,
) -> None:
    if not OPENAPI_GENERATOR_JAR.is_file():
        raise SpecError(
            "OpenAPI Generator JAR is unavailable; expected "
            f"{OPENAPI_GENERATOR_JAR}. Download openapi-generator-cli-7.14.0.jar "
            "or use the pinned Docker image."
        )
    output.mkdir(parents=True, exist_ok=True)
    _run(
        [
            "java",
            "-jar",
            str(OPENAPI_GENERATOR_JAR),
            "generate",
            "-i",
            str(SPEC_YAML),
            "-g",
            generator,
            "-o",
            str(output),
            "-c",
            str(REPO_ROOT / config_path),
        ]
    )


def _generate(
    *,
    image: str,
    generator: str,
    config_path: str,
    output: Path,
) -> None:
    try:
        verify_local_image(image)
        _docker_generate(
            image=image,
            generator=generator,
            config_path=config_path,
            output=output,
        )
    except SpecError:
        _jar_generate(
            generator=generator,
            config_path=config_path,
            output=output,
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


def _postprocess_python_generated(root: Path) -> None:
    """Apply stable fixes for known OpenAPI Generator 7.14.0 Python template debt."""

    if not root.is_dir():
        raise SpecError(f"Python generator output is missing: {root}")

    models_dir = root / "models"
    if models_dir.is_dir():
        for path in models_dir.glob("*.py"):
            text = path.read_text(encoding="utf-8")
            if _TO_JSON_LEGACY in text:
                path.write_text(
                    text.replace(_TO_JSON_LEGACY, _TO_JSON_PYDANTIC_V2),
                    encoding="utf-8",
                )

    api_client = root / "api_client.py"
    if api_client.is_file():
        text = api_client.read_text(encoding="utf-8")
        if _LONG_LEGACY in text:
            api_client.write_text(
                text.replace(_LONG_LEGACY, _LONG_CLEAN),
                encoding="utf-8",
            )


def _copy_java_generated(source_root: Path, destination: Path) -> None:
    java_root = (
        source_root
        / "src"
        / "main"
        / "java"
        / "com"
        / "neuraldefend"
        / "internal"
        / "core"
    )
    if not java_root.is_dir():
        raise SpecError(f"Java generator output is missing: {java_root}")
    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True)
    copied = 0
    for path in sorted(java_root.glob("*.java")):
        shutil.copy2(path, destination / path.name)
        copied += 1
    if copied == 0:
        raise SpecError("Java generator produced no contract .java files")


def _copy_go_generated(source_root: Path, destination: Path) -> None:
    if not source_root.is_dir():
        raise SpecError(f"Go generator output is missing: {source_root}")
    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True)
    copied = 0
    for path in sorted(source_root.rglob("*.go")):
        relative = path.relative_to(source_root)
        if relative.name in _GO_GENERATED_SKIP or relative.parts[0] in {".openapi-generator", "api"}:
            continue
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
        copied += 1
    if copied == 0:
        raise SpecError("Go generator produced no contract .go files")


def _assert_generated_contract(
    python_source: Path,
    typescript_source: Path,
    go_source: Path,
    java_source: Path,
) -> None:
    python_text = _combined_text(python_source)
    typescript_text = _combined_text(typescript_source)
    go_text = _combined_text(go_source)
    java_text = _combined_text(java_source)
    checks = {
        "Python detect_image operation": "detect_image" in python_text,
        "Python detect_video operation": "detect_video" in python_text,
        "TypeScript detectImage operation": "detectImage" in typescript_text,
        "TypeScript detectVideo operation": "detectVideo" in typescript_text,
        "Go DetectImage operation": "DetectImage" in go_text,
        "Go DetectVideo operation": "DetectVideo" in go_text,
        "Java detectImage operation": "detectImage" in java_text,
        "Java detectVideo operation": "detectVideo" in java_text,
        "Python x-api-key authentication": "x-api-key" in python_text,
        "TypeScript x-api-key authentication": "x-api-key" in typescript_text,
        "Go x-api-key authentication": "x-api-key" in go_text,
        "Java x-api-key authentication": "x-api-key" in java_text,
        "Python multipart file field": "file" in python_text,
        "TypeScript multipart file field": "file" in typescript_text,
        "Go multipart file field": "FormFile" in go_text or "formFile" in go_text,
        "Java multipart file field": '"file"' in java_text,
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
        if model not in java_text:
            raise SpecError(f"generated Java model is missing: {model}")
    for model in (
        "DetectImageResponse",
        "DetectVideoResponse",
        "UnifiedFaceAuthenticityScore",
        "UnifiedVideoAuthenticityScore",
        "ApiError",
    ):
        go_model = f"model_{model.lower()}" if model != "ApiError" else "model_api_error"
        if go_model not in go_text.lower() and model.lower() not in go_text.lower():
            raise SpecError(f"generated Go model is missing: {model}")


def generate_snapshot(snapshot: Path) -> None:
    if not SPEC_YAML.is_file():
        raise SpecError(f"authoritative input is missing: {SPEC_YAML}")
    image = pinned_image()
    with tempfile.TemporaryDirectory(prefix="neuraldefend-generator-") as temporary:
        build = Path(temporary) / "build"
        python_build = build / "python"
        typescript_build = build / "typescript"
        go_build = build / "go"
        java_build = build / "java"
        _generate(
            image=image,
            generator="python",
            config_path="generator/python.json",
            output=python_build,
        )
        _generate(
            image=image,
            generator="typescript-fetch",
            config_path="generator/typescript.json",
            output=typescript_build,
        )
        _generate(
            image=image,
            generator="go",
            config_path="generator/go.json",
            output=go_build,
        )
        _generate(
            image=image,
            generator="java",
            config_path="generator/java.json",
            output=java_build,
        )
        python_source = python_build / "neuraldefend" / "_core"
        typescript_source = typescript_build / "src"
        go_source = go_build
        java_source = (
            java_build
            / "src"
            / "main"
            / "java"
            / "com"
            / "neuraldefend"
            / "internal"
            / "core"
        )
        if not python_source.is_dir():
            raise SpecError(f"Python generator output is missing: {python_source}")
        if not typescript_source.is_dir():
            raise SpecError(f"TypeScript generator output is missing: {typescript_source}")
        if not go_source.is_dir():
            raise SpecError(f"Go generator output is missing: {go_source}")
        if not java_source.is_dir():
            raise SpecError(f"Java generator output is missing: {java_source}")
        _assert_generated_contract(python_source, typescript_source, go_source, java_source)
        _postprocess_python_generated(python_source)
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
        go_snapshot = snapshot / "go"
        _copy_go_generated(go_source, go_snapshot)
        java_snapshot = snapshot / "java"
        _copy_java_generated(java_build, java_snapshot)


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
            replace_directory(snapshot / "go", GO_DESTINATION)
            replace_directory(snapshot / "java", JAVA_DESTINATION)
        print("generated Python, TypeScript, Go, and Java private cores")
        return 0
    except (OSError, SpecError) as exc:
        print(f"generation failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
