# Release runbook

The Python, TypeScript, and Go SDKs release independently. The MCP package depends on the
published Python SDK and must be released after a compatible Python version is available
on PyPI. Publishing requires an explicit protected-environment approval for PyPI and npm;
the Go SDK publishes through GitHub tags and the public Go module proxy. Building this
repository does not publish anything.

## One-time setup

1. Create PyPI pending Trusted Publishers using these exact identities:
   - `neuraldefend`: owner `Neural-Defend`, repository `NeuralDefend-SDKs`, workflow
     `release-python.yml`, environment `pypi`.
   - `neuraldefend-mcp`: the same owner/repository, workflow `release-mcp.yml`,
     environment `mcp-pypi`.
   A pending publisher does not reserve the name until its first successful publication.
2. Create the npm `@neuraldefend` organization. Because npm cannot configure trusted
   publishing before a package exists, publish an inspected minimal `@neuraldefend/sdk`
   version `0.0.0` once using a short-lived granular credential and interactive 2FA.
   Configure the trusted publisher for repository `Neural-Defend/NeuralDefend-SDKs`,
   workflow `release-npm.yml`, and environment `npm`, then revoke the bootstrap
   credential immediately.
3. Configure GitHub environments `pypi`, `npm`, `mcp-pypi`, and `staging` with required
   company reviewers, self-review prevention, and no administrator bypass.
4. Make the repository public only after the full-history security review. npm provenance
   publishing requires public source; do not run the npm release while the repository is
   private.
5. Configure PyPI and npm trusted publishing for the corresponding workflows. Do not
   retain registry publication tokens.
6. Set repository variables `SPEC_SOURCE_REPOSITORY` and `SPEC_SOURCE_REF` (the production
   API branch), plus secret `SDK_SPEC_SYNC_TOKEN`, so the scheduled workflow can read the
   private API repository. The scheduled `spec-sync` workflow fails loudly when any of
   these are missing; it does not skip sync silently.
7. Add `NEURALDEFEND_STAGING_API_KEY` to the protected `staging` environment.
8. Protect `main` with pull-request reviews and required checks. Restrict creation,
   update, and deletion of `python-v*`, `ts-v*`, `mcp-v*`, and `packages/go/v*` tags to
   release managers.
9. Enable secret scanning, push protection, Dependabot security updates, and required CI
   checks.

Before making the repository public, scan the complete Git history—not only the current
tree—for credentials, customer media, biometric data, internal model details, and private
infrastructure identifiers. Rewriting or squashing history is a separate destructive
operation and requires explicit approval.

## Spec synchronization credentials

The scheduled `spec-sync` workflow and `python scripts/sync_spec.py --from-github`
require all of the following:

| Name | Kind | Purpose |
| --- | --- | --- |
| `SPEC_SOURCE_REPOSITORY` | repository variable | Private API repo as `owner/repo` |
| `SPEC_SOURCE_REF` | repository variable | Production API branch or tag |
| `SDK_SPEC_SYNC_TOKEN` | repository secret | GitHub token with read access to the private API repo (`GH_TOKEN` for local sync) |

If any value is unset, `spec-sync.yml` exits with an explicit error before attempting
sync. Local developers without the token can still sync from a local API checkout:

```bash
python scripts/sync_spec.py --from-path /path/to/private-api-checkout
```

Verify GitHub configuration before relying on automation:

```bash
# Repository variables (visible in repo Settings → Secrets and variables → Actions)
test -n "${SPEC_SOURCE_REPOSITORY:-}" && echo "SPEC_SOURCE_REPOSITORY is set" \
  || echo "SPEC_SOURCE_REPOSITORY is missing"
test -n "${SPEC_SOURCE_REF:-}" && echo "SPEC_SOURCE_REF is set" \
  || echo "SPEC_SOURCE_REF is missing"
# Secret presence cannot be echoed; confirm SDK_SPEC_SYNC_TOKEN in repository secrets.
```

## Before every release

1. Synchronize and validate the spec; confirm `spec/SPEC_SOURCE.json` names the intended
   immutable source commit.
2. Regenerate all private cores and require `scripts/check_generated.py` to report no
   drift.
3. Run all lint, type, contract, security, package-content, and clean-install checks.
   Linux Python release jobs install `constraints/release.txt` with hash verification and
   build without isolation. When `constraints/release.in` changes, regenerate the
   platform-specific lock under Python 3.13 on Linux with pip-tools 7.6.0 using the command
   recorded in the lock header, then review the dependency diff.
4. Run staging smoke tests with the checked-in media under `tests/fixtures/media/`. Assert
   response shape, never an exact score or message.
5. Update the package changelog with the source-spec commit.
6. Confirm the package version matches the intended tag:
   - `python-vX.Y.Z`
   - `ts-vX.Y.Z`
   - `mcp-vX.Y.Z`
   - `packages/go/vX.Y.Z`
7. Inspect the wheel/sdist or npm tarball before approving the protected release job.
8. Run each release workflow manually in dry-run mode and retain its artifacts for review.

The workflows use OIDC and provenance attestations. A release tag starts publishing only
after the configured environment reviewer approves it.

## Release order and tags

Release from a commit already merged to the protected default branch. Create one tag at a
time and verify the registry before proceeding:

1. `python-vX.Y.Z`
2. `mcp-vX.Y.Z` after `neuraldefend==X.Y.Z` is installable from PyPI
3. `ts-vX.Y.Z`
4. `packages/go/vX.Y.Z` after the commit is on the default branch

The Go tag uses the module path prefix so `go get` resolves the version from the public
module proxy. No registry approval step is required; verify `go get` in a clean module
after the tag is pushed.

Stable tags must exactly match package metadata. Do not publish a prerelease to npm without
an explicit non-`latest` dist-tag.

## Post-publication verification

1. Install the exact Python wheel and sdist from PyPI in clean minimum/latest-runtime
   environments.
2. Install the MCP package from PyPI without a local SDK override and invoke both
   `neuraldefend-mcp` and `python -m neuraldefend_mcp`.
3. Install the exact npm package into clean ESM, CommonJS, TypeScript, and browser-bundle
   consumers.
4. Install the exact Go module version with `go get` in a clean module.
5. Run approved staging smoke tests against the published artifacts.
6. Publish release notes, checksums, SBOMs, and provenance links.

Registry releases are immutable. If a defect is found, stop rollout and publish a patched
version; yank/deprecate the affected version only when necessary and document the reason.

