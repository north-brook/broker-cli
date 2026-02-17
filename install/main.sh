#!/usr/bin/env bash
set -euo pipefail

# ─── Resolve script root ─────────────────────────────────────────────────────

SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [[ -L "${SCRIPT_SOURCE}" ]]; do
  SCRIPT_DIR="$(cd -P "$(dirname "${SCRIPT_SOURCE}")" && pwd)"
  SCRIPT_SOURCE="$(readlink "${SCRIPT_SOURCE}")"
  if [[ "${SCRIPT_SOURCE}" != /* ]]; then
    SCRIPT_SOURCE="${SCRIPT_DIR}/${SCRIPT_SOURCE}"
  fi
done
INSTALL_DIR="$(cd -P "$(dirname "${SCRIPT_SOURCE}")" && pwd)"
ROOT_DIR="$(cd -P "${INSTALL_DIR}/.." && pwd)"

# ─── Configuration paths ─────────────────────────────────────────────────────

BROKER_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}/broker"
BROKER_CONFIG_JSON="${BROKER_CONFIG_JSON:-${BROKER_CONFIG_HOME}/config.json}"
BROKER_STATE_HOME="${XDG_STATE_HOME:-${HOME}/.local/state}/broker"
BROKER_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/broker"
BROKER_SOURCE_DIR="${BROKER_SOURCE_DIR:-${BROKER_DATA_HOME}/source}"
BROKER_REPO="${BROKER_REPO:-https://github.com/north-brook/broker-cli.git}"

export PATH="/opt/homebrew/bin:/usr/local/bin:/home/linuxbrew/.linuxbrew/bin:${PATH}"

PYTHON_VERSION="${PYTHON_VERSION:-3.12}"
IB_CHANNEL="${BROKER_IB_CHANNEL:-stable}"
IB_INSTALL_DIR="${BROKER_IB_INSTALL_DIR:-/Applications/IB Gateway}"
IBC_RELEASE_TAG="${BROKER_IBC_RELEASE_TAG:-latest}"
IBC_INSTALL_DIR="${BROKER_IBC_INSTALL_DIR:-${BROKER_DATA_HOME}/ibc}"
BROKER_BIN_DIR="${BROKER_BIN_DIR:-${HOME}/.local/bin}"
LOG_DIR="$(mktemp -d /tmp/broker-install.XXXXXX)"
STEP_INDEX=0
STEP_TOTAL=0
INTERACTIVE=0
SELECTED_PROVIDER="ib"

export BROKER_CONFIG_HOME BROKER_CONFIG_JSON BROKER_STATE_HOME BROKER_DATA_HOME
export BROKER_SOURCE_DIR BROKER_REPO IBC_RELEASE_TAG IBC_INSTALL_DIR
export BROKER_RUNTIME_PID_FILE="${BROKER_STATE_HOME}/broker-daemon.pid"
export BROKER_RUNTIME_SOCKET_PATH="${BROKER_STATE_HOME}/broker.sock"
export BROKER_LOGGING_AUDIT_DB="${BROKER_STATE_HOME}/audit.db"
export BROKER_LOGGING_LOG_FILE="${BROKER_STATE_HOME}/broker.log"
export BROKER_IBC_PATH="${IBC_INSTALL_DIR}"
export BROKER_IBC_INI="${BROKER_IBC_PATH}/config.ini"
export BROKER_IBC_LOG_FILE="${BROKER_STATE_HOME}/logs/ibc-launch.log"
export BROKER_IB_SETTINGS_DIR="${BROKER_STATE_HOME}/ib-settings"

# Parse --provider flag (non-interactive alternative to provider selection)
for arg in "$@"; do
  case "${arg}" in
    --provider=*)
      SELECTED_PROVIDER="${arg#*=}"
      ;;
  esac
done

if [[ -t 1 ]]; then
  INTERACTIVE=1
  BOLD="$(printf '\033[1m')"
  DIM="$(printf '\033[2m')"
  BLUE="$(printf '\033[34m')"
  GREEN="$(printf '\033[32m')"
  YELLOW="$(printf '\033[33m')"
  RED="$(printf '\033[31m')"
  RESET="$(printf '\033[0m')"
else
  BOLD=""
  DIM=""
  BLUE=""
  GREEN=""
  YELLOW=""
  RED=""
  RESET=""
fi

# ─── Source helpers ───────────────────────────────────────────────────────────

INSTALL_STEPS_DIR="${ROOT_DIR}/install/steps"
source "${INSTALL_STEPS_DIR}/output.sh"
source "${INSTALL_STEPS_DIR}/bootstrap.sh"
source "${INSTALL_STEPS_DIR}/workspace.sh"
source "${INSTALL_STEPS_DIR}/broker.sh"
source "${INSTALL_STEPS_DIR}/runtime.sh"

if [[ ! -d "${ROOT_DIR}/daemon" || ! -d "${ROOT_DIR}/cli" || ! -d "${ROOT_DIR}/sdk" ]]; then
  ensure_source_checkout
fi

# ─── Calculate steps ─────────────────────────────────────────────────────────

normalize_selected_provider() {
  case "$(printf '%s' "${SELECTED_PROVIDER}" | tr '[:upper:]' '[:lower:]')" in
    ib|etrade) ;;
    *) SELECTED_PROVIDER="ib" ;;
  esac
}

normalize_selected_provider

# Install-only steps (no onboarding, no interactive provider selection)
# 1. Prepare dirs  2. Bootstrap tooling  3. Create config
# 4. IB Gateway (if ib)  5. IBC (if ib)  6. Python runtime
# 7. Python packages  8. E*Trade deps (if etrade)  9. Link CLI  10. Completions
STEP_TOTAL=7
if [[ "${SELECTED_PROVIDER}" == "ib" ]]; then
  STEP_TOTAL=$((STEP_TOTAL + 2))  # IB Gateway + IBC
fi
if [[ "${SELECTED_PROVIDER}" == "etrade" ]]; then
  STEP_TOTAL=$((STEP_TOTAL + 1))  # E*Trade deps
fi

# ─── Install ─────────────────────────────────────────────────────────────────

banner
run_step "Preparing broker config/state/data directories" prepare_broker_home
run_step "Bootstrapping system tooling (Homebrew, uv)" bootstrap_tooling
run_step "Creating broker config (${BROKER_CONFIG_JSON})" ensure_broker_config
if [[ "${SELECTED_PROVIDER}" == "ib" ]]; then
  run_step "Interactive Brokers Gateway setup" install_ib_app
  run_step "Installing IBC automation package" install_ibc
fi
run_step "Creating Python runtime" create_python_runtime
run_step "Installing broker Python packages" install_python_packages
if [[ "${SELECTED_PROVIDER}" == "etrade" ]]; then
  run_step "Installing E*Trade dependencies" install_etrade_dependencies
fi
run_step "Linking broker CLI command" bind_broker_command
run_step "Installing shell completions" install_shell_completions

# ─── Done ─────────────────────────────────────────────────────────────────────

rm -rf "${LOG_DIR}"

if [[ "${INTERACTIVE}" -eq 1 ]]; then
  echo ""
fi

echo "${GREEN}✔${RESET} Broker is installed."
echo ""
echo "${BLUE}→${RESET} Next: run ${BOLD}${BLUE}./setup.sh${RESET} to configure your broker credentials"
