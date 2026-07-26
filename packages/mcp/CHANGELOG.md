# Changelog

All notable changes to `neuraldefend-mcp` are documented here. This project follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and semantic versioning.

## [Unreleased]

### Added

- `NEURALDEFEND_MCP_ENVIRONMENT` configuration variable accepting `production`
  (default) or `staging`; arbitrary URLs are rejected.

### Fixed

- Preserve each validated media basename when forwarding uploads to the Python SDK so
  non-JPEG and non-MP4 files receive correct filename and MIME metadata.
- Reject SDK scores outside the public `0.1` through `10.0` contract instead of emitting
  a misleading successful tool result.

## [1.0.0] - 2026-07-26

### Added

- Stdio-only image and video authenticity tools backed by a shared NeuroVerify SDK client.
- Mandatory filesystem allowlisting, link/reparse-point rejection, single-open streaming,
  local size enforcement, and bounded concurrency.
- Sanitized short text plus versioned structured tool results.

### Security

- API keys are accepted only through `NEURALDEFEND_API_KEY`.
- Tool output excludes local names and paths, media, raw SDK payloads, and response headers.

Spec source: `494fc8c88585e0920efe54b41f3f8d355025c475` (`public.yaml` 1.0.0).

[Unreleased]: https://github.com/Neural-Defend/NeuralDefend-SDKs/compare/mcp-v1.0.0...HEAD
[1.0.0]: https://github.com/Neural-Defend/NeuralDefend-SDKs/releases/tag/mcp-v1.0.0
