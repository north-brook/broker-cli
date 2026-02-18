# shellcheck shell=bash

has_prompt_tty() {
  [[ -r /dev/tty && -w /dev/tty ]]
}

tty_printf() {
  local format="$1"
  shift || true

  if has_prompt_tty; then
    printf "${format}" "$@" > /dev/tty
  else
    printf "${format}" "$@"
  fi
}

trim_input() {
  printf '%s' "${1}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

read_line_input() {
  local prompt="$1"
  local default_value="${2:-}"
  local __resultvar="$3"
  local value=""

  if [[ -n "${default_value}" ]]; then
    tty_printf "%s [%s]: " "${prompt}" "${default_value}"
  else
    tty_printf "%s: " "${prompt}"
  fi

  if has_prompt_tty; then
    IFS= read -r value < /dev/tty || value=""
  else
    IFS= read -r value || value=""
  fi

  if [[ -z "${value}" ]]; then
    value="${default_value}"
  fi

  printf -v "${__resultvar}" '%s' "${value}"
}

read_secret_input() {
  local prompt="$1"
  local __resultvar="$2"
  local secret=""
  local stty_state=""

  tty_printf "%s" "${prompt}"

  if has_prompt_tty; then
    stty_state="$(stty -g < /dev/tty 2>/dev/null || true)"
    stty -echo < /dev/tty 2>/dev/null || true
    IFS= read -r secret < /dev/tty || secret=""
    if [[ -n "${stty_state}" ]]; then
      stty "${stty_state}" < /dev/tty 2>/dev/null || true
    else
      stty echo < /dev/tty 2>/dev/null || true
    fi
  else
    stty_state="$(stty -g 2>/dev/null || true)"
    stty -echo 2>/dev/null || true
    IFS= read -r secret || secret=""
    if [[ -n "${stty_state}" ]]; then
      stty "${stty_state}" 2>/dev/null || true
    else
      stty echo 2>/dev/null || true
    fi
  fi

  tty_printf "\n"
  printf -v "${__resultvar}" '%s' "${secret}"
}

read_single_keypress() {
  local key=""
  local suffix=""

  if has_prompt_tty; then
    IFS= read -r -s -n 1 key < /dev/tty || return 1
    if [[ "${key}" == $'\x1b' ]]; then
      IFS= read -r -s -n 1 -t 0.05 suffix < /dev/tty || true
      key+="${suffix}"
      if [[ "${suffix}" == "[" ]]; then
        suffix=""
        IFS= read -r -s -n 1 -t 0.05 suffix < /dev/tty || true
        key+="${suffix}"
      fi
    fi
  else
    IFS= read -r -s -n 1 key || return 1
  fi

  printf '%s' "${key}"
}

prompt_menu_select() {
  local prompt="$1"
  local default_value="$2"
  local __resultvar="$3"
  shift 3
  local options=("$@")
  local option_count="${#options[@]}"

  if [[ "${option_count}" -eq 0 ]]; then
    fail "Internal setup error: '${prompt}' has no selectable options."
  fi

  local selected_index=0
  local i=""
  local value=""
  local label=""
  local hint=""

  for i in "${!options[@]}"; do
    IFS='|' read -r value label hint <<<"${options[i]}"
    if [[ "${value}" == "${default_value}" ]]; then
      selected_index="${i}"
      break
    fi
  done

  local rendered=0
  local lines_rendered=$((option_count + 2))
  while true; do
    if [[ "${rendered}" -eq 1 ]]; then
      tty_printf "\033[%dA" "${lines_rendered}"
      tty_printf "\033[J"
    fi

    tty_printf "%b%s%b\n" "${BOLD}" "${prompt}" "${RESET}"
    tty_printf "%b%s%b\n" "${DIM}" "Use ↑/↓ (or j/k), number keys, and Enter." "${RESET}"

    for i in "${!options[@]}"; do
      IFS='|' read -r value label hint <<<"${options[i]}"
      if [[ "${i}" -eq "${selected_index}" ]]; then
        if [[ -n "${hint}" ]]; then
          tty_printf "  %b>%b %b%s%b %b(%s)%b\n" "${BLUE}" "${RESET}" "${BOLD}" "${label}" "${RESET}" "${DIM}" "${hint}" "${RESET}"
        else
          tty_printf "  %b>%b %b%s%b\n" "${BLUE}" "${RESET}" "${BOLD}" "${label}" "${RESET}"
        fi
      else
        if [[ -n "${hint}" ]]; then
          tty_printf "   %d) %s %b(%s)%b\n" "$((i + 1))" "${label}" "${DIM}" "${hint}" "${RESET}"
        else
          tty_printf "   %d) %s\n" "$((i + 1))" "${label}"
        fi
      fi
    done

    rendered=1
    local key=""
    key="$(read_single_keypress || true)"

    case "${key}" in
      $'\x03')
        tty_printf "\n"
        fail "Setup cancelled."
        ;;
      $'\x1b[A'|k|K)
        selected_index=$(((selected_index - 1 + option_count) % option_count))
        ;;
      $'\x1b[B'|j|J)
        selected_index=$(((selected_index + 1) % option_count))
        ;;
      [1-9])
        local choice_index=$((10#${key} - 1))
        if ((choice_index >= 0 && choice_index < option_count)); then
          selected_index="${choice_index}"
        fi
        ;;
      ""|$'\n'|$'\r')
        IFS='|' read -r value label hint <<<"${options[selected_index]}"
        tty_printf "\033[%dA\033[J" "${lines_rendered}"
        tty_printf "%b✔%b %s: %b%s%b\n" "${GREEN}" "${RESET}" "${prompt}" "${BOLD}" "${label}" "${RESET}"
        printf -v "${__resultvar}" '%s' "${value}"
        return 0
        ;;
      *)
        ;;
    esac
  done
}

prompt_yes_no_menu() {
  local prompt="$1"
  local default_value="$2"
  local __resultvar="$3"
  local normalized
  normalized="$(printf '%s' "${default_value}" | tr '[:upper:]' '[:lower:]')"
  if [[ "${normalized}" != "true" && "${normalized}" != "false" ]]; then
    normalized="false"
  fi

  local selected_value=""
  prompt_menu_select \
    "${prompt}" \
    "${normalized}" \
    selected_value \
    "true|Yes|Enable" \
    "false|No|Disable"
  printf -v "${__resultvar}" '%s' "${selected_value}"
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

read_etrade_config_value() {
  local key="$1"
  if [[ ! -f "${BROKER_CONFIG_JSON}" ]]; then
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    return 0
  fi

  python3 - "${BROKER_CONFIG_JSON}" "${key}" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
key = sys.argv[2]
try:
    data = json.loads(path.read_text(encoding="utf-8"))
except Exception:
    sys.exit(0)

if not isinstance(data, dict):
    sys.exit(0)

broker_cfg = data.get("broker")
if not isinstance(broker_cfg, dict):
    sys.exit(0)

etrade_cfg = broker_cfg.get("etrade")
if not isinstance(etrade_cfg, dict):
    sys.exit(0)

value = etrade_cfg.get(key)
if value is None:
    sys.exit(0)

if isinstance(value, bool):
    print("true" if value else "false")
elif isinstance(value, (str, int, float)):
    print(value)
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

  if ! has_prompt_tty; then
    SELECTED_PROVIDER="ib"
    save_selected_provider "${SELECTED_PROVIDER}"
    warn "No interactive terminal input available. Defaulting broker provider to Interactive Brokers (IBKR)."
    return 0
  fi

  local selected_provider=""
  prompt_menu_select \
    "Choose your broker provider" \
    "${current_provider}" \
    selected_provider \
    "ib|Interactive Brokers (IBKR)|Gateway + IBC automation" \
    "etrade|E*Trade|OAuth + optional persistent auth"

  SELECTED_PROVIDER="${selected_provider}"
  save_selected_provider "${SELECTED_PROVIDER}"
}

run_etrade_onboarding_wizard() {
  if ! has_prompt_tty; then
    warn "No interactive terminal input available. Skipping E*Trade onboarding."
    return 0
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    fail "python3 is required for E*Trade onboarding."
  fi

  tty_printf "%b%s%b\n" "${BOLD}" "E*Trade Configuration" "${RESET}"

  local current_consumer_key=""
  current_consumer_key="$(trim_input "$(read_etrade_config_value "consumer_key" || true)")"
  local current_consumer_secret=""
  current_consumer_secret="$(read_etrade_config_value "consumer_secret" || true)"
  local current_username=""
  current_username="$(trim_input "$(read_etrade_config_value "username" || true)")"
  local current_password=""
  current_password="$(read_etrade_config_value "password" || true)"
  local current_persistent_auth=""
  current_persistent_auth="$(printf '%s' "$(read_etrade_config_value "persistent_auth" || true)" | tr '[:upper:]' '[:lower:]')"
  if [[ "${current_persistent_auth}" != "true" && "${current_persistent_auth}" != "false" ]]; then
    current_persistent_auth="false"
  fi
  local current_sandbox=""
  current_sandbox="$(printf '%s' "$(read_etrade_config_value "sandbox" || true)" | tr '[:upper:]' '[:lower:]')"
  if [[ "${current_sandbox}" != "true" && "${current_sandbox}" != "false" ]]; then
    current_sandbox="false"
  fi

  local consumer_key=""
  read_line_input "E*Trade consumer key" "${current_consumer_key}" consumer_key
  consumer_key="$(trim_input "${consumer_key}")"
  while [[ -z "${consumer_key}" ]]; do
    tty_printf "%b%s%b\n" "${YELLOW}" "Consumer key is required." "${RESET}"
    read_line_input "E*Trade consumer key" "${current_consumer_key}" consumer_key
    consumer_key="$(trim_input "${consumer_key}")"
  done

  local consumer_secret=""
  local secret_input=""
  if [[ -n "${current_consumer_secret}" ]]; then
    read_secret_input "E*Trade consumer secret [press Enter to keep existing]: " secret_input
    if [[ -z "${secret_input}" ]]; then
      consumer_secret="${current_consumer_secret}"
    else
      consumer_secret="${secret_input}"
    fi
  else
    read_secret_input "E*Trade consumer secret: " consumer_secret
  fi

  while [[ -z "${consumer_secret}" ]]; do
    tty_printf "%b%s%b\n" "${YELLOW}" "Consumer secret is required." "${RESET}"
    if [[ -n "${current_consumer_secret}" ]]; then
      secret_input=""
      read_secret_input "E*Trade consumer secret [press Enter to keep existing]: " secret_input
      if [[ -z "${secret_input}" ]]; then
        consumer_secret="${current_consumer_secret}"
      else
        consumer_secret="${secret_input}"
      fi
    else
      read_secret_input "E*Trade consumer secret: " consumer_secret
    fi
  done

  local username=""
  read_line_input "E*Trade username (optional, for persistent auth)" "${current_username}" username
  username="$(trim_input "${username}")"

  local password=""
  if [[ -n "${current_password}" ]]; then
    local password_input=""
    read_secret_input "E*Trade password [press Enter to keep existing]: " password_input
    if [[ -n "${password_input}" ]]; then
      password="${password_input}"
    else
      password="${current_password}"
    fi
  else
    read_secret_input "E*Trade password (optional, for persistent auth): " password
  fi

  local persistent_auth="false"
  if [[ -n "${username}" && -n "${password}" ]]; then
    prompt_yes_no_menu "Enable automatic re-authentication?" "${current_persistent_auth}" persistent_auth
  else
    persistent_auth="false"
  fi

  local sandbox="false"
  prompt_yes_no_menu "Use sandbox/test environment?" "${current_sandbox}" sandbox

  BROKER_ETRADE_CONSUMER_KEY="${consumer_key}" \
  BROKER_ETRADE_CONSUMER_SECRET="${consumer_secret}" \
  BROKER_ETRADE_USERNAME="${username}" \
  BROKER_ETRADE_PASSWORD="${password}" \
  BROKER_ETRADE_PERSISTENT_AUTH="${persistent_auth}" \
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
etrade_cfg["persistent_auth"] = as_bool(os.environ.get("BROKER_ETRADE_PERSISTENT_AUTH", "false"))
etrade_cfg["sandbox"] = as_bool(os.environ.get("BROKER_ETRADE_SANDBOX", "false"))

broker_cfg["provider"] = "etrade"
broker_cfg["etrade"] = etrade_cfg
loaded["broker"] = broker_cfg

config_path.write_text(json.dumps(loaded, indent=2) + "\n", encoding="utf-8")
os.chmod(config_path, 0o600)
PY

  if [[ -z "${username}" || -z "${password}" ]]; then
    tty_printf "%b%s%b\n" "${YELLOW}" "Persistent auth requires E*Trade username and password." "${RESET}"
    tty_printf "%b%s%b\n" "${DIM}" "You can add them later in ~/.config/broker/config.json." "${RESET}"
  fi
}

run_etrade_oauth_flow() {
  if ! has_prompt_tty; then
    warn "No interactive terminal input available. Skipping E*Trade OAuth authentication."
    warn "Rerun 'broker setup' in an interactive terminal to finish authentication."
    return 0
  fi

  local oauth_python=""
  if [[ -x "${ROOT_DIR}/.venv/bin/python" ]]; then
    oauth_python="${ROOT_DIR}/.venv/bin/python"
  elif command -v python3 >/dev/null 2>&1; then
    oauth_python="$(command -v python3)"
  elif command -v python >/dev/null 2>&1; then
    oauth_python="$(command -v python)"
  fi

  if [[ -z "${oauth_python}" ]]; then
    warn "Python runtime not found. Rerun 'broker setup' after installing Python."
    return 0
  fi

  local consumer_key=""
  consumer_key="$(trim_input "$(read_etrade_config_value "consumer_key" || true)")"
  local consumer_secret=""
  consumer_secret="$(read_etrade_config_value "consumer_secret" || true)"
  local sandbox=""
  sandbox="$(printf '%s' "$(read_etrade_config_value "sandbox" || true)" | tr '[:upper:]' '[:lower:]')"
  if [[ "${sandbox}" != "true" && "${sandbox}" != "false" ]]; then
    sandbox="false"
  fi

  if [[ -z "${consumer_key}" || -z "${consumer_secret}" ]]; then
    warn "Missing E*Trade consumer key/secret in config; rerun 'broker setup' and provide both values."
    return 0
  fi

  local setup_pythonpath="${ROOT_DIR}/daemon/src:${ROOT_DIR}/sdk/python/src:${ROOT_DIR}/cli/src"
  if [[ -n "${PYTHONPATH:-}" ]]; then
    setup_pythonpath="${setup_pythonpath}:${PYTHONPATH}"
  fi

  local request_payload=""
  if ! request_payload="$(
    BROKER_SETUP_ETRADE_KEY="${consumer_key}" \
    BROKER_SETUP_ETRADE_SECRET="${consumer_secret}" \
    BROKER_SETUP_ETRADE_SANDBOX="${sandbox}" \
    PYTHONPATH="${setup_pythonpath}" \
    "${oauth_python}" - <<'PY'
import asyncio
import os
import sys

from broker_daemon.exceptions import BrokerError
from broker_daemon.providers.etrade import etrade_authorize_url, etrade_request_token

consumer_key = os.environ.get("BROKER_SETUP_ETRADE_KEY", "").strip()
consumer_secret = os.environ.get("BROKER_SETUP_ETRADE_SECRET", "").strip()
sandbox = os.environ.get("BROKER_SETUP_ETRADE_SANDBOX", "").strip().lower() in {"1", "true", "yes", "on"}

try:
    request = asyncio.run(
        etrade_request_token(
            consumer_key=consumer_key,
            consumer_secret=consumer_secret,
            sandbox=sandbox,
        )
    )
except BrokerError as exc:
    print(f"E*Trade OAuth initialization failed: {exc.message}", file=sys.stderr)
    if exc.suggestion:
        print(exc.suggestion, file=sys.stderr)
    sys.exit(1)
except Exception as exc:
    print(f"E*Trade OAuth initialization failed: {exc}", file=sys.stderr)
    sys.exit(1)

print(request["oauth_token"])
print(request["oauth_token_secret"])
print(etrade_authorize_url(consumer_key, request["oauth_token"]))
PY
  )"; then
    warn "E*Trade OAuth initialization failed. Rerun 'broker setup' to try again."
    return 0
  fi

  local request_token=""
  request_token="$(printf '%s\n' "${request_payload}" | sed -n '1p')"
  local request_token_secret=""
  request_token_secret="$(printf '%s\n' "${request_payload}" | sed -n '2p')"
  local authorize_url=""
  authorize_url="$(printf '%s\n' "${request_payload}" | sed -n '3p')"

  if [[ -z "${request_token}" || -z "${request_token_secret}" || -z "${authorize_url}" ]]; then
    warn "E*Trade OAuth initialization returned an invalid response. Rerun 'broker setup'."
    return 0
  fi

  tty_printf "%b%s%b\n" "${BOLD}" "Open this URL in your browser, sign in, and approve access:" "${RESET}"
  tty_printf "%s\n" "${authorize_url}"

  local verifier=""
  while [[ -z "${verifier}" ]]; do
    read_line_input "Enter E*Trade verification code" "" verifier
    verifier="$(trim_input "${verifier}")"
    if [[ -z "${verifier}" ]]; then
      tty_printf "%b%s%b\n" "${YELLOW}" "Verification code is required." "${RESET}"
    fi
  done

  local token_path=""
  if ! token_path="$(
    BROKER_SETUP_ETRADE_KEY="${consumer_key}" \
    BROKER_SETUP_ETRADE_SECRET="${consumer_secret}" \
    BROKER_SETUP_ETRADE_REQUEST_TOKEN="${request_token}" \
    BROKER_SETUP_ETRADE_REQUEST_SECRET="${request_token_secret}" \
    BROKER_SETUP_ETRADE_VERIFIER="${verifier}" \
    BROKER_SETUP_ETRADE_SANDBOX="${sandbox}" \
    PYTHONPATH="${setup_pythonpath}" \
    "${oauth_python}" - <<'PY'
import asyncio
import os
import sys

from broker_daemon.config import load_config
from broker_daemon.exceptions import BrokerError
from broker_daemon.providers.etrade import etrade_access_token, save_etrade_tokens

consumer_key = os.environ.get("BROKER_SETUP_ETRADE_KEY", "").strip()
consumer_secret = os.environ.get("BROKER_SETUP_ETRADE_SECRET", "").strip()
request_token = os.environ.get("BROKER_SETUP_ETRADE_REQUEST_TOKEN", "").strip()
request_token_secret = os.environ.get("BROKER_SETUP_ETRADE_REQUEST_SECRET", "").strip()
verifier = os.environ.get("BROKER_SETUP_ETRADE_VERIFIER", "").strip()
sandbox = os.environ.get("BROKER_SETUP_ETRADE_SANDBOX", "").strip().lower() in {"1", "true", "yes", "on"}

try:
    access = asyncio.run(
        etrade_access_token(
            consumer_key=consumer_key,
            consumer_secret=consumer_secret,
            request_token=request_token,
            request_token_secret=request_token_secret,
            verifier=verifier,
            sandbox=sandbox,
        )
    )
    token_path = load_config().etrade.token_path.expanduser()
    save_etrade_tokens(
        token_path,
        oauth_token=access["oauth_token"],
        oauth_token_secret=access["oauth_token_secret"],
    )
except BrokerError as exc:
    print(f"E*Trade OAuth verification failed: {exc.message}", file=sys.stderr)
    if exc.suggestion:
        print(exc.suggestion, file=sys.stderr)
    sys.exit(1)
except Exception as exc:
    print(f"E*Trade OAuth verification failed: {exc}", file=sys.stderr)
    sys.exit(1)

print(token_path)
PY
  )"; then
    warn "E*Trade OAuth authentication failed. Rerun 'broker setup' to try again."
    return 0
  fi

  token_path="$(trim_input "${token_path}")"
  if [[ -n "${token_path}" ]]; then
    tty_printf "%b✔%b %s\n" "${GREEN}" "${RESET}" "E*Trade OAuth tokens saved to ${token_path}"
  else
    tty_printf "%b✔%b %s\n" "${GREEN}" "${RESET}" "E*Trade OAuth authentication complete."
  fi

  return 0
}

run_onboarding_wizard() {
  if ! has_prompt_tty; then
    warn "No interactive terminal input available. Skipping Interactive Brokers onboarding."
    return 0
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    fail "python3 is required for onboarding."
  fi

  tty_printf "%b%s%b\n" "${BOLD}" "Interactive Brokers Configuration" "${RESET}"

  local current_username
  current_username="$(trim_input "$(read_broker_config_value "ibkrUsername" || true)")"
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

  local final_username=""
  read_line_input "IBKR username" "${current_username}" final_username
  final_username="$(trim_input "${final_username}")"

  local final_password="${current_password}"
  local password_set="0"
  local password_input=""
  if [[ -n "${current_password}" ]]; then
    read_secret_input "IBKR password [press Enter to keep existing]: " password_input
  else
    read_secret_input "IBKR password: " password_input
  fi
  if [[ -n "${password_input}" ]]; then
    final_password="${password_input}"
    password_set="1"
  fi

  local final_mode=""
  prompt_menu_select \
    "Default gateway mode" \
    "${current_mode}" \
    final_mode \
    "paper|Paper trading|Uses IB paper account (port 4002)" \
    "live|Live trading|Uses IB live account (port 4001)"

  local final_auto=""
  prompt_yes_no_menu "Enable IBC auto login?" "${current_auto}" final_auto

  if [[ "${final_auto}" == "true" ]]; then
    if [[ -z "${final_username}" || -z "${final_password}" ]]; then
      fail "IBC auto login requires both IBKR username and password. Rerun setup and provide both values."
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
