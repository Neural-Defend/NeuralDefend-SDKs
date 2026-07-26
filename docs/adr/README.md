# Architecture decision records

Short notes recording decisions that a future maintainer would otherwise have to
reverse-engineer from the code, along with the reasoning that produced them.

An ADR is required for major architecture changes, including replacing the generated
core, switching generators, or changing how the public API contract is interpreted.

Write one whenever the answer to "why is it like this?" is not obvious from the code.

## Convention

Files are named `NNNN-short-hyphenated-title.md`, numbered sequentially from `0001`.
Records are immutable once accepted: to change a decision, write a new ADR that supersedes
the old one and add a note to the original pointing forward.

## Template

```markdown
# NNNN. Title

- **Status:** Proposed | Accepted | Superseded by ADR-NNNN
- **Date:** YYYY-MM-DD

## Context

What situation forced a decision. Facts, not opinions.

## Decision

What was chosen, stated plainly.

## Consequences

What this makes easier, what it makes harder, and what future work it obliges.
```
