#!/usr/bin/env bash
set -euo pipefail

# Resolve script root.
SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [[ -L "${SCRIPT_SOURCE}" ]]; do
  SCRIPT_DIR="$(cd -P "$(dirname "${SCRIPT_SOURCE}")" && pwd)"
  SCRIPT_SOURCE="$(readlink "${SCRIPT_SOURCE}")"
  if [[ "${SCRIPT_SOURCE}" != /* ]]; then
    SCRIPT_SOURCE="${SCRIPT_DIR}/${SCRIPT_SOURCE}"
  fi
done
ROOT_DIR="$(cd -P "$(dirname "${SCRIPT_SOURCE}")" && pwd)"

# Shared helpers.
INSTALL_STEPS_DIR="${ROOT_DIR}/install/steps"
source "${INSTALL_STEPS_DIR}/common.sh"

# Paths aligned with install/main.sh + setup.sh defaults.
init_broker_common_paths
BROKER_SOURCE_DIR="${BROKER_SOURCE_DIR:-${BROKER_DATA_HOME}/source}"
BROKER_WRAPPER_PATH="${BROKER_BIN_DIR}/broker"
BROKER_GLOBAL_LINK="/usr/local/bin/broker"
BROKER_IB_INSTALL_DIR="${BROKER_IB_INSTALL_DIR:-/Applications/IB Gateway}"

ZDOTDIR_PATH="${ZDOTDIR:-${HOME}}"
ZSH_COMPLETION_FILE="${HOME}/.zfunc/_broker"
OMZ_COMPLETION_FILE="${HOME}/.oh-my-zsh/custom/completions/_broker"
BASH_COMPLETION_FILE="${HOME}/.local/share/bash-completion/completions/broker"
FISH_COMPLETION_FILE="${HOME}/.config/fish/completions/broker.fish"

init_broker_terminal "stdio"

YES=0
KEEP_IB_APP=0
KEEP_SOURCE=0

usage() {
  cat <<EOF
Usage: broker uninstall [OPTIONS]

Remove broker-cli artifacts created by install/setup:
  - CLI wrapper + global symlink
  - Shell completions
  - Broker config/state/data directories
  - Local Python runtime (.venv)
  - E*Trade tokens and setup artifacts
  - Optional: IB Gateway app installed by setup

Options:
  -y, --yes          Skip confirmation prompt
      --keep-ib-app  Keep IB Gateway app at ${BROKER_IB_INSTALL_DIR}
      --keep-source  Keep source checkout at ${BROKER_SOURCE_DIR}
  -h, --help         Show this help
EOF
}

lowercase() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

fail() {
  printf "%bError:%b %s\n" "${RED}" "${RESET}" "$1" >&2
  exit 1
}

warn() {
  printf "%bWarning:%b %s\n" "${YELLOW}" "${RESET}" "$1"
}

info() {
  printf "%b•%b %s\n" "${BLUE}" "${RESET}" "$1"
}

success() {
  printf "%b✔%b %s\n" "${GREEN}" "${RESET}" "$1"
}

path_exists() {
  local path="$1"
  [[ -e "${path}" || -L "${path}" ]]
}

remove_path() {
  local path="$1"
  local label="$2"
  local allow_sudo="${3:-0}"

  if ! path_exists "${path}"; then
    return 0
  fi

  if rm -rf -- "${path}" >/dev/null 2>&1; then
    info "Removed ${label}: ${path}"
    return 0
  fi

  if [[ "${allow_sudo}" -eq 1 && "${INTERACTIVE}" -eq 1 ]] && command -v sudo >/dev/null 2>&1; then
    if sudo -p "broker uninstall needs admin access to remove ${path}. Password: " rm -rf -- "${path}"; then
      info "Removed ${label}: ${path}"
      return 0
    fi
  fi

  warn "Could not remove ${label}: ${path}"
  return 0
}

remove_if_empty() {
  local path="$1"
  if [[ -d "${path}" ]] && [[ -z "$(ls -A "${path}" 2>/dev/null || true)" ]]; then
    rmdir "${path}" >/dev/null 2>&1 || true
  fi
}

resolve_realpath() {
  local path="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "${path}" <<'PY'
import sys
from pathlib import Path

print(Path(sys.argv[1]).expanduser().resolve(strict=False))
PY
    return 0
  fi
  printf '%s\n' "${path}"
}

resolve_link_target() {
  local link_path="$1"
  if [[ ! -L "${link_path}" ]]; then
    return 1
  fi

  local target=""
  target="$(readlink "${link_path}" 2>/dev/null || true)"
  [[ -n "${target}" ]] || return 1

  if [[ "${target}" != /* ]]; then
    target="$(cd -P "$(dirname "${link_path}")" && pwd)/${target}"
  fi
  resolve_realpath "${target}"
}

remove_managed_global_link() {
  if [[ ! -L "${BROKER_GLOBAL_LINK}" ]]; then
    return 0
  fi

  local wrapper_real=""
  wrapper_real="$(resolve_realpath "${BROKER_WRAPPER_PATH}")"
  local link_target_real=""
  link_target_real="$(resolve_link_target "${BROKER_GLOBAL_LINK}" || true)"

  if [[ -n "${link_target_real}" && "${link_target_real}" == "${wrapper_real}" ]]; then
    remove_path "${BROKER_GLOBAL_LINK}" "global broker symlink" 1
  fi
}

kill_pid_gracefully() {
  local pid="$1"
  if ! [[ "${pid}" =~ ^[0-9]+$ ]]; then
    return 0
  fi
  if ! kill -0 "${pid}" >/dev/null 2>&1; then
    return 0
  fi

  kill -TERM "${pid}" >/dev/null 2>&1 || true
  for _ in {1..30}; do
    if ! kill -0 "${pid}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done
  kill -KILL "${pid}" >/dev/null 2>&1 || true
}

stop_daemons() {
  if [[ -x "${ROOT_DIR}/stop.sh" ]]; then
    "${ROOT_DIR}/stop.sh" >/dev/null 2>&1 || true
  fi

  local pid_file="${BROKER_STATE_HOME}/broker-daemon.pid"
  if [[ -f "${pid_file}" ]]; then
    local pid=""
    pid="$(cat "${pid_file}" 2>/dev/null || true)"
    kill_pid_gracefully "${pid}"
  fi

  if command -v pgrep >/dev/null 2>&1; then
    local pid=""
    while IFS= read -r pid; do
      kill_pid_gracefully "${pid}"
    done < <(pgrep -f "broker_daemon.daemon.server" || true)

    while IFS= read -r pid; do
      kill_pid_gracefully "${pid}"
    done < <(pgrep -f "ibcstart.sh" || true)
  fi
}

print_target_plan() {
  printf "%bThis will remove:%b\n" "${BOLD}" "${RESET}"
  printf "  - %s\n" "${BROKER_WRAPPER_PATH}"
  printf "  - ${BROKER_GLOBAL_LINK} (if it points to broker-cli wrapper)"
  printf "  - ${ZSH_COMPLETION_FILE}"
  printf "  - ${OMZ_COMPLETION_FILE}"
  printf "  - ${BASH_COMPLETION_FILE}"
  printf "  - ${FISH_COMPLETION_FILE}"
  printf "  - ${BROKER_CONFIG_HOME}"
  printf "  - ${BROKER_STATE_HOME}"
  printf "  - ${BROKER_DATA_HOME}"
  printf "  - ${ROOT_DIR}/.venv"
  if [[ "${KEEP_SOURCE}" -eq 0 ]]; then
    printf "  - ${BROKER_SOURCE_DIR} (if outside ${BROKER_DATA_HOME})\n"
  fi
  if [[ "${KEEP_IB_APP}" -eq 0 ]]; then
    printf "  - ${BROKER_IB_INSTALL_DIR} (and .app variant)\n"
  fi
  printf "%bNote:%b shared system tooling installed by Homebrew (Homebrew/git/uv) is not removed.\n" "${DIM}" "${RESET}"
}

confirm_uninstall() {
  if [[ "${YES}" -eq 1 ]]; then
    return 0
  fi

  if [[ "${INTERACTIVE}" -eq 0 ]]; then
    fail "Non-interactive session detected. Re-run with --yes to confirm uninstall."
  fi

  print_target_plan
  printf "\n"
  local response=""
  read -r -p "Proceed with full uninstall? [y/N]: " response
  case "$(lowercase "${response}")" in
    y|yes)
      ;;
    *)
      printf "Uninstall cancelled.\n"
      exit 0
      ;;
  esac
}

for arg in "$@"; do
  case "${arg}" in
    -y|--yes)
      YES=1
      ;;
    --keep-ib-app)
      KEEP_IB_APP=1
      ;;
    --keep-source)
      KEEP_SOURCE=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      fail "Unknown option: ${arg}"
      ;;
  esac
done

confirm_uninstall

printf "%bBroker Uninstall%b\n" "${BOLD}" "${RESET}"
printf "\n"

stop_daemons
success "Stopped broker-related background processes."

remove_path "${BROKER_WRAPPER_PATH}" "broker wrapper"
remove_managed_global_link

remove_path "${ZSH_COMPLETION_FILE}" "zsh completion"
remove_path "${OMZ_COMPLETION_FILE}" "oh-my-zsh completion"
remove_path "${BASH_COMPLETION_FILE}" "bash completion"
remove_path "${FISH_COMPLETION_FILE}" "fish completion"
rm -f "${ZDOTDIR_PATH}/.zcompdump"* >/dev/null 2>&1 || true
remove_if_empty "${HOME}/.zfunc"
remove_if_empty "${HOME}/.oh-my-zsh/custom/completions"
remove_if_empty "${HOME}/.local/share/bash-completion/completions"
remove_if_empty "${HOME}/.config/fish/completions"

remove_path "${BROKER_CONFIG_HOME}" "broker config home"
remove_path "${BROKER_STATE_HOME}" "broker state home"
remove_path "${BROKER_DATA_HOME}" "broker data home"
remove_path "${ROOT_DIR}/.venv" "local Python runtime"

if [[ "${KEEP_SOURCE}" -eq 0 ]]; then
  case "${BROKER_SOURCE_DIR}" in
    "${BROKER_DATA_HOME}"|\
"${BROKER_DATA_HOME}/"*)
      # Already removed with BROKER_DATA_HOME.
      ;;
    *)
      local_source_real="$(resolve_realpath "${BROKER_SOURCE_DIR}")"
      local_root_real="$(resolve_realpath "${ROOT_DIR}")"
      if [[ "${local_source_real}" == "${local_root_real}" ]]; then
        warn "Skipping source removal for active install directory: ${BROKER_SOURCE_DIR}"
        warn "Remove it manually if you also want to delete this checkout."
      else
        remove_path "${BROKER_SOURCE_DIR}" "broker source checkout"
      fi
      ;;
  esac
fi

if [[ "${KEEP_IB_APP}" -eq 0 ]]; then
  remove_path "${BROKER_IB_INSTALL_DIR}" "IB Gateway install" 1
  if [[ "${BROKER_IB_INSTALL_DIR}" != *.app ]]; then
    remove_path "${BROKER_IB_INSTALL_DIR}.app" "IB Gateway app bundle" 1
  fi
fi

remove_if_empty "${BROKER_BIN_DIR}"

printf "\n"
success "Uninstall complete."
printf "%bNext:%b restart your shell so PATH/completion cache is refreshed.\n" "${BLUE}" "${RESET}"
