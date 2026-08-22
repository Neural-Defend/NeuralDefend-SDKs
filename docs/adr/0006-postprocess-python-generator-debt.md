# 0006. Post-process OpenAPI Generator 7.14.0 Python template debt

- **Status:** Accepted
- **Date:** 2026-08-22

## Context

The repository pins OpenAPI Generator to 7.14.0 via a digest-locked Docker image
(`generator/config.json`). That release's Python templates still emit:

- `to_json()` helpers that call `json.dumps(self.to_dict())` with a TODO to switch to
  Pydantic v2's `model_dump_json(by_alias=True, exclude_unset=True)`.
- A `NATIVE_TYPES_MAPPING` entry for Java's `long` type with a TODO noting Python 3 only.

Upstream fixed the `to_json` serialization path in 7.21.0. Upgrading the generator is a
separate, higher-risk change (new digest, regenerated cores, contract re-verification).
Custom Mustache templates would fork upstream and add ongoing merge burden.

The generated Python core under `packages/python/src/neuraldefend/_core/` must never be
hand-edited.

## Decision

Apply deterministic post-processing in `scripts/generate.py` immediately after Docker
generation and before the generated tree is copied into package destinations:

1. Replace the legacy `to_json` body with `model_dump_json(by_alias=True, exclude_unset=True)`.
2. Remove the stale TODO comment from the `long` → `int` mapping (the mapping itself
   remains harmless on Python 3).

Track the upstream limitation in `generator/config.json` under `accepted_upstream_debt`.

## Consequences

- Every regeneration applies the same fixes without maintaining custom generator templates.
- `scripts/check_generated.py` enforces that committed cores match post-processed output.
- When upgrading OpenAPI Generator past 7.21.0, re-run generation and delete the
  post-processing step if upstream output no longer carries the TODO markers.
