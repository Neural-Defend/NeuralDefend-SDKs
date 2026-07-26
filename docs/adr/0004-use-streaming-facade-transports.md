# ADR 0004: Use streaming transports behind the public facades

- Status: Accepted
- Date: 2026-07-26

## Context

OpenAPI Generator 7.14.0 produces useful contract models and endpoint signatures, but its
Python `urllib3` client reads each multipart file completely into memory. The public API
accepts videos up to 1.5 GB, so using that client at runtime can exhaust application
memory. The TypeScript client accepts a `Blob`, but its generated operation does not give
the facade reliable cross-platform filename control and complicates the Node/browser
conditional boundary.

The public SDKs also need to parse untouched JSON so unknown response fields and values do
not break already-installed clients.

## Decision

Keep digest-pinned generated cores in both packages as private, reproducible contract
artifacts. Do not export them.

- The Python facade uses an injectable synchronous `httpx` transport, passes open file
  handles to multipart encoding, and rewinds or reopens media for each retry.
- The TypeScript facade uses an injectable Fetch transport, creates fresh `Blob` and
  `FormData` values for each retry, and uses `fs.openAsBlob` for file-backed Node uploads.
- Both facades parse raw response JSON into stable, hand-written public result types.
- Contract drift remains enforced by regenerated-core comparison and shared response
  fixtures.

## Consequences

Large path-based uploads do not need to be buffered in SDK memory. Browser bundles do not
contain Node built-ins. The generated core remains useful for detecting contract changes,
but runtime behavior must be tested directly in the facade. The Python package includes
the generated core's private dependencies so the checked-in artifact remains importable.

