# ADR 0005: Upgrade neuraldefend-mcp to MCP Python SDK v2

- Status: Accepted
- Date: 2026-08-22

## Context

Dependabot PR #17 bumps `mcp` from the v1 line (`>=1.28,<2`) to v2 (`>=2.0.0,<3`).
MCP Python SDK v2 is a breaking release:

- `FastMCP` was renamed to `MCPServer`; `mcp.server.fastmcp` no longer exists.
- Pydantic model fields exposed to Python code switched from camelCase to snake_case
  (for example `structuredContent` → `structured_content`, `isError` → `is_error`).
- The JSON wire format is unchanged; only Python attribute access and constructor
  keyword arguments changed.
- `mypy --strict` reports untyped-decorator errors on `@server.tool()` unless the
  decorator is explicitly ignored or the SDK ships typed overloads.

`neuraldefend-mcp` is a thin stdio server built on the high-level MCPServer API. It
returns explicit `CallToolResult` objects with both human-readable text and versioned
structured payloads.

## Decision

Adopt MCP Python SDK v2 in `packages/mcp` and apply the mechanical migration:

- Import `MCPServer` and `Context` from `mcp.server.mcpserver`.
- Construct `CallToolResult` with `structured_content` and `is_error`.
- Update tests that read Python-side result attributes to snake_case.
- Update `Context` annotations from `Context[ServerSession, AppContext]` to
  `Context[AppContext]` per the v2 type-parameter simplification.
- Accept the dependabot-safe dependency bumps bundled in PR #17 (anyio, neuraldefend
  floor, hatchling, dev tooling) after the test suite passes.

Keep README references to `structuredContent` and `isError` where they document the MCP
protocol contract visible to clients on the wire, not Python SDK attribute names.

## Consequences

- Consumers must install `mcp>=2,<3` alongside `neuraldefend-mcp`; v1 SDK servers
  cannot share a virtualenv with this package without a version conflict.
- Internal Python code and tests must use snake_case when accessing SDK model fields.
- Future MCP SDK minor releases within v2 should be safe to adopt without code changes
  unless the migration guide documents new breaks.
- If the SDK adds typed `@MCPServer.tool()` overloads that break under `--strict`, revisit
  tool registration annotations.
