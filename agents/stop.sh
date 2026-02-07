#!/usr/bin/env bash
set -euo pipefail

AGENTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NORTHBROOK_HOME="${NORTHBROOK_HOME:-${HOME}/.northbrook}"
AGENTS_HOME="${NORTHBROOK_AGENTS_HOME:-${NORTHBROOK_HOME}/agents}"
PID_FILE="${NORTHBROOK_AGENTS_PID_FILE:-${AGENTS_HOME}/agents-daemon.pid}"

if [[ ! -f "${PID_FILE}" ]]; then
  echo '{"ok":true,"running":false}'
  exit 0
fi

pid="$(cat "${PID_FILE}" 2>/dev/null || true)"
if [[ ! "${pid}" =~ ^[0-9]+$ ]]; then
  rm -f "${PID_FILE}"
  echo '{"ok":true,"running":false}'
  exit 0
fi

if ! kill -0 "${pid}" >/dev/null 2>&1; then
  rm -f "${PID_FILE}"
  echo '{"ok":true,"running":false}'
  exit 0
fi

kill -TERM "${pid}" >/dev/null 2>&1 || true
for _ in {1..40}; do
  if ! kill -0 "${pid}" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

if kill -0 "${pid}" >/dev/null 2>&1; then
  kill -KILL "${pid}" >/dev/null 2>&1 || true
fi

rm -f "${PID_FILE}"

if command -v bun >/dev/null 2>&1; then
  exec bun "${AGENTS_DIR}/src/status-cli.ts" --json
fi

echo '{"ok":true,"running":false}'
