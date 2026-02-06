#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BROKER_DIR="${ROOT_DIR}/broker"
PYTHON_VERSION="${PYTHON_VERSION:-3.12}"
INSTALL_IB_APP="${BROKER_INSTALL_IB_APP:-1}"
IB_CHANNEL="${BROKER_IB_CHANNEL:-stable}"
IB_INSTALL_DIR="${BROKER_IB_INSTALL_DIR:-${HOME}/Applications/IB Gateway}"

if [[ ! -d "${BROKER_DIR}" ]]; then
  echo "broker workspace not found at ${BROKER_DIR}" >&2
  exit 1
fi

if ! command -v uv >/dev/null 2>&1; then
  echo "uv is required. Install with: brew install uv" >&2
  exit 1
fi

cd "${BROKER_DIR}"

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
      echo "==> Skipping IB desktop app install (BROKER_INSTALL_IB_APP=${INSTALL_IB_APP})"
      return 0
      ;;
    *)
      echo "==> Invalid BROKER_INSTALL_IB_APP value '${INSTALL_IB_APP}', defaulting to enabled"
      ;;
  esac

  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "==> Skipping IB desktop app install (only automated on macOS)"
    return 0
  fi

  local existing_app=""
  if existing_app="$(find_installed_ib_gateway_app)"; then
    echo "==> IB Gateway already present at: ${existing_app}"
    return 0
  fi

  if [[ "$(uname -m)" == "arm64" ]]; then
    IB_ARCH="macos-arm"
  elif [[ "$(uname -m)" == "x86_64" ]]; then
    IB_ARCH="macos-x64"
  else
    echo "==> Unsupported macOS architecture: $(uname -m)"
    echo "    Install IB Gateway manually."
    exit 1
  fi

  case "${IB_CHANNEL}" in
    stable|latest) ;;
    *)
      echo "==> Invalid BROKER_IB_CHANNEL='${IB_CHANNEL}' (expected stable|latest)"
      exit 1
      ;;
  esac

  if ! command -v curl >/dev/null 2>&1; then
    echo "==> curl is required to download IB Gateway installer"
    exit 1
  fi
  if ! command -v hdiutil >/dev/null 2>&1; then
    echo "==> hdiutil is required to mount IB Gateway installer DMG"
    exit 1
  fi

  local dmg_url="https://download2.interactivebrokers.com/installers/ibgateway/${IB_CHANNEL}-standalone/ibgateway-${IB_CHANNEL}-standalone-${IB_ARCH}.dmg"
  local before_pids=""
  before_pids="$(pgrep -f "IB Gateway|ibgateway" || true)"

  local tmp_dir
  tmp_dir="$(mktemp -d /tmp/broker-ibgateway.XXXXXX)"
  local dmg_path="${tmp_dir}/ibgateway.dmg"
  local mount_point="${tmp_dir}/mnt"
  mkdir -p "${mount_point}"

  echo "==> Downloading IB Gateway installer (${IB_CHANNEL}, ${IB_ARCH})"
  if ! curl --fail --location --retry 3 --connect-timeout 20 --output "${dmg_path}" "${dmg_url}"; then
    echo "==> Failed to download installer from:"
    echo "    ${dmg_url}"
    rm -rf "${tmp_dir}"
    exit 1
  fi

  echo "==> Mounting installer image"
  if ! hdiutil attach "${dmg_path}" -mountpoint "${mount_point}" -nobrowse -quiet; then
    echo "==> Failed to mount installer DMG"
    rm -rf "${tmp_dir}"
    exit 1
  fi

  local installer_stub=""
  if [[ -x "${mount_point}/IB Gateway Installer.app/Contents/MacOS/JavaApplicationStub" ]]; then
    installer_stub="${mount_point}/IB Gateway Installer.app/Contents/MacOS/JavaApplicationStub"
  fi

  if [[ -z "${installer_stub}" || ! -x "${installer_stub}" ]]; then
    echo "==> Could not locate installer at:"
    echo "    ${mount_point}/IB Gateway Installer.app/Contents/MacOS/JavaApplicationStub"
    hdiutil detach "${mount_point}" -quiet || true
    rm -rf "${tmp_dir}"
    exit 1
  fi

  echo "==> Installing IB Gateway to: ${IB_INSTALL_DIR}"
  mkdir -p "$(dirname "${IB_INSTALL_DIR}")"
  if ! "${installer_stub}" -q -overwrite -dir "${IB_INSTALL_DIR}"; then
    echo "==> Silent install failed"
    hdiutil detach "${mount_point}" -quiet || true
    rm -rf "${tmp_dir}"
    exit 1
  fi

  hdiutil detach "${mount_point}" -quiet || true
  rm -rf "${tmp_dir}"

  local installed_app=""
  if installed_app="$(find_installed_ib_gateway_app)"; then
    :
  fi

  if [[ -z "${installed_app}" ]]; then
    echo "==> Install finished but IB Gateway app was not found in expected locations."
    echo "    Set BROKER_IB_INSTALL_DIR and rerun, or install manually."
    exit 1
  fi

  echo "==> Installed IB Gateway app: ${installed_app}"

  local after_pids=""
  after_pids="$(pgrep -f "IB Gateway|ibgateway" || true)"
  if [[ -n "${after_pids}" ]]; then
    local pid
    for pid in ${after_pids}; do
      if [[ -z "${before_pids}" ]] || ! printf '%s\n' "${before_pids}" | grep -qx "${pid}"; then
        kill -TERM "${pid}" >/dev/null 2>&1 || true
      fi
    done
  fi
}

install_ib_app

echo "==> Ensuring virtual environment (.venv)"
uv venv --python "${PYTHON_VERSION}" --seed --allow-existing

echo "==> Installing Python package dependencies"
.venv/bin/python -m pip install -e './packages/daemon[dev]' -e './packages/sdk/python[dev]' -e './packages/cli[dev]'

if command -v direnv >/dev/null 2>&1; then
  echo "==> Allowing direnv for broker/"
  direnv allow "${BROKER_DIR}" >/dev/null 2>&1 || true
fi

if command -v npm >/dev/null 2>&1; then
  echo "==> Installing TypeScript SDK dependencies"
  (
    cd packages/sdk/typescript
    npm install
  )
else
  echo "npm not found; skipped TypeScript SDK dependency install"
fi

echo "==> Running test suite"
.venv/bin/python -m pytest packages/daemon/tests packages/cli/tests packages/sdk/python/tests -q

if command -v npm >/dev/null 2>&1; then
  echo "==> Running TypeScript SDK typecheck"
  (
    cd packages/sdk/typescript
    npm run typecheck
  )
fi

echo "Build completed successfully."
