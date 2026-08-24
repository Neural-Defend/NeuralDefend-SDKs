# Contributing

This repository publishes customer-facing SDKs. Correct contract handling and accidental
data disclosure are higher risks than implementation convenience.

## Before changing code

1. Read the API behaviours and response scenarios in `docs/client/`.
2. Treat `spec/public.yaml` as generated input. Never edit either spec file by hand.
3. Never edit `packages/python/src/neuraldefend/_core/`,
   `packages/typescript/src/core/`, or `packages/go/internal/core/`; regenerate them with
   `scripts/generate.py`.
4. Never commit API keys, customer media, biometric data, build outputs, or local
   environment files.

## Contract rules

- Branch on the response envelope's `status`, not HTTP 200 alone.
- A business rejection is a normal result. A server error is an exception.
- Keep video and audio risk fields independent.
- Use risk levels for business decisions; server-owned score thresholds may change.
- Unknown response fields and enum values must not break installed clients.
- Retry only 429, 500, and 503. Never retry a successful, billable request.

## Verification

Run the language-specific lint, type, test, and package checks documented in each package
README. Contract changes require:

- a refreshed spec with `spec/SPEC_SOURCE.json`;
- regenerated private cores;
- a language-neutral fixture under `tests/fixtures/`; and
- equivalent Python, TypeScript, and Go tests.

Generated-code, package-content, secret, and internal-term checks must pass before merge.

