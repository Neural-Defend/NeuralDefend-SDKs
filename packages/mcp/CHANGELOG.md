# Changelog

All notable changes to `neuraldefend-mcp` are documented here. This project follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and semantic versioning.

## [Unreleased]

## [2.0.0] - 2026-08-22

### Changed

- Upgraded the MCP Python SDK dependency from v1 to v2 (`mcp>=2.0.0,<3`). `FastMCP`
  is now `MCPServer` (`mcp.server.mcpserver`), and Python-side `CallToolResult` fields
  use snake_case (`structured_content`, `is_error`). The JSON wire format is unchanged.
- Raised the minimum `neuraldefend` dependency to `1.0.3`.
- Pinned ruff to `0.16.1` in dev dependencies for parity with the Python SDK.

## [1.0.2] - 2026-07-27

### Changed

- Expanded PyPI metadata with SEO keywords, Homepage/Repository links, and topic
  classifiers for deepfake and AI-generated media detection.
- Added Neural Defend website API-key onboarding steps across the MCP guide, examples,
  and the media-authenticity agent skill.

## [1.0.1] - 2026-07-27

### Added

- `NEURALDEFEND_MCP_ENVIRONMENT` configuration variable accepting `production`
  (default) or `staging`; arbitrary URLs are rejected.

### Changed

- Expanded the published guide with complete setup examples, explicit API-key injection,
  tool documentation, structured response scenarios, security controls, and troubleshooting.

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

[Unreleased]: https://github.com/Neural-Defend/NeuralDefend-SDKs/compare/mcp-v2.0.0...HEAD
[2.0.0]: https://github.com/Neural-Defend/NeuralDefend-SDKs/compare/mcp-v1.0.2...mcp-v2.0.0
[1.0.2]: https://github.com/Neural-Defend/NeuralDefend-SDKs/compare/mcp-v1.0.1...mcp-v1.0.2
[1.0.1]: https://github.com/Neural-Defend/NeuralDefend-SDKs/compare/mcp-v1.0.0...mcp-v1.0.1
[1.0.0]: https://github.com/Neural-Defend/NeuralDefend-SDKs/releases/tag/mcp-v1.0.0
