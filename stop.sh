#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BROKER_DIR="${ROOT_DIR}/broker"
BROKER_BIN="${BROKER_BIN:-${BROKER_DIR}/.venv/bin/broker}"

if [[ ! -x "${BROKER_BIN}" ]]; then
  if command -v broker >/dev/null 2>&1; then
    BROKER_BIN="$(command -v broker)"
  else
    echo "broker CLI not found. Nothing to stop." >&2
    exit 1
  fi
fi

set +e
"${BROKER_BIN}" daemon stop "$@"
status=$?
set -e

if [[ "${status}" -eq 3 ]]; then
  echo "broker-daemon is not running."
  exit 0
fi

exit "${status}"
