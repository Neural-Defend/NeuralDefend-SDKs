# Release checklist

Concise pre-flight list for `python-v*`, `ts-v*`, `mcp-v*`, `packages/go/v*`, `dart-v*`,
`java-v*`, and Swift `X.Y.Z` patch releases. Full context lives in [releasing.md](releasing.md).

## One-time registry and environment setup

- [ ] **PyPI trusted publishers** — confirm pending publishers for `neuraldefend`
  (`release-python.yml` → environment `pypi`) and `neuraldefend-mcp`
  (`release-mcp.yml` → environment `mcp-pypi`) use owner `Neural-Defend`, repository
  `NeuralDefend-SDKs`, and the correct workflow filenames.
- [ ] **npm trusted publisher** — confirm `@neuraldefend/sdk` trusted publishing for
  `release-npm.yml` → environment `npm`. Do not retain long-lived registry tokens.
- [ ] **pub.dev automated publishing** — `neuraldefend` belongs to the Neural Defend
  verified publisher and allows GitHub Actions from `Neural-Defend/NeuralDefend-SDKs`
  with tag pattern `dart-v{{version}}` and required environment `pub-dev`.
- [ ] **Maven Central** — confirm the `com.neuraldefend` namespace is registered on the
  Central Portal and repository secrets `MAVEN_CENTRAL_USERNAME`, `MAVEN_CENTRAL_PASSWORD`,
  `MAVEN_CENTRAL_SIGNING_KEY`, and `MAVEN_CENTRAL_SIGNING_PASSWORD` are configured for
  `release-java.yml` → environment `maven-central`.
- [ ] **Protected environments** — `pypi`, `npm`, `mcp-pypi`, `pub-dev`, `maven-central`,
  `swift-release`, and `staging` require company reviewers, self-review prevention, and no
  administrator bypass.
- [ ] **Tag protection** — restrict creation, update, and deletion of `python-v*`,
  `ts-v*`, `mcp-v*`, `packages/go/v*`, `dart-v*`, `java-v*`, and Swift `[0-9]*.[0-9]*.[0-9]*`
  tags to release managers; protect `main` with required reviews and CI checks. The Swift tag
  ruleset must block deletion and force-updates, because a pushed Swift tag is installable
  immediately.
- [ ] **Swift Package Index** — after the first Swift tag, submit the repository at
  <https://swiftpackageindex.com/add-a-package>.
- [ ] **Spec-sync secrets** — set repository variables `SPEC_SOURCE_REPOSITORY` and
  `SPEC_SOURCE_REF`, plus secret `SDK_SPEC_SYNC_TOKEN`, so the scheduled spec-sync
  workflow can read the private API repository.
- [ ] **Staging key** — add `NEURALDEFEND_STAGING_API_KEY` to the protected `staging`
  environment.

## Before tagging

- [ ] Package versions match intended tags (`python-vX.Y.Z`, `ts-vX.Y.Z`, `mcp-vX.Y.Z`,
  `packages/go/vX.Y.Z`, `dart-vX.Y.Z`, `java-vX.Y.Z`, Swift `X.Y.Z` matching
  `NeuroVerifyClient.sdkVersion`).
- [ ] Changelogs updated; `scripts/validate_versions.py` passes.
- [ ] `scripts/check_generated.py` reports no drift; staging smoke tests pass.
- [ ] Run each release workflow manually in **dry-run** mode and inspect artifacts.

## Release order

1. `python-vX.Y.Z`
2. `mcp-vX.Y.Z` after `neuraldefend==X.Y.Z` is installable from PyPI
3. `ts-vX.Y.Z`
4. `packages/go/vX.Y.Z`
5. `dart-vX.Y.Z`
6. `java-vX.Y.Z` after Maven Central credentials and the `maven-central` environment are configured
7. `X.Y.Z` (Swift; never delete or move it once pushed)

## Post-publication verification

- [ ] Install exact PyPI wheels/sdists, the npm tarball, the Go module, the pub.dev
  package, the Maven Central artifact, and the Swift package (`exact: "X.Y.Z"`) in clean consumers.
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
