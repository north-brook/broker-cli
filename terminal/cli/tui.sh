#!/usr/bin/env bash
set -euo pipefail

# nb run / nb (default) — TUI launcher.
# Parses daemon vs terminal args, boots broker + agents, then exec's bun.
# Sourced environment: ROOT_DIR, and _lib.sh helpers.

if [[ ! -x "${ROOT_DIR}/broker/start.sh" ]]; then
  echo "broker/start.sh not found or not executable at ${ROOT_DIR}/broker/start.sh" >&2
  exit 1
fi
if [[ ! -f "${ROOT_DIR}/terminal/src/main.tsx" ]]; then
  echo "terminal entrypoint not found at ${ROOT_DIR}/terminal/src/main.tsx" >&2
  exit 1
fi
if ! command -v bun >/dev/null 2>&1; then
  echo "bun is required to launch the terminal. Run ./install.sh first." >&2
  exit 1
fi

load_northbrook_secrets

INTERACTIVE=0
if [[ -t 1 ]]; then
  INTERACTIVE=1
  BLUE="$(printf '\033[34m')"
  GREEN="$(printf '\033[32m')"
  RED="$(printf '\033[31m')"
  RESET="$(printf '\033[0m')"
else
  BLUE=""
  GREEN=""
  RED=""
  RESET=""
fi

run_with_spinner() {
  local label="$1"
  local log_file="$2"
  shift 2

  if [[ "${INTERACTIVE}" -eq 1 ]]; then
    local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local frame_index=0
    "$@" >"${log_file}" 2>&1 &
    local pid=$!

    while kill -0 "${pid}" >/dev/null 2>&1; do
      printf "\r  ${BLUE}%s${RESET} %s" "${frames[frame_index]}" "${label}"
      frame_index=$(((frame_index + 1) % ${#frames[@]}))
      sleep 0.1
    done

    local rc
    if wait "${pid}"; then
      rc=0
    else
      rc=$?
    fi

    if [[ "${rc}" -eq 0 ]]; then
      printf "\r  ${GREEN}ok${RESET} %s\n" "${label}"
      return 0
    fi

    printf "\r  ${RED}failed${RESET} %s\n" "${label}" >&2
    return "${rc}"
  fi

  if "$@" >"${log_file}" 2>&1; then
    return 0
  fi
  return 1
}

daemon_args=()
terminal_args=()
has_ib_wait=0
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  arg="${args[i]}"
  case "${arg}" in
    --live|--paper|--launch-ib|--no-launch-ib)
      daemon_args+=("${arg}")
      ;;
    --gateway|--ib-app-path|--ib-wait)
      if [[ "${arg}" == "--ib-wait" ]]; then
        has_ib_wait=1
      fi
      daemon_args+=("${arg}")
      ((i += 1))
      if ((i >= ${#args[@]})); then
        echo "Missing value for ${arg}." >&2
        exit 2
      fi
      daemon_args+=("${args[i]}")
      ;;
    --gateway=*|--ib-app-path=*|--ib-wait=*)
      if [[ "${arg}" == --ib-wait=* ]]; then
        has_ib_wait=1
      fi
      daemon_args+=("${arg}")
      ;;
    --daemon-help)
      exec "${ROOT_DIR}/broker/start.sh" --help
      ;;
    *)
      terminal_args+=("${arg}")
      ;;
  esac
done

if ! has_explicit_gateway_or_mode "${daemon_args[@]}"; then
  daemon_args+=("$(default_daemon_mode_arg)")
fi

# Keep TUI startup responsive by default; callers can still override via --ib-wait.
if [[ "${has_ib_wait}" -eq 0 ]]; then
  daemon_args+=("--ib-wait=0")
fi

for arg in "${terminal_args[@]}"; do
  if [[ "${arg}" == "-h" || "${arg}" == "--help" ]]; then
    cd "${ROOT_DIR}/terminal"
    exec bun src/main.tsx "${terminal_args[@]}"
  fi
done

daemon_log="$(mktemp /tmp/northbrook-nb-daemon.XXXXXX)"
if ! run_with_spinner "Starting broker daemon" "${daemon_log}" run_broker_start "${daemon_args[@]}"; then
  echo "Failed to initialize broker daemon." >&2
  tail -n 40 "${daemon_log}" >&2 || true
  rm -f "${daemon_log}"
  exit 1
fi
rm -f "${daemon_log}"

agents_log="$(mktemp /tmp/northbrook-nb-agents.XXXXXX)"
if ! run_with_spinner "Starting agents daemon" "${agents_log}" run_agents_start; then
  echo "Failed to initialize agents daemon." >&2
  tail -n 40 "${agents_log}" >&2 || true
  rm -f "${agents_log}"
  exit 1
fi
rm -f "${agents_log}"

cd "${ROOT_DIR}/terminal"
exec bun src/main.tsx "${terminal_args[@]}"
