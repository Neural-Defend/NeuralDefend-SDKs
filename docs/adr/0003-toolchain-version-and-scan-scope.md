# 0003. Toolchain version and scan scope

- **Status:** Accepted
- **Date:** 2026-07-26

## Context

The published Python SDK targets Python 3.9+, while repository maintenance scripts can
use Python 3.10+. The final security posture scans source, generated packages, and built
artifacts, but Phase 1 owns only the spec and generation tooling.

## Decision

Repository scripts require Python 3.10+ and may use its standard-library features. This
does not change the Python 3.9+ runtime target of the published SDK.

During Phase 1 the forbidden-term scan covers `spec/public.yaml` and its derived
`spec/public.json` only. Later package and release phases must extend the same scan to SDK
source and built artifacts before publication.

## Consequences

Maintenance code can remain small without raising the SDK's consumer requirement. Passing
Phase 1 validation is not evidence that future generated or packaged artifacts have been
scanned.
