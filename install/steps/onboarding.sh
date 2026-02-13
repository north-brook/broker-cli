# shellcheck shell=bash

read_secret_input() {
  local prompt="$1"
  local __resultvar="$2"
  local secret=""

  printf "%s" "${prompt}"
  stty -echo
  IFS= read -r secret || true
  stty echo
  printf "\n"

  printf -v "${__resultvar}" '%s' "${secret}"
}

parse_yes_no_default_no() {
  local raw="$1"
  local lowered
  lowered="$(printf '%s' "${raw}" | tr '[:upper:]' '[:lower:]')"
  case "${lowered}" in
    y|yes|1|true|on)
      printf '%s\n' "true"
      return 0
      ;;
    n|no|0|false|off|"")
      printf '%s\n' "false"
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

read_configured_provider() {
  if ! command -v python3 >/dev/null 2>&1; then
    printf '%s\n' "ib"
    return 0
  fi

  python3 - "${BROKER_CONFIG_JSON}" <<'PY'
import json
import sys
from pathlib import Path

config_path = Path(sys.argv[1]).expanduser()
provider = "ib"

if config_path.exists():
    try:
        loaded = json.loads(config_path.read_text(encoding="utf-8"))
        if isinstance(loaded, dict):
            broker_cfg = loaded.get("broker")
            if isinstance(broker_cfg, dict):
                raw_provider = broker_cfg.get("provider")
                if isinstance(raw_provider, str):
                    value = raw_provider.strip().lower()
                    if value in {"ib", "etrade"}:
                        provider = value
    except Exception:
        provider = "ib"

print(provider)
PY
}

save_selected_provider() {
  local provider="$1"

  if [[ "${provider}" != "ib" && "${provider}" != "etrade" ]]; then
    provider="ib"
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    fail "python3 is required to update ${BROKER_CONFIG_JSON}."
  fi

  BROKER_SELECTED_PROVIDER="${provider}" python3 - "${BROKER_CONFIG_JSON}" <<'PY'
import json
import os
import sys
from pathlib import Path

config_path = Path(sys.argv[1]).expanduser()
config_path.parent.mkdir(parents=True, exist_ok=True)
provider = os.environ.get("BROKER_SELECTED_PROVIDER", "ib").strip().lower()
if provider not in {"ib", "etrade"}:
    provider = "ib"

loaded: dict[str, object] = {}
if config_path.exists():
    try:
        existing = json.loads(config_path.read_text(encoding="utf-8"))
        if isinstance(existing, dict):
            loaded = existing
    except Exception:
        loaded = {}

broker_cfg = loaded.get("broker")
if not isinstance(broker_cfg, dict):
    broker_cfg = {}
broker_cfg["provider"] = provider
loaded["broker"] = broker_cfg

config_path.write_text(json.dumps(loaded, indent=2) + "\n", encoding="utf-8")
os.chmod(config_path, 0o600)
PY
}

select_broker_provider() {
  if ! command -v python3 >/dev/null 2>&1; then
    fail "python3 is required for provider selection."
  fi

  local current_provider
  current_provider="$(read_configured_provider || true)"
  if [[ "${current_provider}" != "ib" && "${current_provider}" != "etrade" ]]; then
    current_provider="ib"
  fi

  if [[ ! -t 0 || ! -t 1 ]]; then
    SELECTED_PROVIDER="ib"
    save_selected_provider "${SELECTED_PROVIDER}"
    warn "No interactive TTY available. Defaulting broker provider to Interactive Brokers (IBKR)."
    return 0
  fi

  local default_choice="1"
  if [[ "${current_provider}" == "etrade" ]]; then
    default_choice="2"
  fi

  local choice=""
  while true; do
    printf "Select your broker provider:\n"
    printf "  1) Interactive Brokers (IBKR)\n"
    printf "  2) E*Trade\n"
    read -r -p "Provider [${default_choice}]: " choice

    case "${choice}" in
      "")
        choice="${default_choice}"
        ;;
      1|2)
        ;;
      *)
        echo "Please enter 1 or 2."
        continue
        ;;
    esac

    if [[ "${choice}" == "1" ]]; then
      SELECTED_PROVIDER="ib"
    else
      SELECTED_PROVIDER="etrade"
    fi
    break
  done

  save_selected_provider "${SELECTED_PROVIDER}"
}

run_etrade_onboarding_wizard() {
  if [[ ! -t 0 || ! -t 1 ]]; then
    warn "No interactive TTY available. Skipping E*Trade onboarding."
    return 0
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    fail "python3 is required for E*Trade onboarding."
  fi

  local consumer_key=""
  while [[ -z "${consumer_key}" ]]; do
    read -r -p "E*Trade consumer key: " consumer_key
    consumer_key="$(printf '%s' "${consumer_key}" | xargs)"
    if [[ -z "${consumer_key}" ]]; then
      echo "Consumer key is required."
    fi
  done

  local consumer_secret=""
  while [[ -z "${consumer_secret}" ]]; do
    read_secret_input "E*Trade consumer secret: " consumer_secret
    if [[ -z "${consumer_secret}" ]]; then
      echo "Consumer secret is required."
    fi
  done

  local username=""
  read -r -p "E*Trade username (for auto-reauth): " username
  username="$(printf '%s' "${username}" | xargs)"

  local password=""
  read_secret_input "E*Trade password (for auto-reauth): " password

  local auto_reauth="false"
  if [[ -n "${username}" && -n "${password}" ]]; then
    while true; do
      local auto_input=""
      read -r -p "Enable automatic re-authentication? [y/N]: " auto_input
      auto_reauth="$(parse_yes_no_default_no "${auto_input}" || true)"
      if [[ -n "${auto_reauth}" ]]; then
        break
      fi
      echo "Please answer yes or no."
    done
  fi

  local sandbox="false"
  while true; do
    local sandbox_input=""
    read -r -p "Use sandbox/test environment? [y/N]: " sandbox_input
    sandbox="$(parse_yes_no_default_no "${sandbox_input}" || true)"
    if [[ -n "${sandbox}" ]]; then
      break
    fi
    echo "Please answer yes or no."
  done

  BROKER_ETRADE_CONSUMER_KEY="${consumer_key}" \
  BROKER_ETRADE_CONSUMER_SECRET="${consumer_secret}" \
  BROKER_ETRADE_USERNAME="${username}" \
  BROKER_ETRADE_PASSWORD="${password}" \
  BROKER_ETRADE_AUTO_REAUTH="${auto_reauth}" \
  BROKER_ETRADE_SANDBOX="${sandbox}" \
  python3 - "${BROKER_CONFIG_JSON}" <<'PY'
import json
import os
import sys
from pathlib import Path

config_path = Path(sys.argv[1]).expanduser()
config_path.parent.mkdir(parents=True, exist_ok=True)

try:
    loaded = json.loads(config_path.read_text(encoding="utf-8")) if config_path.exists() else {}
except Exception:
    loaded = {}
if not isinstance(loaded, dict):
    loaded = {}


def as_non_empty_str(value: object) -> str:
    if isinstance(value, str):
        return value.strip()
    return ""


def as_bool(value: object) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        lowered = value.strip().lower()
        return lowered in {"1", "true", "yes", "on"}
    return False

broker_cfg = loaded.get("broker")
if not isinstance(broker_cfg, dict):
    broker_cfg = {}

etrade_cfg = broker_cfg.get("etrade")
if not isinstance(etrade_cfg, dict):
    etrade_cfg = {}

etrade_cfg["consumer_key"] = as_non_empty_str(os.environ.get("BROKER_ETRADE_CONSUMER_KEY", ""))
etrade_cfg["consumer_secret"] = as_non_empty_str(os.environ.get("BROKER_ETRADE_CONSUMER_SECRET", ""))
etrade_cfg["username"] = as_non_empty_str(os.environ.get("BROKER_ETRADE_USERNAME", ""))
etrade_cfg["password"] = os.environ.get("BROKER_ETRADE_PASSWORD", "")
etrade_cfg["auto_reauth"] = as_bool(os.environ.get("BROKER_ETRADE_AUTO_REAUTH", "false"))
etrade_cfg["sandbox"] = as_bool(os.environ.get("BROKER_ETRADE_SANDBOX", "false"))

broker_cfg["provider"] = "etrade"
broker_cfg["etrade"] = etrade_cfg
loaded["broker"] = broker_cfg

config_path.write_text(json.dumps(loaded, indent=2) + "\n", encoding="utf-8")
os.chmod(config_path, 0o600)
PY

  if [[ -z "${username}" || -z "${password}" ]]; then
    echo "Auto-reauth requires E*Trade username and password."
    echo "You can add them later in ~/.config/broker/config.json"
  fi
}

run_etrade_oauth_flow() {
  if [[ ! -t 0 || ! -t 1 ]]; then
    warn "No interactive TTY available. Skipping E*Trade OAuth authentication."
    warn "Run 'broker auth etrade' later to finish authentication."
    return 0
  fi

  local broker_cmd=""
  if [[ -x "${BROKER_BIN_DIR}/broker" ]]; then
    broker_cmd="${BROKER_BIN_DIR}/broker"
  elif command -v broker >/dev/null 2>&1; then
    broker_cmd="$(command -v broker)"
  elif [[ -x "${ROOT_DIR}/.venv/bin/broker" ]]; then
    broker_cmd="${ROOT_DIR}/.venv/bin/broker"
  fi

  if [[ -z "${broker_cmd}" ]]; then
    warn "Could not find broker CLI wrapper; run 'broker auth etrade' later."
    return 0
  fi

  if ! "${broker_cmd}" auth etrade; then
    warn "E*Trade OAuth authentication failed. You can run 'broker auth etrade' later."
  fi

  return 0
}

run_onboarding_wizard() {
  if [[ ! -t 0 || ! -t 1 ]]; then
    warn "No interactive TTY available. Skipping Interactive Brokers onboarding."
    return 0
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    fail "python3 is required for onboarding."
  fi

  local current_username
  current_username="$(read_broker_config_value "ibkrUsername" || true)"
  local current_mode
  current_mode="$(read_broker_config_value "ibkrGatewayMode" | tr '[:upper:]' '[:lower:]' || true)"
  if [[ "${current_mode}" != "paper" && "${current_mode}" != "live" ]]; then
    current_mode="paper"
  fi
  local current_auto
  current_auto="$(read_broker_config_value "ibkrAutoLogin" | tr '[:upper:]' '[:lower:]' || true)"
  if [[ "${current_auto}" != "true" && "${current_auto}" != "false" ]]; then
    current_auto="false"
  fi
  local current_password
  current_password="$(read_broker_config_value "ibkrPassword" || true)"

  local username_input
  if [[ -n "${current_username}" ]]; then
    read -r -p "IBKR username [${current_username}]: " username_input
  else
    read -r -p "IBKR username: " username_input
  fi
  local final_username="${current_username}"
  if [[ -n "${username_input}" ]]; then
    final_username="${username_input}"
  fi

  local final_password="${current_password}"
  local password_set="0"
  local password_input=""
  if [[ -n "${current_password}" ]]; then
    printf "IBKR password [press Enter to keep existing]: "
  else
    printf "IBKR password: "
  fi
  stty -echo
  IFS= read -r password_input || true
  stty echo
  printf "\n"
  if [[ -n "${password_input}" ]]; then
    final_password="${password_input}"
    password_set="1"
  fi

  local final_mode="${current_mode}"
  while true; do
    local mode_input=""
    read -r -p "Default gateway mode (paper/live) [${current_mode}]: " mode_input
    mode_input="$(printf '%s' "${mode_input}" | tr '[:upper:]' '[:lower:]')"
    if [[ -z "${mode_input}" ]]; then
      final_mode="${current_mode}"
      break
    fi
    if [[ "${mode_input}" == "paper" || "${mode_input}" == "live" ]]; then
      final_mode="${mode_input}"
      break
    fi
    echo "Please enter 'paper' or 'live'."
  done

  local auto_prompt="y/N"
  if [[ "${current_auto}" == "true" ]]; then
    auto_prompt="Y/n"
  fi

  local final_auto="${current_auto}"
  while true; do
    local auto_input=""
    read -r -p "Enable IBC auto login? [${auto_prompt}]: " auto_input
    auto_input="$(printf '%s' "${auto_input}" | tr '[:upper:]' '[:lower:]')"
    if [[ -z "${auto_input}" ]]; then
      final_auto="${current_auto}"
      break
    fi
    case "${auto_input}" in
      y|yes|1|true|on)
        final_auto="true"
        break
        ;;
      n|no|0|false|off)
        final_auto="false"
        break
        ;;
      *)
        echo "Please answer yes or no."
        ;;
    esac
  done

  if [[ "${final_auto}" == "true" ]]; then
    if [[ -z "${final_username}" || -z "${final_password}" ]]; then
      fail "IBC auto login requires both IBKR username and password. Rerun onboarding and provide both values."
    fi
  fi

  BROKER_ONBOARD_USERNAME="${final_username}" \
  BROKER_ONBOARD_PASSWORD="${final_password}" \
  BROKER_ONBOARD_PASSWORD_SET="${password_set}" \
  BROKER_ONBOARD_GATEWAY_MODE="${final_mode}" \
  BROKER_ONBOARD_AUTO_LOGIN="${final_auto}" \
  python3 - "${BROKER_CONFIG_JSON}" <<'PY'
import json
import os
import sys
from pathlib import Path

config_path = Path(sys.argv[1]).expanduser()
config_path.parent.mkdir(parents=True, exist_ok=True)

try:
    data = json.loads(config_path.read_text(encoding="utf-8")) if config_path.exists() else {}
except Exception:
    data = {}
if not isinstance(data, dict):
    data = {}


def as_non_empty_str(value: object) -> str:
    if isinstance(value, str):
        return value.strip()
    return ""


def as_bool(value: object) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        lowered = value.strip().lower()
        return lowered in {"1", "true", "yes", "on"}
    return False

broker_cfg = data.get("broker")
if not isinstance(broker_cfg, dict):
    broker_cfg = {}

username = as_non_empty_str(os.environ.get("BROKER_ONBOARD_USERNAME", ""))
password = os.environ.get("BROKER_ONBOARD_PASSWORD", "")
password_set = os.environ.get("BROKER_ONBOARD_PASSWORD_SET", "0") == "1"
gateway_mode = as_non_empty_str(os.environ.get("BROKER_ONBOARD_GATEWAY_MODE", "paper")).lower()
auto_login = as_bool(os.environ.get("BROKER_ONBOARD_AUTO_LOGIN", "false"))

if gateway_mode not in {"paper", "live"}:
    gateway_mode = "paper"

existing_password = as_non_empty_str(data.get("ibkrPassword"))
if password_set:
    next_password = password
else:
    next_password = existing_password

normalized = {
    "broker": broker_cfg,
    "ibkrUsername": username,
    "ibkrPassword": next_password,
    "ibkrGatewayMode": gateway_mode,
    "ibkrAutoLogin": auto_login,
}

config_path.write_text(json.dumps(normalized, indent=2) + "\n", encoding="utf-8")
os.chmod(config_path, 0o600)
PY
}
