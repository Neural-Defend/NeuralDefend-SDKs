#!/usr/bin/env bash
# Verifies the committed Gradle wrapper against checksums published by gradle.org and
# requires the distribution download itself to be pinned by SHA-256.
set -euo pipefail

cd "$(dirname "$0")/.."
properties="gradle/wrapper/gradle-wrapper.properties"

url="$(sed -n 's/^distributionUrl=//p' "$properties" | sed 's/\\:/:/g')"
pinned="$(sed -n 's/^distributionSha256Sum=//p' "$properties")"
version="$(sed -E -n 's#^https://services\.gradle\.org/distributions/gradle-([0-9][0-9A-Za-z.-]*)-(bin|all)\.zip$#\1#p' <<<"$url")"

if [[ -z "$version" ]]; then
  echo "::error::$properties must download an official distribution from services.gradle.org (found '$url')." >&2
  exit 1
fi
if [[ ! "$pinned" =~ ^[0-9a-f]{64}$ ]]; then
  echo "::error::$properties must pin distributionSha256Sum." >&2
  exit 1
fi

published_distribution="$(curl --fail --silent --show-error --location "${url}.sha256")"
published_wrapper="$(curl --fail --silent --show-error --location "https://services.gradle.org/distributions/gradle-${version}-wrapper.jar.sha256")"
actual_wrapper="$(sha256sum gradle/wrapper/gradle-wrapper.jar | cut -d' ' -f1)"

if [[ "$pinned" != "$published_distribution" ]]; then
  echo "::error::distributionSha256Sum does not match the checksum gradle.org publishes for Gradle ${version}." >&2
  exit 1
fi
if [[ "$actual_wrapper" != "$published_wrapper" ]]; then
  echo "::error::gradle-wrapper.jar does not match the official Gradle ${version} wrapper." >&2
  exit 1
fi
echo "Gradle ${version} wrapper and distribution checksums match gradle.org."
