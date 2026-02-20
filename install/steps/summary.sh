# shellcheck shell=bash

resolve_summary_provider() {
  local provider="${SELECTED_PROVIDER:-}"
  if [[ "${provider}" == "ib" || "${provider}" == "etrade" ]]; then
    printf '%s\n' "${provider}"
    return 0
  fi

  if [[ -f "${BROKER_CONFIG_JSON}" ]] && command -v python3 >/dev/null 2>&1; then
    provider="$(python3 - "${BROKER_CONFIG_JSON}" <<'PY'
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
    )"
  fi

  if [[ "${provider}" != "ib" && "${provider}" != "etrade" ]]; then
    provider="ib"
  fi
  printf '%s\n' "${provider}"
}

resolve_summary_fund_dir() {
  if [[ ! -f "${BROKER_CONFIG_JSON}" ]] || ! command -v python3 >/dev/null 2>&1; then
    return 0
  fi
  python3 - "${BROKER_CONFIG_JSON}" <<'PY'
import json
import sys
from pathlib import Path

config_path = Path(sys.argv[1]).expanduser()
if not config_path.exists():
    sys.exit(0)
try:
    loaded = json.loads(config_path.read_text(encoding="utf-8"))
except Exception:
    sys.exit(0)

if not isinstance(loaded, dict):
    sys.exit(0)
broker_cfg = loaded.get("broker")
if not isinstance(broker_cfg, dict):
    sys.exit(0)
observability = broker_cfg.get("observability")
if not isinstance(observability, dict):
    sys.exit(0)
fund_dir = observability.get("fund_dir")
if isinstance(fund_dir, str) and fund_dir.strip():
    print(fund_dir.strip())
PY
}

print_summary() {
  local provider
  provider="$(resolve_summary_provider)"
  local fund_dir
  fund_dir="$(resolve_summary_fund_dir || true)"

  if [[ "${provider}" == "etrade" ]]; then
    cat <<SUMMARY

${BOLD}${GREEN}Broker Install Complete (E*Trade)${RESET}

Config: ${BROKER_CONFIG_JSON}
Tokens: ${BROKER_CONFIG_HOME}/etrade-tokens.json
Fund repo: ${fund_dir:-"(not configured)"}

Try:
  ${BOLD}broker daemon start${RESET}
  ${BOLD}broker daemon status${RESET}
  ${BOLD}broker quote AAPL${RESET}
SUMMARY
    return 0
  fi

  cat <<SUMMARY

${BOLD}${GREEN}Broker Install Complete${RESET}

Config: ${BROKER_CONFIG_JSON}
Runtime state: ${BROKER_STATE_HOME}
Runtime data: ${BROKER_DATA_HOME}
Fund repo: ${fund_dir:-"(not configured)"}

Try:
  ${BOLD}broker --help${RESET}
  ${BOLD}broker daemon start --paper${RESET}
  ${BOLD}broker daemon status${RESET}
SUMMARY
}
