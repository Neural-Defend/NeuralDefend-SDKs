# Release checklist

Concise pre-flight list for `python-v*`, `ts-v*`, `mcp-v*`, and `packages/go/v*` patch
releases. Full context lives in [releasing.md](releasing.md).

## One-time registry and environment setup

- [ ] **PyPI trusted publishers** — confirm pending publishers for `neuraldefend`
  (`release-python.yml` → environment `pypi`) and `neuraldefend-mcp`
  (`release-mcp.yml` → environment `mcp-pypi`) use owner `Neural-Defend`, repository
  `NeuralDefend-SDKs`, and the correct workflow filenames.
- [ ] **npm trusted publisher** — confirm `@neuraldefend/sdk` trusted publishing for
  `release-npm.yml` → environment `npm`. Do not retain long-lived registry tokens.
- [ ] **Protected environments** — `pypi`, `npm`, `mcp-pypi`, and `staging` require
  company reviewers, self-review prevention, and no administrator bypass.
- [ ] **Tag protection** — restrict creation, update, and deletion of `python-v*`,
  `ts-v*`, `mcp-v*`, and `packages/go/v*` tags to release managers; protect `main` with
  required reviews and CI checks.
- [ ] **Spec-sync secrets** — set repository variables `SPEC_SOURCE_REPOSITORY` and
  `SPEC_SOURCE_REF`, plus secret `SDK_SPEC_SYNC_TOKEN`, so the scheduled spec-sync
  workflow can read the private API repository.
- [ ] **Staging key** — add `NEURALDEFEND_STAGING_API_KEY` to the protected `staging`
  environment.

## Before tagging

- [ ] Package versions match intended tags (`python-vX.Y.Z`, `ts-vX.Y.Z`, `mcp-vX.Y.Z`,
  `packages/go/vX.Y.Z`).
- [ ] Changelogs updated; `scripts/validate_versions.py` passes.
- [ ] `scripts/check_generated.py` reports no drift; staging smoke tests pass.
- [ ] Run each release workflow manually in **dry-run** mode and inspect artifacts.

## Release order

1. `python-vX.Y.Z`
2. `mcp-vX.Y.Z` after `neuraldefend==X.Y.Z` is installable from PyPI
3. `ts-vX.Y.Z`
4. `packages/go/vX.Y.Z`

## Post-publication verification

- [ ] Install exact PyPI wheels/sdists, the npm tarball, and the Go module in clean
  consumers.
- [ ] Run staging smoke tests against published artifacts.
- [ ] Attach release notes, checksums, SBOMs, and provenance links to GitHub Releases.

## SBOM retention

Release and `dependency-security` workflows upload CycloneDX SBOMs as GitHub Actions
artifacts. Distribution artifacts use a **14-day** retention window; security-scan SBOMs
use the workflow default (typically **90 days**). Download SBOMs before they expire if
long-term retention is required.

## Spec-sync cron failures

The scheduled `spec-sync` workflow opens a PR when the upstream spec changes. On failure:

1. Inspect the workflow run log and confirm `SPEC_SOURCE_REPOSITORY`, `SPEC_SOURCE_REF`,
   and `SDK_SPEC_SYNC_TOKEN` are present and valid.
2. Re-run the workflow after fixing credentials or upstream access.
3. If the upstream spec advanced but automation failed, run spec sync locally, open a PR
   manually, and do not cut SDK releases until `spec/SPEC_SOURCE.json` matches the
   intended immutable source commit.
