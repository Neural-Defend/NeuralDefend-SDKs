#!/usr/bin/env python3
"""Fail when package metadata and runtime version strings drift."""

from __future__ import annotations

import ast
import json
import re
import sys
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:  # Python 3.10 repository tooling.
    tomllib = None  # type: ignore[assignment]

ROOT = Path(__file__).resolve().parents[1]
SEMVER = re.compile(r"^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$")


def _toml_version(path: Path) -> str:
    if tomllib is not None:
        with path.open("rb") as stream:
            value = tomllib.load(stream)["project"]["version"]
    else:
        text = path.read_text(encoding="utf-8")
        project = re.search(r"(?ms)^\[project\]\s*(.*?)(?=^\[|\Z)", text)
        version = (
            re.search(r'(?m)^version\s*=\s*"([^"]+)"\s*$', project.group(1))
            if project is not None
            else None
        )
        if version is None:
            raise ValueError(f"{path}: missing project.version")
        value = version.group(1)
    if not isinstance(value, str):
        raise ValueError(f"{path}: project.version must be a string")
    return value


def _python_constant(path: Path, name: str) -> str:
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    for node in tree.body:
        if (
            isinstance(node, ast.Assign)
            and any(
                isinstance(target, ast.Name) and target.id == name
                for target in node.targets
            )
            and isinstance(node.value, ast.Constant)
            and isinstance(node.value.value, str)
        ):
            return node.value.value
    raise ValueError(f"{path}: missing string constant {name}")


def validate() -> None:
    python_version = _toml_version(ROOT / "packages/python/pyproject.toml")
    python_runtime = _python_constant(
        ROOT / "packages/python/src/neuraldefend/client.py", "SDK_VERSION"
    )
    mcp_version = _toml_version(ROOT / "packages/mcp/pyproject.toml")
    mcp_runtime = _python_constant(
        ROOT / "packages/mcp/src/neuraldefend_mcp/__init__.py", "__version__"
    )
    package_path = ROOT / "packages/typescript/package.json"
    package = json.loads(package_path.read_text(encoding="utf-8"))
    typescript_version = package["version"]
    lock = json.loads(
        (ROOT / "packages/typescript/package-lock.json").read_text(encoding="utf-8")
    )
    lock_versions = {lock["version"], lock["packages"][""]["version"]}
    client_source = (ROOT / "packages/typescript/src/client.ts").read_text(
        encoding="utf-8"
    )
    user_agent = re.search(r'@neuraldefend/sdk/([^"]+)"', client_source)

    go_version = ""
    for line in (ROOT / "packages/go/version.go").read_text(encoding="utf-8").splitlines():
        if "Version" in line and "=" in line:
            go_version = line.split("=")[1].strip().strip('"')
            break
    if not go_version:
        raise ValueError("packages/go/version.go: missing Version constant")

    java_manifest = ""
    for line in (ROOT / "packages/java/build.gradle.kts").read_text(encoding="utf-8").splitlines():
        if line.strip().startswith('version = "'):
            java_manifest = line.split('"')[1]
            break
    if not java_manifest:
        raise ValueError("packages/java/build.gradle.kts: missing version")
    java_runtime = ""
    java_runtime_match = re.search(
        r'VERSION\s*=\s*"([^"]+)"',
        (ROOT / "packages/java/src/main/java/com/neuraldefend/SdkVersion.java").read_text(
            encoding="utf-8"
        ),
    )
    if java_runtime_match is None:
        raise ValueError("packages/java/.../SdkVersion.java: missing VERSION constant")
    java_runtime = java_runtime_match.group(1)

    versions = {
        "Python manifest": python_version,
        "Python runtime": python_runtime,
        "MCP manifest": mcp_version,
        "MCP runtime": mcp_runtime,
        "TypeScript manifest": typescript_version,
        "Go runtime": go_version,
        "Java manifest": java_manifest,
        "Java runtime": java_runtime,
    }
    invalid = {
        name: value for name, value in versions.items() if not SEMVER.fullmatch(value)
    }
    if invalid:
        raise ValueError(f"invalid semantic versions: {invalid}")
    if python_runtime != python_version:
        raise ValueError("Python SDK_VERSION does not match pyproject.toml")
    if mcp_runtime != mcp_version:
        raise ValueError("MCP __version__ does not match pyproject.toml")
    if lock_versions != {typescript_version}:
        raise ValueError("TypeScript package-lock versions do not match package.json")
    if user_agent is None or user_agent.group(1) != typescript_version:
        raise ValueError("TypeScript user-agent version does not match package.json")
    if java_runtime != java_manifest:
        raise ValueError("Java SdkVersion.VERSION does not match build.gradle.kts")


def main() -> int:
    try:
        validate()
    except (
        KeyError,
        OSError,
        SyntaxError,
        TypeError,
        ValueError,
        json.JSONDecodeError,
    ) as exc:
        print(f"version validation failed: {exc}", file=sys.stderr)
        return 1
    print("package version validation passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
