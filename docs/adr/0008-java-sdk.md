# ADR 0008: Java SDK with private generated core and streaming facade

- Status: Accepted
- Date: 2026-08-26

## Context

The repository ships Python, TypeScript, and Go SDKs using digest-pinned OpenAPI Generator
7.14.0 output as private contract artifacts plus hand-written public facades (ADR-0004).
Java is widely used for enterprise services and needs the same contract semantics:
streaming multipart uploads, bounded retries, typed results, and explicit errors for
operational failures.

## Decision

Add `packages/java` as a public Gradle module:

- Generate the contract into `com.neuraldefend.internal.core` with OpenAPI Generator `java`
  (`library=native`) and the same pinned Docker image (or equivalent CLI JAR fallback) as
  other languages.
- Keep the generated core private. Do not expose it from the public API.
- Implement the public `com.neuraldefend` package with a hand-written facade that:
  - streams multipart uploads through OkHttp;
  - retries only 429, 500, and 503 with the same backoff rules as other SDKs;
  - parses raw JSON into stable public result types; and
  - redacts API keys from errors and diagnostic envelopes.
- Enforce contract drift with `scripts/check_generated.py` and shared fixtures under
  `tests/fixtures/`.
- Release with GitHub tag `java-vX.Y.Z`; CI validates tests and version alignment, then
  creates a GitHub Release.

## Consequences

Java consumers integrate from the monorepo path or a future Maven publication. Large uploads
avoid buffering entire files in SDK memory. The generated core remains useful for detecting
contract changes but runtime behavior must be tested in the facade. Generation now covers
four languages; spec or generator changes must regenerate all private cores before merge.
