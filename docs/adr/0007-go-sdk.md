# ADR 0007: Go SDK with private generated core and streaming facade

- Status: Accepted
- Date: 2026-08-24

## Context

The repository already ships Python and TypeScript SDKs using digest-pinned OpenAPI
Generator 7.14.0 output as private contract artifacts plus hand-written public facades
(ADR-0004). Go is a common choice for backend services and needs the same contract
semantics: streaming multipart uploads, bounded retries, typed results, and explicit
errors for operational failures.

Go modules in a monorepo are consumed from a subdirectory path
(`github.com/Neural-Defend/NeuralDefend-SDKs/packages/go`). Release tags use the
`packages/go/vX.Y.Z` prefix so the public module proxy can resolve versions without a
separate registry.

## Decision

Add `packages/go` as a public Go module:

- Generate the contract into `packages/go/internal/core/` with OpenAPI Generator `go`
  and the same pinned Docker image as Python and TypeScript.
- Keep the generated core private (`internal/`). Do not export it from the public API.
- Implement the public `neuraldefend` package with a hand-written facade that:
  - streams multipart uploads through `io.Pipe` and `multipart.Writer`;
  - retries only 429, 500, and 503 with the same backoff rules as other SDKs;
  - parses raw JSON into stable public result types; and
  - redacts API keys from errors and diagnostic envelopes.
- Enforce contract drift with `scripts/check_generated.py` and shared fixtures under
  `tests/fixtures/`.
- Release with GitHub tag `packages/go/vX.Y.Z`; CI validates tests and version alignment,
  then creates a GitHub Release. The Go module proxy indexes the tag automatically.

## Consequences

Go consumers install with `go get` and do not need PyPI or npm credentials. Large uploads
avoid buffering entire files in SDK memory. The generated core remains useful for detecting
contract changes but runtime behavior must be tested in the facade. Generation now covers
three languages; spec or generator changes must regenerate all private cores before merge.
