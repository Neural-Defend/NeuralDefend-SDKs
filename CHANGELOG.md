# Changelog

Repository-level changes. Each package also keeps its own changelog, because the three
version lines are independent and an SDK version is not the API version:

- `packages/python/CHANGELOG.md` — tagged `python-v*`
- `packages/typescript/CHANGELOG.md` — tagged `ts-v*`
- `packages/mcp/CHANGELOG.md` — tagged `mcp-v*`

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html), judged from the facade's public
surface.

## [Unreleased]

### Changed

- Pinned GitHub Actions to current major releases (`actions/checkout` v7,
  `actions/setup-python` and `actions/setup-node` v7, `actions/upload-artifact` v7,
  `actions/download-artifact` v8) across CI, release, spec-sync, and security workflows.
- Updated Python dev tooling pins (`mypy<3`, `ruff==0.16.1`), TypeScript dev dependencies
  (`@types/node`, `publint`, `nanoid`), and grouped GitHub Actions updates in Dependabot.
- Prepared releases: `neuraldefend` 1.0.3, `@neuraldefend/sdk` 1.0.4, and
  `neuraldefend-mcp` 2.0.0 (MCP Python SDK v2 migration).
- Migrated `neuraldefend-mcp` to MCP Python SDK v2 (`MCPServer`, snake_case
  `CallToolResult` fields).
- Post-process OpenAPI Generator 7.14.0 Python output to use Pydantic v2
  `model_dump_json` (ADR-0006).
- Refreshed hash-pinned `constraints/release.txt` for MCP v2 release jobs.

### Added

- `docs/RELEASE_CHECKLIST.md` for publish prerequisites (trusted publishers, protected
  environments, spec-sync secrets, SBOM retention).
- ADR-0005 (MCP Python SDK v2) and ADR-0006 (generator post-processing).
- Spec-sync credential requirements documented in `docs/releasing.md`.
