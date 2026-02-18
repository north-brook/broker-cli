# shellcheck shell=bash

init_broker_common_paths() {
  BROKER_CONFIG_HOME="${BROKER_CONFIG_HOME:-${XDG_CONFIG_HOME:-${HOME}/.config}/broker}"
  BROKER_CONFIG_JSON="${BROKER_CONFIG_JSON:-${BROKER_CONFIG_HOME}/config.json}"
  BROKER_STATE_HOME="${BROKER_STATE_HOME:-${XDG_STATE_HOME:-${HOME}/.local/state}/broker}"
  BROKER_DATA_HOME="${BROKER_DATA_HOME:-${XDG_DATA_HOME:-${HOME}/.local/share}/broker}"
  BROKER_BIN_DIR="${BROKER_BIN_DIR:-${HOME}/.local/bin}"
}

init_broker_terminal() {
  local mode="${1:-stdio}"

  if [[ -t 1 ]]; then
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

  INTERACTIVE=0
  case "${mode}" in
    tty-io)
      if [[ -t 1 && -r /dev/tty && -w /dev/tty ]]; then
        INTERACTIVE=1
      fi
      ;;
    stdout)
      if [[ -t 1 ]]; then
        INTERACTIVE=1
      fi
      ;;
    stdio|*)
      if [[ -t 0 && -t 1 ]]; then
        INTERACTIVE=1
      fi
      ;;
  esac
}
