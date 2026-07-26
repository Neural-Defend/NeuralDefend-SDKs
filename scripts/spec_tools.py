"""Shared, dependency-light helpers for the repository's spec tooling."""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import tempfile
import uuid
from collections.abc import Mapping
from pathlib import Path
from typing import Any

try:
    import yaml
    from yaml.events import AliasEvent
except ImportError as exc:  # pragma: no cover - exercised only on misconfigured hosts
    raise SystemExit(
        "PyYAML is required by the spec tooling. Install it with "
        "'python -m pip install PyYAML'."
    ) from exc


REPO_ROOT = Path(__file__).resolve().parents[1]
SPEC_YAML = REPO_ROOT / "spec" / "public.yaml"
SPEC_JSON = REPO_ROOT / "spec" / "public.json"
SPEC_SOURCE = REPO_ROOT / "spec" / "SPEC_SOURCE.json"
SOURCE_PATH = "openapi/public.yaml"

ALLOWED_SERVERS = {
    "https://deepscan.neuraldefend.com",
    "https://stage.deepscan.neuraldefend.com",
}
EXPECTED_OPERATIONS = {
    "/detect/image": "detectImage",
    "/detect/video": "detectVideo",
}
FORBIDDEN_TERMS = (
    "prediction_tag",
    "deepfake",
    "faceswap",
    "scrfd",
    "mediapipe",
    "insightface",
    "cosmos",
    "azure",
    ".pth",
    "/test/",
    "/internal/",
)
HTTP_METHODS = {
    "get",
    "put",
    "post",
    "delete",
    "options",
    "head",
    "patch",
    "trace",
}


class SpecError(ValueError):
    """Raised when a public spec invariant is violated."""


class StrictSafeLoader(yaml.SafeLoader):
    """Safe YAML loader that rejects aliases, anchors, and duplicate keys."""

    def compose_node(self, parent: Any, index: Any) -> Any:
        if self.check_event(AliasEvent):
            event = self.peek_event()
            raise SpecError(f"YAML aliases are forbidden (alias '*{event.anchor}')")
        event = self.peek_event()
        anchor = getattr(event, "anchor", None)
        if anchor is not None:
            raise SpecError(f"YAML anchors are forbidden (anchor '&{anchor}')")
        return super().compose_node(parent, index)

    def construct_mapping(self, node: Any, deep: bool = False) -> dict[Any, Any]:
        self.flatten_mapping(node)
        mapping: dict[Any, Any] = {}
        for key_node, value_node in node.value:
            key = self.construct_object(key_node, deep=deep)
            try:
                duplicate = key in mapping
            except TypeError as exc:
                raise SpecError("YAML mapping keys must be scalar values") from exc
            if duplicate:
                raise SpecError(
                    f"duplicate YAML key {key!r} at line {key_node.start_mark.line + 1}"
                )
            mapping[key] = self.construct_object(value_node, deep=deep)
        return mapping


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def normalize_yaml_bytes(raw: bytes) -> bytes:
    """Decode strict UTF-8, remove a BOM, and normalize all line endings to LF."""
    try:
        text = raw.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        raise SpecError("the source spec is not valid UTF-8") from exc
    return text.replace("\r\n", "\n").replace("\r", "\n").encode("utf-8")


def load_yaml_bytes(data: bytes) -> dict[str, Any]:
    try:
        document = yaml.load(data.decode("utf-8-sig"), Loader=StrictSafeLoader)
    except UnicodeDecodeError as exc:
        raise SpecError("spec/public.yaml is not valid UTF-8") from exc
    except yaml.YAMLError as exc:
        raise SpecError(f"invalid YAML: {exc}") from exc
    if not isinstance(document, dict):
        raise SpecError("the OpenAPI document must be a mapping")
    return document


def load_json_bytes(data: bytes) -> dict[str, Any]:
    try:
        document = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise SpecError(f"invalid JSON: {exc}") from exc
    if not isinstance(document, dict):
        raise SpecError("the derived JSON document must be an object")
    return document


def deterministic_json(document: Mapping[str, Any]) -> bytes:
    return (
        json.dumps(document, ensure_ascii=False, indent=2, separators=(",", ": "))
        + "\n"
    ).encode("utf-8")


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise SpecError(message)


def _validate_forbidden_terms(*documents: tuple[str, bytes]) -> None:
    for name, data in documents:
        try:
            lowered = data.decode("utf-8").casefold()
        except UnicodeDecodeError as exc:
            raise SpecError(f"{name} is not valid UTF-8") from exc
        hits = [term for term in FORBIDDEN_TERMS if term.casefold() in lowered]
        if hits:
            raise SpecError(
                f"{name} contains forbidden term(s): {', '.join(sorted(hits))}"
            )


def validate_document(document: Mapping[str, Any]) -> None:
    _require(document.get("openapi") == "3.0.3", "openapi must be exactly 3.0.3")

    paths = document.get("paths")
    _require(isinstance(paths, dict), "paths must be an object")
    _require(set(paths) == set(EXPECTED_OPERATIONS), "unexpected public API paths")

    operation_ids: list[str] = []
    for path, expected_operation_id in EXPECTED_OPERATIONS.items():
        path_item = paths[path]
        _require(isinstance(path_item, dict), f"{path} must be a path object")
        methods = {key.casefold() for key in path_item if key.casefold() in HTTP_METHODS}
        _require(methods == {"post"}, f"{path} must expose POST only")
        post = path_item.get("post")
        _require(isinstance(post, dict), f"{path} POST operation is missing")
        operation_id = post.get("operationId")
        _require(
            operation_id == expected_operation_id,
            f"{path} operationId must be {expected_operation_id}",
        )
        if "security" in post:
            _require(
                post["security"] == [{"ApiKeyAuth": []}],
                f"{path} must not override ApiKeyAuth",
            )
        operation_ids.append(operation_id)
        _validate_multipart(path, post)

    _require(
        len(operation_ids) == len(set(operation_ids)),
        "operationIds must be unique",
    )
    _validate_auth(document)
    _validate_servers(document)
    _validate_video_query(paths["/detect/video"]["post"])


def _validate_auth(document: Mapping[str, Any]) -> None:
    components = document.get("components")
    _require(isinstance(components, dict), "components must be an object")
    schemes = components.get("securitySchemes")
    _require(isinstance(schemes, dict), "components.securitySchemes must be an object")
    scheme = schemes.get("ApiKeyAuth")
    _require(isinstance(scheme, dict), "ApiKeyAuth security scheme is required")
    _require(scheme.get("type") == "apiKey", "ApiKeyAuth.type must be apiKey")
    _require(scheme.get("in") == "header", "ApiKeyAuth.in must be header")
    _require(scheme.get("name") == "x-api-key", "ApiKeyAuth.name must be x-api-key")
    _require(
        document.get("security") == [{"ApiKeyAuth": []}],
        "ApiKeyAuth must be globally required",
    )


def _validate_servers(document: Mapping[str, Any]) -> None:
    servers = document.get("servers")
    _require(isinstance(servers, list), "servers must be an array")
    urls = [
        server.get("url")
        for server in servers
        if isinstance(server, dict) and isinstance(server.get("url"), str)
    ]
    _require(
        len(urls) == len(servers) == len(ALLOWED_SERVERS),
        "every server must define exactly one allowed URL",
    )
    _require(set(urls) == ALLOWED_SERVERS, "server URLs do not match the allowlist")


def _validate_multipart(path: str, operation: Mapping[str, Any]) -> None:
    request_body = operation.get("requestBody")
    _require(isinstance(request_body, dict), f"{path} requestBody is required")
    _require(request_body.get("required") is True, f"{path} requestBody must be required")
    content = request_body.get("content")
    _require(isinstance(content, dict), f"{path} requestBody.content is required")
    multipart = content.get("multipart/form-data")
    _require(isinstance(multipart, dict), f"{path} must use multipart/form-data")
    schema = multipart.get("schema")
    _require(isinstance(schema, dict), f"{path} multipart schema is required")
    _require(schema.get("type") == "object", f"{path} multipart schema must be object")
    _require(schema.get("required") == ["file"], f"{path} must require only file")
    properties = schema.get("properties")
    _require(isinstance(properties, dict), f"{path} multipart properties are required")
    _require(set(properties) == {"file"}, f"{path} multipart field must be exactly file")
    file_schema = properties["file"]
    _require(isinstance(file_schema, dict), f"{path} file schema is required")
    _require(
        file_schema.get("type") == "string" and file_schema.get("format") == "binary",
        f"{path} file must be a binary string",
    )


def _validate_video_query(operation: Mapping[str, Any]) -> None:
    parameters = operation.get("parameters")
    _require(isinstance(parameters, list), "video parameters must be an array")
    by_name = {
        parameter.get("name"): parameter
        for parameter in parameters
        if isinstance(parameter, dict)
    }
    _require(
        set(by_name) == {"max_frames", "sample_rate"},
        "video query parameters must be exactly max_frames and sample_rate",
    )
    max_frames = by_name["max_frames"]
    sample_rate = by_name["sample_rate"]
    for name, parameter in by_name.items():
        _require(parameter.get("in") == "query", f"{name} must be a query parameter")
        _require(parameter.get("required") is False, f"{name} must be optional")
        schema = parameter.get("schema")
        _require(isinstance(schema, dict), f"{name} schema is required")
        _require(schema.get("type") == "integer", f"{name} must be integer")
        _require(schema.get("nullable") is True, f"{name} must be nullable")
        _require(schema.get("minimum") == 1, f"{name} minimum must be 1")
    _require(
        max_frames["schema"].get("maximum") == 100,
        "max_frames maximum must be 100",
    )
    _require(
        "maximum" not in sample_rate["schema"],
        "sample_rate must not define a maximum",
    )


def validate_spec_bytes(
    yaml_bytes: bytes,
    json_bytes: bytes,
    *,
    validate_terms: bool = True,
) -> dict[str, Any]:
    yaml_document = load_yaml_bytes(yaml_bytes)
    json_document = load_json_bytes(json_bytes)
    validate_document(yaml_document)
    _require(
        yaml_document == json_document,
        "spec/public.yaml and spec/public.json are not semantically equal",
    )
    if validate_terms:
        _validate_forbidden_terms(
            ("spec/public.yaml", yaml_bytes),
            ("spec/public.json", json_bytes),
        )
    return yaml_document


def provenance_bytes(
    *,
    source_repo: str,
    source_ref: str,
    resolved_commit: str,
    source_blob_sha: str,
    source_raw_sha256: str,
    local_normalized_sha256: str,
    derived_json_sha256: str,
    spec_version: str,
    source_timestamp: str,
    synced_at: str,
) -> bytes:
    payload = {
        "schema_version": 1,
        "source_repo": source_repo,
        "source_ref": source_ref,
        "resolved_commit": resolved_commit,
        "source_path": SOURCE_PATH,
        "source_blob_sha": source_blob_sha,
        "source_raw_sha256": source_raw_sha256,
        "local_normalized_sha256": local_normalized_sha256,
        "derived_json_sha256": derived_json_sha256,
        "spec_version": spec_version,
        "source_timestamp": source_timestamp,
        "synced_at": synced_at,
    }
    return deterministic_json(payload)


def atomic_write_files(files: Mapping[Path, bytes]) -> list[Path]:
    """Replace a group of files transactionally, rolling back on any failure."""
    changed = [path for path, data in files.items() if not path.exists() or path.read_bytes() != data]
    if not changed:
        return []

    token = uuid.uuid4().hex
    staged: dict[Path, Path] = {}
    backups: dict[Path, Path] = {}
    replaced: list[Path] = []
    try:
        for target in changed:
            target.parent.mkdir(parents=True, exist_ok=True)
            fd, temporary_name = tempfile.mkstemp(
                prefix=f".{target.name}.{token}.",
                suffix=".tmp",
                dir=target.parent,
            )
            temporary = Path(temporary_name)
            with os.fdopen(fd, "wb") as handle:
                handle.write(files[target])
                handle.flush()
                os.fsync(handle.fileno())
            staged[target] = temporary

        for target in changed:
            if target.exists():
                backup = target.with_name(f".{target.name}.{token}.bak")
                os.replace(target, backup)
                backups[target] = backup
            os.replace(staged[target], target)
            replaced.append(target)
    except Exception:
        for target in reversed(replaced):
            if target.exists():
                target.unlink()
            if target in backups and backups[target].exists():
                os.replace(backups[target], target)
        for target, backup in backups.items():
            if target not in replaced and backup.exists():
                os.replace(backup, target)
        raise
    finally:
        for temporary in staged.values():
            temporary.unlink(missing_ok=True)
        for backup in backups.values():
            backup.unlink(missing_ok=True)
    return changed


def file_manifest(root: Path) -> dict[str, str]:
    if not root.is_dir():
        return {}
    return {
        path.relative_to(root).as_posix(): sha256_bytes(path.read_bytes())
        for path in sorted(root.rglob("*"))
        if path.is_file()
    }


def replace_directory(source: Path, destination: Path) -> None:
    """Replace a generated directory without exposing a partially copied tree."""
    if not source.is_dir():
        raise FileNotFoundError(f"generated source directory not found: {source}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    token = uuid.uuid4().hex
    staged = destination.with_name(f".{destination.name}.{token}.tmp")
    backup = destination.with_name(f".{destination.name}.{token}.bak")
    shutil.copytree(source, staged)
    try:
        if destination.exists():
            os.replace(destination, backup)
        os.replace(staged, destination)
    except Exception:
        if destination.exists():
            shutil.rmtree(destination)
        if backup.exists():
            os.replace(backup, destination)
        raise
    finally:
        if staged.exists():
            shutil.rmtree(staged)
        if backup.exists():
            shutil.rmtree(backup)
