#!/usr/bin/env bash
# Retry a live staging smoke command. Transient NeuroVerify HTTP 500/503
# responses should not fail the weekly job on the first attempt; a persistent
# outage still fails after ATTEMPTS.
set -u

usage() {
  echo "usage: retry-smoke.sh ATTEMPTS DELAY_SECONDS -- COMMAND [ARGS...]" >&2
  exit 2
}

if [[ $# -lt 4 ]]; then
  usage
fi

attempts=$1
delay=$2
shift 2

if [[ ! "$attempts" =~ ^[1-9][0-9]*$ ]] || [[ ! "$delay" =~ ^[0-9]+$ ]]; then
  usage
fi
if [[ "$1" != "--" ]]; then
  usage
fi
shift
if [[ $# -lt 1 ]]; then
  usage
fi

status=1
for ((i = 1; i <= attempts; i++)); do
  "$@"
  status=$?
  if [[ "$status" -eq 0 ]]; then
    exit 0
  fi
  if [[ "$i" -eq "$attempts" ]]; then
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
      echo "::error::Command failed after ${attempts} attempt(s): $*" >&2
    else
      echo "Command failed after ${attempts} attempt(s): $*" >&2
    fi
    exit "$status"
  fi
  echo "Command failed on attempt ${i}/${attempts}; retrying in ${delay}s." >&2
  sleep "$delay"
done
exit "$status"
