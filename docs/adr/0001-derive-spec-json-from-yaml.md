# 0001. Derive `spec/public.json` from `spec/public.yaml`

- **Status:** Accepted
- **Date:** 2026-07-26

## Context

`spec/public.yaml` is the authoritative contract artifact in this repository. Generation,
synchronization, and drift checks all consume the YAML. Nothing consumes JSON directly.

The API repository commits both `openapi/public.json` and `openapi/public.yaml`, because
FastAPI serves its spec at `/openapi.json` and the JSON has a real job there. Both files
were copied into this repository when it was seeded. They were verified identical when
this record was written.

Keeping a second hand-maintained copy of the contract creates a drift risk that nothing
currently detects: an edit to one file would not fail any check, and the resulting
mismatch would surface as a confusing generator or documentation bug much later.

Deleting the JSON was considered and rejected. JSON is easier for some tooling and some
readers to consume, and the cost of keeping it is low provided it cannot drift.

## Decision

Keep `spec/public.json`, but treat it as a derived artifact rather than a source file.

`scripts/sync_spec.py` regenerates it from `spec/public.yaml` on every sync, and CI asserts
that the two parse to equal structures. Neither file is ever hand-edited; both are refreshed
from the API repository.

## Consequences

- `sync_spec.py` gains a serialisation step and must write both files atomically, so a
  failed sync cannot leave one refreshed and the other stale.
- The equality check compares parsed structures, not bytes. YAML and JSON differ in
  formatting by nature, so a byte comparison would always fail.
- `spec/public.json` is marked `linguist-generated=true` in `.gitattributes` alongside the
  YAML, and its provenance is covered by the existing `spec/SPEC_SOURCE.json` record.
- Contributors must not edit either file; both are refreshed by the synchronization
  workflow.
