#!/usr/bin/env bash
# Retry a live staging command a few times. HTTP 503 from NeuroVerify is retryable
# and not billable; a single short outage should not fail the weekly smoke job.
set -euo pipefail

if [[ "$#" -lt 1 ]]; then
  echo "usage: retry_cmd.sh <command> [args...]" >&2
  exit 2
fi

attempts="${RETRY_ATTEMPTS:-3}"
delay="${RETRY_DELAY_SECONDS:-20}"

if ! [[ "$attempts" =~ ^[1-9][0-9]*$ ]]; then
  echo "RETRY_ATTEMPTS must be a positive integer" >&2
  exit 2
fi
if ! [[ "$delay" =~ ^[0-9]+$ ]]; then
  echo "RETRY_DELAY_SECONDS must be a non-negative integer" >&2
  exit 2
fi

i=1
while true; do
  if "$@"; then
    exit 0
  fi
  if (( i >= attempts )); then
    exit 1
  fi
  echo "Command failed (attempt ${i}/${attempts}); retrying in ${delay}s" >&2
  sleep "$delay"
  i=$((i + 1))
done
