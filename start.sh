#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BROKER_DIR="${ROOT_DIR}/broker"
BROKER_BIN="${BROKER_BIN:-${BROKER_DIR}/.venv/bin/broker}"
LAUNCH_IB="${BROKER_LAUNCH_IB:-1}"
IB_APP_PATH="${BROKER_IB_APP_PATH:-}"
IB_WAIT_SECONDS="${BROKER_IB_WAIT_SECONDS:-45}"

if [[ ! -x "${BROKER_BIN}" ]]; then
  if command -v broker >/dev/null 2>&1; then
    BROKER_BIN="$(command -v broker)"
  else
    echo "broker CLI not found. Run ./build.sh first." >&2
    exit 1
  fi
fi

LIVE=0
PAPER=0
HAS_GATEWAY=0
SHOW_HELP=0
PASSTHROUGH=()
ARGS=("$@")
for ((i = 0; i < ${#ARGS[@]}; i++)); do
  arg="${ARGS[i]}"
  case "${arg}" in
    --live)
      LIVE=1
      ;;
    --paper)
      PAPER=1
      ;;
    --launch-ib)
      LAUNCH_IB=1
      ;;
    --no-launch-ib)
      LAUNCH_IB=0
      ;;
    --ib-app-path)
      ((i += 1))
      if ((i >= ${#ARGS[@]})); then
        echo "Missing value for --ib-app-path." >&2
        exit 2
      fi
      IB_APP_PATH="${ARGS[i]}"
      ;;
    --ib-app-path=*)
      IB_APP_PATH="${arg#*=}"
      ;;
    --ib-wait)
      ((i += 1))
      if ((i >= ${#ARGS[@]})); then
        echo "Missing value for --ib-wait (seconds)." >&2
        exit 2
      fi
      IB_WAIT_SECONDS="${ARGS[i]}"
      ;;
    --ib-wait=*)
      IB_WAIT_SECONDS="${arg#*=}"
      ;;
    -h|--help)
      SHOW_HELP=1
      PASSTHROUGH+=("${arg}")
      ;;
    --gateway)
      HAS_GATEWAY=1
      PASSTHROUGH+=("${arg}")
      ((i += 1))
      if ((i >= ${#ARGS[@]})); then
        echo "Missing value for --gateway (expected HOST:PORT)." >&2
        exit 2
      fi
      PASSTHROUGH+=("${ARGS[i]}")
      ;;
    --gateway=*)
      HAS_GATEWAY=1
      PASSTHROUGH+=("${arg}")
      ;;
    *)
      PASSTHROUGH+=("${arg}")
      ;;
  esac
done

if [[ "${LIVE}" -eq 1 && "${PAPER}" -eq 1 ]]; then
  echo "Choose one mode: --live or --paper (not both)." >&2
  exit 2
fi

if [[ "${SHOW_HELP}" -eq 1 ]]; then
  echo "Wrapper options:"
  echo "  --live | --paper"
  echo "  --launch-ib | --no-launch-ib"
  echo "  --ib-app-path /path/to/App.app"
  echo "  --ib-wait <seconds>"
  echo
  echo "broker daemon start options:"
  "${BROKER_BIN}" daemon start --help
  exit 0
fi

case "${LAUNCH_IB,,}" in
  1|true|yes|on) LAUNCH_IB=1 ;;
  0|false|no|off) LAUNCH_IB=0 ;;
  *)
    echo "Invalid BROKER_LAUNCH_IB value '${LAUNCH_IB}', defaulting to 1."
    LAUNCH_IB=1
    ;;
esac

if ! [[ "${IB_WAIT_SECONDS}" =~ ^[0-9]+$ ]]; then
  echo "Invalid --ib-wait value '${IB_WAIT_SECONDS}' (must be integer seconds)." >&2
  exit 2
fi

detect_port() {
  local listeners="$1"
  shift
  local port
  for port in "$@"; do
    if printf '%s\n' "${listeners}" | grep -Eq "[:.]${port}[[:space:]].*LISTEN"; then
      echo "${port}"
      return 0
    fi
  done
  return 1
}

force_stop_existing_daemon() {
  local pid_file="${HOME}/.broker/broker-daemon.pid"
  local socket_file="${HOME}/.broker/broker.sock"

  "${BROKER_BIN}" daemon stop >/dev/null 2>&1 || true
  sleep 0.2

  if [[ -f "${pid_file}" ]]; then
    local pid
    pid="$(cat "${pid_file}" 2>/dev/null || true)"
    if [[ "${pid}" =~ ^[0-9]+$ ]] && kill -0 "${pid}" >/dev/null 2>&1; then
      local cmdline
      cmdline="$(ps -p "${pid}" -o command= 2>/dev/null || true)"
      if [[ "${cmdline}" == *"broker_daemon.daemon.server"* ]]; then
        echo "Daemon stop request timed out; sending SIGTERM to pid ${pid}."
        kill -TERM "${pid}" >/dev/null 2>&1 || true
        for _ in {1..30}; do
          if ! kill -0 "${pid}" >/dev/null 2>&1; then
            break
          fi
          sleep 0.1
        done
        if kill -0 "${pid}" >/dev/null 2>&1; then
          echo "Daemon still running; sending SIGKILL to pid ${pid}."
          kill -KILL "${pid}" >/dev/null 2>&1 || true
        fi
      fi
    fi
  fi

  if [[ -S "${socket_file}" ]]; then
    rm -f "${socket_file}" || true
  fi
  if [[ -f "${pid_file}" ]]; then
    rm -f "${pid_file}" || true
  fi
}

extract_gateway_port_from_args() {
  local endpoint=""
  local arg
  for ((j = 0; j < ${#PASSTHROUGH[@]}; j++)); do
    arg="${PASSTHROUGH[j]}"
    if [[ "${arg}" == --gateway=* ]]; then
      endpoint="${arg#*=}"
    elif [[ "${arg}" == --gateway ]]; then
      ((j += 1))
      endpoint="${PASSTHROUGH[j]:-}"
    else
      continue
    fi

    local port="${endpoint##*:}"
    if [[ "${port}" =~ ^[0-9]+$ ]]; then
      printf '%s\n' "${port}"
      return 0
    fi
  done
  return 1
}

any_port_listening() {
  local listeners="$1"
  shift
  local port
  for port in "$@"; do
    if printf '%s\n' "${listeners}" | grep -Eq "[:.]${port}[[:space:]].*LISTEN"; then
      return 0
    fi
  done
  return 1
}

wait_for_any_port() {
  local timeout_seconds="$1"
  shift
  local deadline=$((SECONDS + timeout_seconds))
  while ((SECONDS < deadline)); do
    local listeners
    listeners="$(lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null || true)"
    if any_port_listening "${listeners}" "$@"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

is_valid_gateway_app_bundle() {
  local app_path="$1"
  [[ -d "${app_path}" ]] || return 1
  local name
  name="$(basename "${app_path}")"
  case "${name}" in
    IB\ Gateway*.app)
      case "${name}" in
        *Installer.app|*Uninstaller.app) return 1 ;;
      esac
      return 0
      ;;
  esac
  return 1
}

resolve_ib_gateway_app_from_root() {
  local root="$1"
  [[ -d "${root}" ]] || return 1

  local install_prop="${root}/.install4j/install.prop"
  if [[ -f "${install_prop}" ]]; then
    local launcher0=""
    launcher0="$(sed -n 's/^launcher0=//p' "${install_prop}" | head -n 1)"
    if [[ -n "${launcher0}" ]]; then
      local app_path="${launcher0%/Contents/MacOS/JavaApplicationStub}"
      if is_valid_gateway_app_bundle "${app_path}"; then
        printf '%s\n' "${app_path}"
        return 0
      fi
    fi
  fi

  local response_varfile="${root}/.install4j/response.varfile"
  if [[ -f "${response_varfile}" ]]; then
    local exe_name=""
    exe_name="$(sed -n 's/^exeName=//p' "${response_varfile}" | head -n 1)"
    if [[ -n "${exe_name}" ]]; then
      local app_path="${root}/${exe_name}"
      if is_valid_gateway_app_bundle "${app_path}"; then
        printf '%s\n' "${app_path}"
        return 0
      fi
    fi
  fi

  local direct="${root}/IB Gateway.app"
  if is_valid_gateway_app_bundle "${direct}"; then
    printf '%s\n' "${direct}"
    return 0
  fi

  return 1
}

find_ib_app_path() {
  if [[ -n "${IB_APP_PATH}" ]]; then
    if is_valid_gateway_app_bundle "${IB_APP_PATH}"; then
      printf '%s\n' "${IB_APP_PATH}"
      return 0
    fi
    if app_path="$(resolve_ib_gateway_app_from_root "${IB_APP_PATH}")"; then
      printf '%s\n' "${app_path}"
      return 0
    fi
    return 1
  fi

  local app_path=""
  for app_path in "/Applications/IB Gateway.app" "${HOME}/Applications/IB Gateway.app"; do
    if is_valid_gateway_app_bundle "${app_path}"; then
      printf '%s\n' "${app_path}"
      return 0
    fi
  done

  local root=""
  for root in "/Applications/IB Gateway" "${HOME}/Applications/IB Gateway"; do
    if app_path="$(resolve_ib_gateway_app_from_root "${root}")"; then
      printf '%s\n' "${app_path}"
      return 0
    fi
  done

  return 1
}

maybe_launch_ib() {
  local -a target_ports=("$@")

  if [[ "${LAUNCH_IB}" -ne 1 ]]; then
    return 0
  fi

  local listeners
  listeners="$(lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null || true)"
  if any_port_listening "${listeners}" "${target_ports[@]}"; then
    return 0
  fi

  if [[ "$(uname -s)" != "Darwin" ]]; then
    return 0
  fi

  local app_path
  if ! app_path="$(find_ib_app_path)"; then
    echo "IB Gateway.app not found; unable to auto-launch Gateway."
    echo "Install IB Gateway, or pass --ib-app-path <path>."
    return 0
  fi

  echo "No IB API listener detected; launching $(basename "${app_path}")."
  if ! open -ga "${app_path}" >/dev/null 2>&1; then
    open -a "${app_path}" >/dev/null 2>&1 || true
  fi

  if wait_for_any_port "${IB_WAIT_SECONDS}" "${target_ports[@]}"; then
    echo "Detected IB API listener."
  else
    echo "Timed out waiting for IB API listener (${IB_WAIT_SECONDS}s)."
  fi
}

read_daemon_pid() {
  local pid_file="${HOME}/.broker/broker-daemon.pid"
  if [[ ! -f "${pid_file}" ]]; then
    return 1
  fi
  local pid
  pid="$(cat "${pid_file}" 2>/dev/null || true)"
  if [[ "${pid}" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "${pid}"
    return 0
  fi
  return 1
}

is_broker_daemon_pid_running() {
  local pid="$1"
  if ! kill -0 "${pid}" >/dev/null 2>&1; then
    return 1
  fi
  local cmdline
  cmdline="$(ps -p "${pid}" -o command= 2>/dev/null || true)"
  [[ "${cmdline}" == *"broker_daemon.daemon.server"* ]]
}

MODE="auto"
if [[ "${LIVE}" -eq 1 ]]; then
  MODE="live"
elif [[ "${PAPER}" -eq 1 ]]; then
  MODE="paper"
fi

EXPLICIT_GATEWAY_PORT=""
if GATEWAY_PORT="$(extract_gateway_port_from_args)"; then
  EXPLICIT_GATEWAY_PORT="${GATEWAY_PORT}"
fi

TARGET_PORTS=()
if [[ -n "${EXPLICIT_GATEWAY_PORT}" ]]; then
  TARGET_PORTS=("${EXPLICIT_GATEWAY_PORT}")
elif [[ "${MODE}" == "paper" ]]; then
  TARGET_PORTS=(4002)
elif [[ "${MODE}" == "live" ]]; then
  TARGET_PORTS=(4001)
else
  TARGET_PORTS=(4002 4001)
fi

maybe_launch_ib "${TARGET_PORTS[@]}"

START_ARGS=("${PASSTHROUGH[@]}")
if [[ "${HAS_GATEWAY}" -eq 0 ]]; then
  LISTENERS="$(lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null || true)"
  DETECTED_PORT=""
  case "${MODE}" in
    paper)
      DETECTED_PORT="$(detect_port "${LISTENERS}" 4002 || true)"
      ;;
    live)
      DETECTED_PORT="$(detect_port "${LISTENERS}" 4001 || true)"
      ;;
    *)
      DETECTED_PORT="$(detect_port "${LISTENERS}" 4002 4001 || true)"
      ;;
  esac

  if [[ -n "${DETECTED_PORT}" ]]; then
    START_ARGS+=(--gateway "127.0.0.1:${DETECTED_PORT}")
  elif [[ "${MODE}" == "paper" || "${MODE}" == "auto" ]]; then
    START_ARGS+=(--paper)
  fi
fi

PRE_STATUS_JSON="$("${BROKER_BIN}" --json daemon status 2>/dev/null || true)"
if [[ -n "${PRE_STATUS_JSON}" && "${PRE_STATUS_JSON}" == *'"connected":false'* ]]; then
  PRE_PORT="$(printf '%s' "${PRE_STATUS_JSON}" | sed -n 's/.*"port":\([0-9][0-9]*\).*/\1/p')"
  echo "Existing daemon is running but disconnected on localhost:${PRE_PORT}; restarting."
  force_stop_existing_daemon
elif [[ -z "${PRE_STATUS_JSON}" || "${PRE_STATUS_JSON}" == *'"code":"DAEMON_NOT_RUNNING"'* ]]; then
  if DAEMON_PID="$(read_daemon_pid)"; then
    if is_broker_daemon_pid_running "${DAEMON_PID}"; then
      echo "Found stale daemon process pid ${DAEMON_PID} without a healthy socket; restarting."
      force_stop_existing_daemon
    fi
  fi
fi

echo "Starting broker daemon with: ${BROKER_BIN} daemon start ${START_ARGS[*]}"
"${BROKER_BIN}" daemon start "${START_ARGS[@]}"

echo "Daemon status:"
STATUS_JSON="$("${BROKER_BIN}" --json daemon status 2>/dev/null || true)"
if [[ -n "${STATUS_JSON}" ]]; then
  echo "${STATUS_JSON}"
  if [[ "${STATUS_JSON}" == *'"connected":false'* ]]; then
    PORT="$(printf '%s' "${STATUS_JSON}" | sed -n 's/.*"port":\([0-9][0-9]*\).*/\1/p')"
    echo
    echo "IB is not reachable on localhost:${PORT}."
    echo "Start IB Gateway and enable API socket access, or pass --gateway HOST:PORT."
    echo "Common Gateway ports: paper/live = 4002/4001."
    echo "If risk_halted=true after reconnect, run: ${BROKER_BIN} resume"
  fi
else
  "${BROKER_BIN}" daemon status
fi
