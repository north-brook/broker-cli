#!/usr/bin/env bash
set -euo pipefail

SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [[ -L "${SCRIPT_SOURCE}" ]]; do
  SCRIPT_DIR="$(cd -P "$(dirname "${SCRIPT_SOURCE}")" && pwd)"
  SCRIPT_SOURCE="$(readlink "${SCRIPT_SOURCE}")"
  if [[ "${SCRIPT_SOURCE}" != /* ]]; then
    SCRIPT_SOURCE="${SCRIPT_DIR}/${SCRIPT_SOURCE}"
  fi
done
ROOT_DIR="$(cd -P "$(dirname "${SCRIPT_SOURCE}")" && pwd)"

NORTHBROOK_HOME="${NORTHBROOK_HOME:-${HOME}/.northbrook}"
NORTHBROOK_CONFIG_JSON="${NORTHBROOK_HOME}/northbrook.json"
NORTHBROOK_WORKSPACE="${NORTHBROOK_HOME}/workspace"
NORTHBROOK_SOURCE_DIR="${NORTHBROOK_SOURCE_DIR:-${NORTHBROOK_HOME}/source}"
NORTHBROOK_REPO="${NORTHBROOK_REPO:-https://github.com/brycedbjork/northbrook.git}"
ORIG_ARGS=("$@")

export PATH="/opt/homebrew/bin:/usr/local/bin:/home/linuxbrew/.linuxbrew/bin:${HOME}/.bun/bin:${PATH}"

load_northbrook_secrets() {
  local cfg="${NORTHBROOK_CONFIG_JSON}"
  if [[ ! -f "${cfg}" ]]; then
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    return 0
  fi

  while IFS='=' read -r key value; do
    if [[ -z "${key}" ]]; then
      continue
    fi
    export "${key}=${value}"
  done < <(
    python3 - "${cfg}" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    data = json.loads(path.read_text(encoding="utf-8"))
except Exception:
    sys.exit(0)

if not isinstance(data, dict):
    sys.exit(0)
def as_non_empty_str(value: object) -> str:
    if isinstance(value, str):
        return value.strip()
    return ""

ai_provider_cfg = data.get("aiProvider")
if isinstance(ai_provider_cfg, dict):
    provider = as_non_empty_str(ai_provider_cfg.get("provider")).lower()
    api_key = as_non_empty_str(ai_provider_cfg.get("apiKey"))
    model = as_non_empty_str(ai_provider_cfg.get("model"))
else:
    provider = ""
    api_key = ""
    model = ""

if provider in {"anthropic", "openai", "google"}:
    print(f"NORTHBROOK_AI_PROVIDER={provider}")
if model:
    print(f"NORTHBROOK_AI_MODEL={model}")
if provider in {"anthropic", "openai", "google"} and api_key:
    provider_env_map = {
        "anthropic": "ANTHROPIC_API_KEY",
        "openai": "OPENAI_API_KEY",
        "google": "GEMINI_API_KEY",
    }
    provider_env = provider_env_map.get(provider)
    if provider_env:
        print(f"{provider_env}={api_key}")

skills = data.get("skills")
x_api_key = ""
brave_search_api_key = ""
if isinstance(skills, dict):
    x_cfg = skills.get("xApi")
    if isinstance(x_cfg, dict):
        x_api_key = as_non_empty_str(x_cfg.get("apiKey"))
    brave_cfg = skills.get("braveSearchApi")
    if isinstance(brave_cfg, dict):
        brave_search_api_key = as_non_empty_str(brave_cfg.get("apiKey"))

if x_api_key:
    print(f"X_API_KEY={x_api_key}")
if brave_search_api_key:
    print(f"BRAVE_SEARCH_API_KEY={brave_search_api_key}")

ibkr_username = as_non_empty_str(data.get("ibkrUsername"))
ibkr_password = as_non_empty_str(data.get("ibkrPassword"))
ibkr_auto_login = data.get("ibkrAutoLogin")

if ibkr_username:
    print(f"BROKER_IB_USERNAME={ibkr_username}")
if ibkr_password:
    print(f"BROKER_IB_PASSWORD={ibkr_password}")
if isinstance(ibkr_auto_login, bool):
    print(f"BROKER_IB_AUTO_LOGIN={'true' if ibkr_auto_login else 'false'}")
PY
  )
}

read_northbrook_config_value() {
  local key="$1"
  if [[ ! -f "${NORTHBROOK_CONFIG_JSON}" ]]; then
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    return 0
  fi
  python3 - "${NORTHBROOK_CONFIG_JSON}" "${key}" <<'PY'
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

value = data.get(key)

if value is None and key == "aiProvider.provider":
    ai_provider = data.get("aiProvider")
    if isinstance(ai_provider, dict):
        value = ai_provider.get("provider")

if value is None:
    sys.exit(0)

if isinstance(value, bool):
    print("true" if value else "false")
elif isinstance(value, (str, int, float)):
    print(value)
PY
}

default_daemon_mode_arg() {
  local mode
  mode="$(read_northbrook_config_value "ibkrGatewayMode" | tr '[:upper:]' '[:lower:]' || true)"
  case "${mode}" in
    live) printf '%s\n' "--live" ;;
    paper|"") printf '%s\n' "--paper" ;;
    *) printf '%s\n' "--paper" ;;
  esac
}

has_explicit_gateway_or_mode() {
  local args=("$@")
  local arg=""
  for arg in "${args[@]}"; do
    case "${arg}" in
      --paper|--live|--gateway|--gateway=*)
        return 0
        ;;
    esac
  done
  return 1
}

run_broker_start() {
  local daemon_args=("$@")
  if ! has_explicit_gateway_or_mode "${daemon_args[@]}"; then
    daemon_args+=("$(default_daemon_mode_arg)")
  fi

  "${ROOT_DIR}/broker/start.sh" "${daemon_args[@]}"
}

run_agents_start() {
  if [[ ! -x "${ROOT_DIR}/agents/start.sh" ]]; then
    echo "agents/start.sh not found or not executable at ${ROOT_DIR}/agents/start.sh" >&2
    return 1
  fi
  "${ROOT_DIR}/agents/start.sh"
}

BROKER_DIR="${ROOT_DIR}/broker"
PYTHON_VERSION="${PYTHON_VERSION:-3.12}"
INSTALL_IB_APP="${BROKER_INSTALL_IB_APP:-1}"
IB_CHANNEL="${BROKER_IB_CHANNEL:-stable}"
IB_INSTALL_DIR="${BROKER_IB_INSTALL_DIR:-${HOME}/Applications/IB Gateway}"
IBC_RELEASE_TAG="${BROKER_IBC_RELEASE_TAG:-latest}"
IBC_INSTALL_DIR="${BROKER_IBC_INSTALL_DIR:-${NORTHBROOK_HOME}/ibc}"
NB_BIN_DIR="${NB_BIN_DIR:-${HOME}/.local/bin}"
LOG_DIR="$(mktemp -d /tmp/northbrook-install.XXXXXX)"
STEP_INDEX=0
STEP_TOTAL=12
INTERACTIVE=0
SKIP_ONBOARDING=0
ONBOARDING_ONLY=0
ONBOARDING_INTERACTIVE=0

if [[ -t 0 && -t 1 ]]; then
  ONBOARDING_INTERACTIVE=1
fi

for arg in "${ORIG_ARGS[@]}"; do
  case "${arg}" in
    --skip-onboarding)
      SKIP_ONBOARDING=1
      ;;
    --onboarding-only)
      ONBOARDING_ONLY=1
      ;;
  esac
done

if [[ "${SKIP_ONBOARDING}" -eq 0 && "${ONBOARDING_INTERACTIVE}" -eq 1 ]]; then
  STEP_TOTAL=13
fi

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

banner() {
  cat <<BANNER
${BOLD}${BLUE}========================================${RESET}
${BOLD}${BLUE}  Northbrook Platform Installer${RESET}
${BOLD}${BLUE}========================================${RESET}
BANNER
}

success() {
  printf "${GREEN}%s${RESET}\n" "$1"
}

warn() {
  printf "${YELLOW}%s${RESET}\n" "$1"
}

fail() {
  printf "${RED}%s${RESET}\n" "$1" >&2
  exit 1
}

run_step() {
  local label="$1"
  shift
  STEP_INDEX=$((STEP_INDEX + 1))

  local prefix
  prefix=$(printf "[%d/%d]" "${STEP_INDEX}" "${STEP_TOTAL}")
  local log_file="${LOG_DIR}/step-${STEP_INDEX}.log"

  if [[ "${INTERACTIVE}" -eq 1 ]]; then
    local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local frame_index=0
    "$@" >"${log_file}" 2>&1 &
    local pid=$!

    while kill -0 "${pid}" >/dev/null 2>&1; do
      printf "\r  ${DIM}%s${RESET} ${BLUE}%s${RESET} %s" \
        "${prefix}" "${frames[frame_index]}" "${label}"
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
      printf "\r  ${DIM}%s${RESET} ${GREEN}✔${RESET} %s\n" "${prefix}" "${label}"
      rm -f "${log_file}"
      return 0
    fi

    printf "\r  ${DIM}%s${RESET} ${RED}✖${RESET} %s\n" "${prefix}" "${label}" >&2
    printf "    ${RED}Step failed.${RESET} Log: %s\n" "${log_file}" >&2
    tail -n 40 "${log_file}" >&2 || true
    return "${rc}"
  fi

  printf "${BOLD}%s${RESET} %s\n" "${prefix}" "${label}"
  if "$@" >"${log_file}" 2>&1; then
    success "  ${label}"
    rm -f "${log_file}"
    return 0
  fi

  printf "${RED}Step failed.${RESET} Log: %s\n" "${log_file}" >&2
  tail -n 40 "${log_file}" >&2 || true
  return 1
}

ensure_source_checkout() {
  if [[ -d "${BROKER_DIR}" && -d "${ROOT_DIR}/terminal" && -d "${ROOT_DIR}/agents" ]]; then
    return 0
  fi

  if ! command -v git >/dev/null 2>&1; then
    ensure_homebrew
    ensure_brew_package "git"
  fi
  if ! command -v git >/dev/null 2>&1; then
    fail "git is required for bootstrap installs but could not be installed."
  fi

  mkdir -p "${NORTHBROOK_HOME}"

  if [[ -d "${NORTHBROOK_SOURCE_DIR}/.git" ]]; then
    git -C "${NORTHBROOK_SOURCE_DIR}" fetch --depth=1 origin main || true
    git -C "${NORTHBROOK_SOURCE_DIR}" reset --hard origin/main || true
  else
    rm -rf "${NORTHBROOK_SOURCE_DIR}"
    git clone --depth=1 "${NORTHBROOK_REPO}" "${NORTHBROOK_SOURCE_DIR}"
  fi

  exec "${NORTHBROOK_SOURCE_DIR}/install.sh" "${ORIG_ARGS[@]}"
}
ensure_homebrew() {
  if command -v brew >/dev/null 2>&1; then
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    fail "curl is required to install Homebrew."
  fi

  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  if [[ -x "/opt/homebrew/bin/brew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x "/usr/local/bin/brew" ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  elif [[ -x "/home/linuxbrew/.linuxbrew/bin/brew" ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
  fi

  if ! command -v brew >/dev/null 2>&1; then
    fail "Homebrew installation finished but 'brew' is still not on PATH."
  fi
}

ensure_brew_package() {
  local pkg="$1"
  if brew list --versions "${pkg}" >/dev/null 2>&1; then
    return 0
  fi
  brew install "${pkg}"
}

ensure_bun() {
  if command -v bun >/dev/null 2>&1; then
    return 0
  fi
  brew install oven-sh/bun/bun
  if ! command -v bun >/dev/null 2>&1; then
    fail "bun installation completed but 'bun' is still not on PATH."
  fi
}

bootstrap_tooling() {
  ensure_homebrew
  ensure_brew_package "git"
  ensure_brew_package "uv"
  ensure_bun
}

prepare_northbrook_home() {
  mkdir -p "${NORTHBROOK_HOME}"
  mkdir -p "${NORTHBROOK_HOME}/logs"
}

init_workspace_repo() {
  mkdir -p "${NORTHBROOK_WORKSPACE}"

  if [[ ! -d "${NORTHBROOK_WORKSPACE}/.git" ]]; then
    git init -b main "${NORTHBROOK_WORKSPACE}" >/dev/null 2>&1 || {
      git init "${NORTHBROOK_WORKSPACE}" >/dev/null 2>&1
      git -C "${NORTHBROOK_WORKSPACE}" checkout -b main >/dev/null 2>&1 || true
    }
  fi

  if [[ ! -f "${NORTHBROOK_WORKSPACE}/risk.json" ]]; then
    cat > "${NORTHBROOK_WORKSPACE}/risk.json" <<'RISK'
{
  "max_position_pct": 10.0,
  "max_order_value": 50000,
  "max_daily_loss_pct": 2.0
}
RISK
  fi

  if [[ ! -f "${NORTHBROOK_WORKSPACE}/README.md" ]]; then
    cat > "${NORTHBROOK_WORKSPACE}/README.md" <<'README'
# Northbrook Workspace

Instance-specific files belong here (for example `risk.json`).
This directory is a git repository so you can commit/push your local policy and strategy files.
README
  fi
}

ensure_northbrook_secrets_config() {
  mkdir -p "${NORTHBROOK_HOME}"
  if ! command -v python3 >/dev/null 2>&1; then
    fail "python3 is required to initialize ${NORTHBROOK_CONFIG_JSON}."
  fi

  python3 - "${NORTHBROOK_CONFIG_JSON}" <<'PY'
import json
import os
import sys
from pathlib import Path

config_path = Path(sys.argv[1]).expanduser()
config_path.parent.mkdir(parents=True, exist_ok=True)

defaults = {
    "aiProvider": {
        "provider": "anthropic",
        "apiKey": "",
        "model": "claude-sonnet-4-5",
    },
    "skills": {},
    "ibkrUsername": "",
    "ibkrPassword": "",
    "ibkrGatewayMode": "paper",
    "ibkrAutoLogin": False,
}
provider_defaults = {
    "anthropic": "claude-sonnet-4-5",
    "openai": "gpt-5",
    "google": "gemini-2.5-pro",
}

def as_non_empty_str(value: object) -> str:
    if isinstance(value, str):
        return value.strip()
    return ""

data: dict[str, object] = defaults
if config_path.exists():
    try:
        loaded = json.loads(config_path.read_text(encoding="utf-8"))
        if isinstance(loaded, dict):
            data = loaded
    except Exception:
        data = defaults

ai_provider = data.get("aiProvider")
if not isinstance(ai_provider, dict):
    ai_provider = {}
provider = as_non_empty_str(ai_provider.get("provider")).lower()
if provider not in provider_defaults:
    provider = "anthropic"
api_key = as_non_empty_str(ai_provider.get("apiKey"))
model = as_non_empty_str(ai_provider.get("model")) or provider_defaults[provider]

skills = data.get("skills")
if not isinstance(skills, dict):
    skills = {}
normalized_skills: dict[str, dict[str, str]] = {}
for skill_name in ("xApi", "braveSearchApi"):
    raw_skill = skills.get(skill_name)
    if isinstance(raw_skill, dict):
        normalized_skills[skill_name] = {"apiKey": as_non_empty_str(raw_skill.get("apiKey"))}

gateway_mode = as_non_empty_str(data.get("ibkrGatewayMode"))
if gateway_mode not in {"paper", "live"}:
    gateway_mode = "paper"

data = {
    "aiProvider": {"provider": provider, "apiKey": api_key, "model": model},
    "skills": normalized_skills,
    "ibkrUsername": as_non_empty_str(data.get("ibkrUsername")),
    "ibkrPassword": as_non_empty_str(data.get("ibkrPassword")),
    "ibkrGatewayMode": gateway_mode,
    "ibkrAutoLogin": bool(data.get("ibkrAutoLogin")),
}

config_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
os.chmod(config_path, 0o600)
PY
}

run_onboarding_wizard() {
  if ! command -v bun >/dev/null 2>&1; then
    fail "bun is required for onboarding."
  fi
  if [[ ! -f "${ROOT_DIR}/terminal/wizard/main.tsx" ]]; then
    fail "terminal onboarding wizard not found at ${ROOT_DIR}/terminal/wizard/main.tsx"
  fi

  (
    cd "${ROOT_DIR}/terminal"
    bun run wizard -- --config "${NORTHBROOK_CONFIG_JSON}"
  )
}

start_services_after_onboarding() {
  if [[ ! -x "${ROOT_DIR}/broker/start.sh" ]]; then
    fail "broker/start.sh not found or not executable at ${ROOT_DIR}/broker/start.sh"
  fi
  if [[ ! -x "${ROOT_DIR}/agents/start.sh" ]]; then
    fail "agents/start.sh not found or not executable at ${ROOT_DIR}/agents/start.sh"
  fi

  load_northbrook_secrets

  local broker_args=()
  broker_args+=("$(default_daemon_mode_arg)")

  local broker_log
  broker_log="$(mktemp /tmp/northbrook-onboarding-broker.XXXXXX.log)"
  if ! run_broker_start "${broker_args[@]}" >"${broker_log}" 2>&1; then
    echo "Failed to start broker daemon after onboarding." >&2
    tail -n 40 "${broker_log}" >&2 || true
    rm -f "${broker_log}"
    return 1
  fi
  rm -f "${broker_log}"

  local agents_log
  agents_log="$(mktemp /tmp/northbrook-onboarding-agents.XXXXXX.log)"
  if ! run_agents_start >"${agents_log}" 2>&1; then
    echo "Failed to start agents daemon after onboarding." >&2
    tail -n 40 "${agents_log}" >&2 || true
    rm -f "${agents_log}"
    return 1
  fi
  rm -f "${agents_log}"

  return 0
}

bind_nb_command() {
  local cli_script="${ROOT_DIR}/terminal/cli/nb.sh"
  local nb_path="${NB_BIN_DIR}/nb"

  [[ -f "${cli_script}" ]] || fail "CLI entry point not found at ${cli_script}"

  chmod +x "${cli_script}"
  mkdir -p "${NB_BIN_DIR}"
  ln -sfn "${cli_script}" "${nb_path}"
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

find_installed_ib_gateway_app() {
  local app_path=""

  for app_path in "/Applications/IB Gateway.app" "${HOME}/Applications/IB Gateway.app"; do
    if is_valid_gateway_app_bundle "${app_path}"; then
      printf '%s\n' "${app_path}"
      return 0
    fi
  done

  local root=""
  for root in \
    "${IB_INSTALL_DIR}" \
    "/Applications/IB Gateway" \
    "${HOME}/Applications/IB Gateway"; do
    if app_path="$(resolve_ib_gateway_app_from_root "${root}")"; then
      printf '%s\n' "${app_path}"
      return 0
    fi
  done

  return 1
}

install_ib_app() {
  case "${INSTALL_IB_APP,,}" in
    1|true|yes|on) ;;
    0|false|no|off)
      return 0
      ;;
    *)
      ;;
  esac

  if [[ "$(uname -s)" != "Darwin" ]]; then
    return 0
  fi

  local existing_app=""
  if existing_app="$(find_installed_ib_gateway_app)"; then
    return 0
  fi

  local ib_arch=""
  if [[ "$(uname -m)" == "arm64" ]]; then
    ib_arch="macos-arm"
  elif [[ "$(uname -m)" == "x86_64" ]]; then
    ib_arch="macos-x64"
  else
    fail "Unsupported macOS architecture: $(uname -m). Install IB Gateway manually."
  fi

  case "${IB_CHANNEL}" in
    stable|latest) ;;
    *) fail "Invalid BROKER_IB_CHANNEL='${IB_CHANNEL}' (expected stable|latest)." ;;
  esac

  command -v curl >/dev/null 2>&1 || fail "curl is required to download IB Gateway installer."
  command -v hdiutil >/dev/null 2>&1 || fail "hdiutil is required to mount the IB Gateway installer DMG."

  local dmg_url="https://download2.interactivebrokers.com/installers/ibgateway/${IB_CHANNEL}-standalone/ibgateway-${IB_CHANNEL}-standalone-${ib_arch}.dmg"
  local tmp_dir
  tmp_dir="$(mktemp -d /tmp/broker-ibgateway.XXXXXX)"
  local dmg_path="${tmp_dir}/ibgateway.dmg"
  local mount_point="${tmp_dir}/mnt"
  mkdir -p "${mount_point}"

  if ! curl --fail --location --retry 3 --connect-timeout 20 --output "${dmg_path}" "${dmg_url}"; then
    rm -rf "${tmp_dir}"
    fail "Failed to download IB Gateway installer from ${dmg_url}"
  fi

  if ! hdiutil attach "${dmg_path}" -mountpoint "${mount_point}" -nobrowse -quiet; then
    rm -rf "${tmp_dir}"
    fail "Failed to mount installer DMG."
  fi

  local installer_stub=""
  if [[ -x "${mount_point}/IB Gateway Installer.app/Contents/MacOS/JavaApplicationStub" ]]; then
    installer_stub="${mount_point}/IB Gateway Installer.app/Contents/MacOS/JavaApplicationStub"
  fi

  if [[ -z "${installer_stub}" || ! -x "${installer_stub}" ]]; then
    hdiutil detach "${mount_point}" -quiet || true
    rm -rf "${tmp_dir}"
    fail "Could not locate installer at ${mount_point}/IB Gateway Installer.app/Contents/MacOS/JavaApplicationStub"
  fi

  mkdir -p "$(dirname "${IB_INSTALL_DIR}")"
  if ! "${installer_stub}" -q -overwrite -dir "${IB_INSTALL_DIR}"; then
    hdiutil detach "${mount_point}" -quiet || true
    rm -rf "${tmp_dir}"
    fail "Silent IB Gateway install failed."
  fi

  hdiutil detach "${mount_point}" -quiet || true
  rm -rf "${tmp_dir}"

  if ! find_installed_ib_gateway_app >/dev/null 2>&1; then
    fail "Install finished but IB Gateway app was not found in expected locations. Set BROKER_IB_INSTALL_DIR and rerun."
  fi
}

install_ibc() {
  local os_name
  os_name="$(uname -s)"
  local asset_name=""
  case "${os_name}" in
    Darwin)
      asset_name="IBCMacos"
      ;;
    Linux)
      asset_name="IBCLinux"
      ;;
    *)
      return 0
      ;;
  esac

  command -v curl >/dev/null 2>&1 || fail "curl is required to download IBC."
  command -v unzip >/dev/null 2>&1 || fail "unzip is required to install IBC."
  command -v python3 >/dev/null 2>&1 || fail "python3 is required to resolve IBC release assets."

  local api_url=""
  if [[ "${IBC_RELEASE_TAG}" == "latest" ]]; then
    api_url="https://api.github.com/repos/IbcAlpha/IBC/releases/latest"
  else
    api_url="https://api.github.com/repos/IbcAlpha/IBC/releases/tags/${IBC_RELEASE_TAG}"
  fi

  local tmp_dir
  tmp_dir="$(mktemp -d /tmp/northbrook-ibc.XXXXXX)"
  local release_json="${tmp_dir}/release.json"
  local zip_path="${tmp_dir}/ibc.zip"

  if ! curl --fail --location --retry 3 --connect-timeout 20 --output "${release_json}" "${api_url}"; then
    rm -rf "${tmp_dir}"
    fail "Failed to resolve IBC release metadata from ${api_url}"
  fi

  local resolved_url=""
  resolved_url="$(python3 - "${release_json}" "${asset_name}" <<'PY'
import json
import sys
from pathlib import Path

release_path = Path(sys.argv[1])
asset_prefix = sys.argv[2]
payload = json.loads(release_path.read_text(encoding="utf-8"))
assets = payload.get("assets")
if not isinstance(assets, list):
    sys.exit(1)
for asset in assets:
    if not isinstance(asset, dict):
        continue
    name = asset.get("name")
    url = asset.get("browser_download_url")
    if not isinstance(name, str) or not isinstance(url, str):
        continue
    if name.startswith(asset_prefix + "-") and name.endswith(".zip"):
        print(url)
        sys.exit(0)
sys.exit(1)
PY
  )" || {
    rm -rf "${tmp_dir}"
    fail "Could not find ${asset_name} release asset for IBC (${IBC_RELEASE_TAG})."
  }

  if ! curl --fail --location --retry 3 --connect-timeout 20 --output "${zip_path}" "${resolved_url}"; then
    rm -rf "${tmp_dir}"
    fail "Failed to download IBC archive from ${resolved_url}"
  fi

  rm -rf "${IBC_INSTALL_DIR}"
  mkdir -p "${IBC_INSTALL_DIR}"
  unzip -q "${zip_path}" -d "${IBC_INSTALL_DIR}"
  chmod +x "${IBC_INSTALL_DIR}"/*.sh >/dev/null 2>&1 || true
  chmod +x "${IBC_INSTALL_DIR}/scripts"/*.sh >/dev/null 2>&1 || true

  if [[ ! -f "${IBC_INSTALL_DIR}/config.ini" ]]; then
    rm -rf "${tmp_dir}"
    fail "IBC install is missing config.ini at ${IBC_INSTALL_DIR}."
  fi
  chmod 700 "${IBC_INSTALL_DIR}"
  chmod 600 "${IBC_INSTALL_DIR}/config.ini"

  rm -rf "${tmp_dir}"
}

create_python_runtime() {
  cd "${BROKER_DIR}"
  uv venv --python "${PYTHON_VERSION}" --seed --allow-existing
}

install_python_packages() {
  cd "${BROKER_DIR}"
  .venv/bin/python -m pip install -e './daemon[dev]' -e './sdk/python[dev]' -e './cli[dev]'
  if command -v direnv >/dev/null 2>&1; then
    direnv allow "${BROKER_DIR}" >/dev/null 2>&1 || true
  fi
}

install_typescript_packages() {
  (
    cd "${BROKER_DIR}/sdk/typescript"
    bun install
  )
  (
    cd "${ROOT_DIR}/agents"
    bun install
  )
  (
    cd "${ROOT_DIR}/terminal"
    bun install
  )
}

run_python_tests() {
  cd "${BROKER_DIR}"
  .venv/bin/python -m pytest daemon/tests cli/tests sdk/python/tests -q
}

run_typescript_typechecks() {
  (
    cd "${BROKER_DIR}/sdk/typescript"
    bun run typecheck
  )
  (
    cd "${ROOT_DIR}/agents"
    bun run typecheck
  )
  (
    cd "${ROOT_DIR}/terminal"
    bun run typecheck
  )
}

print_summary() {
  cat <<SUMMARY

${BOLD}${GREEN}Northbrook install complete.${RESET}

${BOLD}Paths${RESET}
- Data home: ${NORTHBROOK_HOME}
- Secrets config: ${NORTHBROOK_CONFIG_JSON}
- Workspace repo: ${NORTHBROOK_WORKSPACE}

${BOLD}Platform overview${RESET}
- terminal: human command center for portfolio, risk, agents, and events
- broker: execution layer with risk controls, audit trail, and daemon runtime
- agents: background runtime for agent services (heartbeats/scheduler stubs + scheduled jobs)
- workspace: your instance-specific git repo for files like risk.json

${BOLD}Quickstart${RESET}
Next step: ${BOLD}nb${RESET}
1. Launch terminal + daemon: ${BOLD}nb${RESET}
2. Broker + agents daemons keep running in background; check with: ${BOLD}nb status${RESET}
3. Service controls: ${BOLD}nb start${RESET} / ${BOLD}nb stop${RESET} / ${BOLD}nb restart${RESET}
4. Scheduled jobs skill: ${BOLD}nb jobs --help${RESET}
5. Rerun onboarding anytime: ${BOLD}nb setup${RESET}
6. Workspace repo for instance files: ${BOLD}${NORTHBROOK_WORKSPACE}${RESET}

${DIM}Tip: if 'nb' is not found, add ${NB_BIN_DIR} to PATH and reopen your shell.${RESET}
SUMMARY
}

if [[ ! -d "${BROKER_DIR}" ]]; then
  ensure_source_checkout
fi

if [[ "${ONBOARDING_ONLY}" -eq 1 ]]; then
  banner
  prepare_northbrook_home
  ensure_northbrook_secrets_config
  run_onboarding_wizard
  if [[ "${ONBOARDING_INTERACTIVE}" -eq 1 ]]; then
    echo
    echo "Starting background services..."
    start_services_after_onboarding
  fi
  rm -rf "${LOG_DIR}"
  exit 0
fi

banner
run_step "Preparing Northbrook data home" prepare_northbrook_home
run_step "Bootstrapping system tooling (Homebrew, uv, bun)" bootstrap_tooling
run_step "Initializing workspace git repository" init_workspace_repo
run_step "Creating secrets config (${NORTHBROOK_CONFIG_JSON})" ensure_northbrook_secrets_config
run_step "Interactive Brokers Gateway setup" install_ib_app
run_step "Installing IBC automation package" install_ibc
run_step "Creating Python runtime" create_python_runtime
run_step "Installing Python packages" install_python_packages
run_step "Installing TypeScript packages (bun)" install_typescript_packages
run_step "Running Python test suite" run_python_tests
run_step "Running TypeScript typechecks" run_typescript_typechecks
run_step "Finalizing CLI command binding" bind_nb_command

if [[ "${SKIP_ONBOARDING}" -eq 0 ]]; then
  run_onboarding_wizard
  if [[ "${ONBOARDING_INTERACTIVE}" -eq 1 ]]; then
    run_step "Starting background services" start_services_after_onboarding
  fi
fi

rm -rf "${LOG_DIR}"
print_summary
