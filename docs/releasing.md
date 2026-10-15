# Release runbook

The Python, TypeScript, Go, Dart, Java, Swift, and Kotlin SDKs release independently. The MCP
package depends on the published Python SDK and must be released after a compatible Python
version is available on PyPI. Publishing requires an explicit protected-environment approval for
PyPI, npm, pub.dev, and Maven Central; the Go SDK publishes through GitHub tags and the public Go
module proxy, and the Swift SDK publishes through plain `X.Y.Z` Git tags that Swift Package
Manager resolves directly. Building this repository does not publish anything.

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
3. Create a pub.dev verified publisher for the Neural Defend domain and publish the first
   `neuraldefend` version manually from a release manager's machine with `dart pub publish`
   (pub.dev cannot enable automated publishing before a package exists). Transfer the
   package to the verified publisher, then under **Admin → Automated publishing** enable
   GitHub Actions for repository `Neural-Defend/NeuralDefend-SDKs`, tag pattern
   `dart-v{{version}}`, and required environment `pub-dev`.
4. Set up Maven Central for the Java and Kotlin SDKs (see
   [Maven Central setup](#maven-central-setup) for the details of each step):
   - create a Central Portal account at <https://central.sonatype.com> under a shared
     company identity;
   - register and verify the `com.neuraldefend` namespace with the DNS TXT record the
     portal shows for the `neuraldefend.com` domain;
   - generate a portal user token (username and password pair);
   - generate a dedicated GPG signing key and publish its public key to
     `keyserver.ubuntu.com`;
   - create the `maven-central` GitHub environment, limited to tags matching `java-v*` and
     `kotlin-v*`, and store secrets `MAVEN_CENTRAL_USERNAME`, `MAVEN_CENTRAL_PASSWORD`,
     `MAVEN_CENTRAL_SIGNING_KEY` (ASCII-armored private key), and
     `MAVEN_CENTRAL_SIGNING_PASSWORD` in it. `release-java.yml` and `release-kotlin.yml` both
     publish from this environment.
5. Configure GitHub environments `pypi`, `npm`, `mcp-pypi`, `pub-dev`, `maven-central`,
   `swift-release`, and `staging` with required company reviewers, self-review prevention,
   and no administrator bypass.
6. Make the repository public only after the full-history security review. npm provenance
   publishing requires public source; do not run the npm release while the repository is
   private.
7. Configure PyPI and npm trusted publishing for the corresponding workflows. Do not
   retain registry publication tokens.
8. Set repository variables `SPEC_SOURCE_REPOSITORY` and `SPEC_SOURCE_REF` (the production
   API branch), plus secret `SDK_SPEC_SYNC_TOKEN`, so the scheduled workflow can read the
   private API repository. The scheduled `spec-sync` workflow fails loudly when any of
   these are missing; it does not skip sync silently.
9. Add `NEURALDEFEND_STAGING_API_KEY` to the protected `staging` environment.
10. Protect `main` with pull-request reviews and required checks. Restrict creation,
   update, and deletion of `python-v*`, `ts-v*`, `mcp-v*`, `packages/go/v*`, `dart-v*`,
   `java-v*`, `kotlin-v*`, and Swift `[0-9]*.[0-9]*.[0-9]*` tags to release managers with a
   tag ruleset. For Swift this ruleset is the real release control: a pushed tag is
   installable immediately, while the `swift-release` environment only gates the GitHub
   Release page. Deleting or moving a Swift tag breaks every app that resolved it, so the
   ruleset must block both.
11. Enable secret scanning, push protection, Dependabot security updates, and required CI
   checks.
12. After the first Swift tag exists, submit `https://github.com/Neural-Defend/NeuralDefend-SDKs`
   at <https://swiftpackageindex.com/add-a-package>. The index reads `.spi.yml` for the
   documentation target and builds every later tag automatically.

Before making the repository public, scan the complete Git history—not only the current
tree—for credentials, customer media, biometric data, internal model details, and private
infrastructure identifiers. Rewriting or squashing history is a separate destructive
operation and requires explicit approval.

## Maven Central setup

The Kotlin SDK publishes `com.neuraldefend:neuraldefend` (JVM) and
`com.neuraldefend:neuraldefend-android` (Android AAR) through the Central Portal. Maven
Central has no OIDC trusted publishing, so the release job uses a portal user token and a
GPG key stored only in the protected `maven-central` environment.

1. **Account.** Sign in to <https://central.sonatype.com> with a shared company account,
   not a personal one, and enable two-factor authentication.
2. **Namespace.** Under **Namespaces**, add `com.neuraldefend`. The portal shows a
   verification key; publish it as a DNS TXT record on `neuraldefend.com` and press
   **Verify**. Leave the record in place until the namespace shows as verified.
3. **User token.** Under **Account → Generate User Token**, create a token. Its username
   becomes `MAVEN_CENTRAL_USERNAME` and its password becomes `MAVEN_CENTRAL_PASSWORD`.
   Do not use the account login password.
4. **Signing key.** On a trusted machine, create a dedicated RSA 4096 key for releases,
   protect it with a passphrase, and publish the public key so Maven Central can check
   signatures:

   ```bash
   gpg --quick-generate-key "Neural Defend Releases <security@neuraldefend.com>" rsa4096 sign 2y
   gpg --keyserver keyserver.ubuntu.com --send-keys <KEY_ID>
   gpg --armor --export-secret-keys <KEY_ID> > signing-key.asc
   ```

   Store the full contents of `signing-key.asc` (including the `BEGIN`/`END` lines) as
   `MAVEN_CENTRAL_SIGNING_KEY` and the passphrase as `MAVEN_CENTRAL_SIGNING_PASSWORD`, then
   delete the exported file.
   Keep an offline backup of the key and a revocation certificate.
5. **Environment.** Create the GitHub environment `maven-central` with required company
   reviewers, self-review prevention, no administrator bypass, and a deployment-branch
   rule that allows only tags matching `java-v*` and `kotlin-v*`. Add the four secrets above to this
   environment, not to the repository.

Rotate the user token and signing key if a release manager leaves or a secret may have
leaked. Publish the new public key before the next release.

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
   - `dart-vX.Y.Z`
   - `java-vX.Y.Z`
   - `X.Y.Z` for Swift, matching `NeuroVerifyClient.sdkVersion` and the latest
     `packages/swift/CHANGELOG.md` entry
   - `kotlin-vX.Y.Z` (matches `VERSION_NAME` in `packages/kotlin/gradle.properties`)
7. Inspect the wheel/sdist, npm tarball, `dart pub publish --dry-run` file list, Java jars, or
   the Kotlin `central-bundle` artifact before approving the protected release job.
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
5. `dart-vX.Y.Z` after the commit is on the default branch
6. `java-vX.Y.Z` after the commit is on the default branch
7. `X.Y.Z` (Swift) after the commit is on the default branch
8. `kotlin-vX.Y.Z` after the commit is on the default branch

The Go tag uses the module path prefix so `go get` resolves the version from the public
module proxy. The Java tag builds and tests the SDK, then publishes signed artifacts to
Maven Central after approval in the protected `maven-central` environment, and creates a
GitHub Release. No registry approval step is required for Go; verify `go get` in a clean
module after the tag is pushed.

The Dart tag starts `release-dart.yml`, which tests the package, checks the tag against
`pubspec.yaml`, and publishes to pub.dev with a GitHub OIDC token after the `pub-dev`
environment reviewer approves. pub.dev versions cannot be deleted; a defective version can
only be retracted within seven days or superseded.

The Swift tag starts `release-swift.yml`, which checks the tag against
`NeuroVerifyClient.sdkVersion`, confirms the commit is on the default branch, runs the macOS
tests, resolves the package as a consumer, and creates the GitHub Release after the
`swift-release` environment reviewer approves. Swift Package Manager can install the tag as
soon as it is pushed, so run the dry run and every check before tagging. Never delete or move
a Swift tag; publish a new patch version instead.

The Kotlin tag starts `release-kotlin.yml`. The build job checks that the tag matches
`VERSION_NAME`, that the tagged commit is on the default branch, and that the Gradle
wrapper is genuine, then runs every check and builds an unsigned bundle. After the
`maven-central` environment reviewer approves, the publish job signs the bundle with GPG,
verifies and scans it, attests provenance, uploads it to the Central Portal with automatic
publishing, waits until the deployment reaches `PUBLISHED`, and creates a GitHub release
with the bundle attached. A manual run of the workflow only performs the build job (dry
run). Maven Central versions cannot be deleted or replaced; a defective version can only
be superseded.

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
5. Add the exact `neuraldefend` version to clean Dart and Flutter projects and confirm the
   pub.dev score page shows all expected platforms.
6. Resolve `com.neuraldefend:neuraldefend-sdk:X.Y.Z` from Maven Central in a clean Gradle
   or Maven project.
7. Add the exact Swift version to a clean Xcode app with
   `.package(url: "https://github.com/Neural-Defend/NeuralDefend-SDKs", exact: "X.Y.Z")`,
   build for an iOS Simulator, and confirm Swift Package Index lists the version.
8. Add `com.neuraldefend:neuraldefend:X.Y.Z` to a clean JVM Gradle project and
   `com.neuraldefend:neuraldefend-android:X.Y.Z` to a clean Android app, and confirm both
   resolve from Maven Central (new versions can take up to 30 minutes to appear).
9. Run approved staging smoke tests against the published artifacts.
10. Publish release notes, checksums, SBOMs, and provenance links.

Registry releases are immutable. If a defect is found, stop rollout and publish a patched
version; yank/deprecate the affected version only when necessary and document the reason.

