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
