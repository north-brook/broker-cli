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

# ─── Configuration paths ─────────────────────────────────────────────────────

BROKER_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}/broker"
BROKER_CONFIG_JSON="${BROKER_CONFIG_JSON:-${BROKER_CONFIG_HOME}/config.json}"
BROKER_STATE_HOME="${XDG_STATE_HOME:-${HOME}/.local/state}/broker"
BROKER_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/broker"
BROKER_BIN_DIR="${BROKER_BIN_DIR:-${HOME}/.local/bin}"

export BROKER_CONFIG_HOME BROKER_CONFIG_JSON BROKER_STATE_HOME BROKER_DATA_HOME

if [[ -t 1 ]]; then
  BOLD="$(printf '\033[1m')"
  DIM="$(printf '\033[2m')"
  BLUE="$(printf '\033[34m')"
  GREEN="$(printf '\033[32m')"
  YELLOW="$(printf '\033[33m')"
  RED="$(printf '\033[31m')"
  RESET="$(printf '\033[0m')"
else
  BOLD="" DIM="" BLUE="" GREEN="" YELLOW="" RED="" RESET=""
fi

INTERACTIVE=0
[[ -t 0 && -t 1 ]] && INTERACTIVE=1

# ─── Source helpers ───────────────────────────────────────────────────────────

INSTALL_STEPS_DIR="${ROOT_DIR}/install/steps"
source "${INSTALL_STEPS_DIR}/secrets.sh"
source "${INSTALL_STEPS_DIR}/onboarding.sh"

# ─── Guards ───────────────────────────────────────────────────────────────────

if [[ "${INTERACTIVE}" -eq 0 ]]; then
  printf "${RED}Error:${RESET} setup requires an interactive terminal.\n" >&2
  printf "Run this command directly (not via pipe).\n" >&2
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
