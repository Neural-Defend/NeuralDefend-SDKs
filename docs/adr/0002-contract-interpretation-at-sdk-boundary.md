# 0002. Contract interpretation at the SDK boundary

- **Status:** Accepted
- **Date:** 2026-07-26

## Context

Early design notes used both “three retries” and “max three attempts”, while the facade
constructor calls the setting `max_retries`. They also described nullable risk fields as
optional even though the authoritative OpenAPI schemas list those properties as required
and nullable. A proposed default of 12 for `max_frames` was not declared as an OpenAPI
`default`.

## Decision

`max_retries = 3` means three retries after the initial request: four total attempts.
Exhausted HTTP 500 and 503 responses raise `ServerError`, preserving a parsed envelope
when available.

Required nullable response properties are required wire keys whose values may be null;
they are not optional properties. Query parameter presence, constraints, and defaults are
taken only from `spec/public.yaml`. Consequently the generated core does not invent a
`max_frames` default. A facade may apply 12 explicitly as its own documented default.

## Consequences

Retry tests count attempts explicitly. Generated types follow the wire contract even when
older prose differs, and future contract changes must first be made in the authoritative
spec.
