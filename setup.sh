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
ROOT_DIR="$(cd -P "$(dirname "${SCRIPT_SOURCE}")" && pwd)"

# ─── Source common helpers ───────────────────────────────────────────────────

INSTALL_STEPS_DIR="${ROOT_DIR}/install/steps"
source "${INSTALL_STEPS_DIR}/common.sh"

# ─── Configuration paths ─────────────────────────────────────────────────────

init_broker_common_paths
IB_CHANNEL="${BROKER_IB_CHANNEL:-stable}"
IB_INSTALL_DIR="${BROKER_IB_INSTALL_DIR:-/Applications/IB Gateway}"
IBC_RELEASE_TAG="${BROKER_IBC_RELEASE_TAG:-latest}"
IBC_INSTALL_DIR="${BROKER_IBC_INSTALL_DIR:-${BROKER_DATA_HOME}/ibc}"
INSTALL_IB_APP="${INSTALL_IB_APP:-1}"
LOG_DIR="$(mktemp -d /tmp/broker-setup.XXXXXX)"
STEP_INDEX=0
STEP_TOTAL=0

export BROKER_CONFIG_HOME BROKER_CONFIG_JSON BROKER_STATE_HOME BROKER_DATA_HOME
export IBC_RELEASE_TAG IBC_INSTALL_DIR
export BROKER_IBC_PATH="${IBC_INSTALL_DIR}"
export BROKER_IBC_INI="${BROKER_IBC_PATH}/config.ini"
export BROKER_IBC_LOG_FILE="${BROKER_STATE_HOME}/logs/ibc-launch.log"
export BROKER_IB_SETTINGS_DIR="${BROKER_STATE_HOME}/ib-settings"

cleanup_setup_tmp() {
  rm -rf "${LOG_DIR}" >/dev/null 2>&1 || true
}

trap cleanup_setup_tmp EXIT

init_broker_terminal "tty-io"

# ─── Source helpers ───────────────────────────────────────────────────────────

source "${INSTALL_STEPS_DIR}/output.sh"
source "${INSTALL_STEPS_DIR}/secrets.sh"
source "${INSTALL_STEPS_DIR}/onboarding.sh"
source "${INSTALL_STEPS_DIR}/broker.sh"
source "${INSTALL_STEPS_DIR}/runtime.sh"

# ─── Guards ───────────────────────────────────────────────────────────────────

if [[ "${INTERACTIVE}" -eq 0 ]]; then
  printf "${RED}Error:${RESET} setup requires terminal input/output access.\n" >&2
  printf "Run this command in a local terminal session.\n" >&2
  exit 1
fi

if [[ ! -f "${BROKER_CONFIG_JSON}" ]]; then
  printf "${RED}Error:${RESET} broker config not found at ${BROKER_CONFIG_JSON}\n" >&2
  printf "Run ${BOLD}./install.sh${RESET} first.\n" >&2
  exit 1
fi

# ─── Provider selection ──────────────────────────────────────────────────────

echo ""
echo "${BOLD}Broker Setup${RESET}"
echo ""

select_broker_provider
normalize_selected_provider() {
  case "$(printf '%s' "${SELECTED_PROVIDER}" | tr '[:upper:]' '[:lower:]')" in
    ib|etrade) ;;
    *) SELECTED_PROVIDER="ib" ;;
  esac
}
normalize_selected_provider

# ─── Provider-specific install ──────────────────────────────────────────────

if [[ "${SELECTED_PROVIDER}" == "ib" ]]; then
  STEP_TOTAL=2
  run_step "Interactive Brokers Gateway setup" install_ib_app
  run_step "Installing IBC automation package" install_ibc
else
  STEP_TOTAL=1
  run_step "Installing E*Trade dependencies" install_etrade_dependencies
fi

# ─── Onboarding ──────────────────────────────────────────────────────────────

if [[ "${SELECTED_PROVIDER}" == "ib" ]]; then
  echo ""
  run_onboarding_wizard
else
  echo ""
  run_etrade_onboarding_wizard
  echo ""
  run_etrade_oauth_flow
fi

# ─── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo "${GREEN}✔${RESET} Setup complete."
echo ""
echo "${BLUE}→${RESET} Try: ${BOLD}${BLUE}broker daemon start${RESET}"
