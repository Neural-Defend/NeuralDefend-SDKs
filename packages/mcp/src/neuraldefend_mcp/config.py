"""Environment-only configuration for the MCP server."""

from __future__ import annotations

import os
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Literal

from .path_security import PathConfigurationError, prepare_allowed_roots

DEFAULT_MAX_CONCURRENCY = 2
MAX_CONCURRENCY = 32
APIEnvironment = Literal["production", "staging"]


class ConfigurationError(Exception):
    """A startup-safe configuration error with no secret values."""


@dataclass(frozen=True)
class ServerConfig:
    api_key: str
    allowed_roots: tuple[Path, ...]
    environment: APIEnvironment = "production"
    max_concurrency: int = DEFAULT_MAX_CONCURRENCY


def _parse_concurrency(raw: str | None) -> int:
    if raw is None:
        return DEFAULT_MAX_CONCURRENCY
    try:
        value = int(raw, 10)
    except ValueError as exc:
        raise ConfigurationError(
            "NEURALDEFEND_MCP_MAX_CONCURRENCY must be a positive integer."
        ) from exc
    if value < 1 or value > MAX_CONCURRENCY:
        raise ConfigurationError(
            f"NEURALDEFEND_MCP_MAX_CONCURRENCY must be between 1 and {MAX_CONCURRENCY}."
        )
    return value


def _parse_environment(raw: str | None) -> APIEnvironment:
    value = "production" if raw is None else raw.strip().lower()
    if value == "production":
        return "production"
    if value == "staging":
        return "staging"
    raise ConfigurationError(
        "NEURALDEFEND_MCP_ENVIRONMENT must be either 'production' or 'staging'."
    )


def load_config(environ: Mapping[str, str] | None = None) -> ServerConfig:
    """Load and validate configuration without retaining the environment mapping."""

    env = os.environ if environ is None else environ
    api_key = env.get("NEURALDEFEND_API_KEY", "")
    if not api_key.strip():
        raise ConfigurationError("NEURALDEFEND_API_KEY is required.")

    allowed_dirs = env.get("NEURALDEFEND_MCP_ALLOWED_DIRS")
    if allowed_dirs is None or not allowed_dirs.strip():
        raise ConfigurationError("NEURALDEFEND_MCP_ALLOWED_DIRS is required.")
    entries = allowed_dirs.split(os.pathsep)
    if any(not entry.strip() for entry in entries):
        raise ConfigurationError("NEURALDEFEND_MCP_ALLOWED_DIRS contains an empty entry.")
    try:
        roots = prepare_allowed_roots(entries)
    except PathConfigurationError as exc:
        raise ConfigurationError(exc.public_message) from exc

    return ServerConfig(
        api_key=api_key.strip(),
        allowed_roots=roots,
        environment=_parse_environment(env.get("NEURALDEFEND_MCP_ENVIRONMENT")),
        max_concurrency=_parse_concurrency(env.get("NEURALDEFEND_MCP_MAX_CONCURRENCY")),
    )
