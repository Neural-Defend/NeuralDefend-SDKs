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
- Prepared patch releases: `neuraldefend` 1.0.3, `@neuraldefend/sdk` 1.0.4, and
  `neuraldefend-mcp` 1.0.3.

### Added

- OpenAPI contract (`spec/`) and endpoint documentation (`docs/client/`).
- Architecture decision records (`docs/adr/`), starting with ADR-0001 on deriving
  `spec/public.json` from `spec/public.yaml`.
- Repository scaffolding: license, generator version pin, line-ending normalisation, and
  ignore rules.
- Digest-pinned spec synchronization, validation, provenance, and deterministic core
  generation.
- Python and TypeScript 1.0 facades with shared contract fixtures and package validation.
- Secure stdio MCP server and installable media-authenticity agent skill.
- Matrix CI, dependency auditing, staging smoke checks, and OIDC release workflows.
