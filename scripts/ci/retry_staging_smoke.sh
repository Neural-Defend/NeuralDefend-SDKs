#!/usr/bin/env bash
# Re-run staging smoke commands when the staging API has a transient outage.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: retry_staging_smoke.sh <command...>" >&2
  exit 2
fi

attempts="${STAGING_SMOKE_ATTEMPTS:-3}"
delay="${STAGING_SMOKE_RETRY_DELAY_SECONDS:-30}"

for ((i = 1; i <= attempts; i++)); do
  if "$@"; then
    exit 0
  fi
  if ((i < attempts)); then
    echo "Staging smoke attempt ${i}/${attempts} failed; retrying in ${delay}s..." >&2
    sleep "$delay"
  fi
done

echo "Staging smoke failed after ${attempts} attempt(s)." >&2
exit 1
