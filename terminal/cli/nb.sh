#!/usr/bin/env bash
set -euo pipefail

# Northbrook CLI entry point.
# Symlinked as `nb` by the installer (bind_nb_command).

# Resolve ROOT_DIR through symlinks.
SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [[ -L "${SCRIPT_SOURCE}" ]]; do
  SCRIPT_DIR="$(cd -P "$(dirname "${SCRIPT_SOURCE}")" && pwd)"
  SCRIPT_SOURCE="$(readlink "${SCRIPT_SOURCE}")"
  if [[ "${SCRIPT_SOURCE}" != /* ]]; then
    SCRIPT_SOURCE="${SCRIPT_DIR}/${SCRIPT_SOURCE}"
  fi
done
CLI_DIR="$(cd -P "$(dirname "${SCRIPT_SOURCE}")" && pwd)"
ROOT_DIR="$(cd -P "${CLI_DIR}/../.." && pwd)"

NORTHBROOK_HOME="${NORTHBROOK_HOME:-${HOME}/.northbrook}"
NORTHBROOK_CONFIG_JSON="${NORTHBROOK_HOME}/northbrook.json"
NORTHBROOK_WORKSPACE="${NORTHBROOK_HOME}/workspace"

export PATH="/opt/homebrew/bin:/usr/local/bin:/home/linuxbrew/.linuxbrew/bin:${HOME}/.bun/bin:${PATH}"

# Source shared helpers.
source "${CLI_DIR}/_lib.sh"

print_nb_help() {
  cat <<'HELP'
Northbrook CLI

Usage:
  nb                    Launch terminal (ensures broker + agents daemons are up)
  nb setup              Run onboarding wizard
  nb reset [--yes]      Wipe ~/.northbrook and reinitialize defaults (asks for confirmation)
  nb status             Show gateway, broker daemon, and agents daemon status
  nb update             Pull latest source and rerun installer
  nb start [args]       Start broker + agents daemons
  nb restart [args]     Restart broker + agents daemons
  nb stop               Stop broker + agents daemons
  nb jobs ...           Scheduled-jobs skill CLI

Terminal flags:
  nb --screen=NAME
  nb --paper | --live
  nb --gateway HOST:PORT
  nb --daemon-help

Job examples:
  nb jobs create --agent analyst-1 --in 30m --prompt "Scan earnings movers"
  nb jobs list
  nb jobs edit <job_id> --in 2h
  nb jobs remove <job_id>
HELP
}

subcommand="${1:-}"
case "${subcommand}" in
  setup)
    shift
    exec "${ROOT_DIR}/install.sh" --onboarding-only "$@"
    ;;
  reset)
    shift
    source "${CLI_DIR}/reset.sh"
    exit $?
    ;;
  status)
    shift
    source "${CLI_DIR}/status.sh"
    exit 0
    ;;
  update)
    shift
    if ! command -v git >/dev/null 2>&1; then
      echo "git is required for nb update. Run ./install.sh first." >&2
      exit 1
    fi
    if [[ ! -d "${ROOT_DIR}/.git" ]]; then
      echo "No git metadata at ${ROOT_DIR}; rerunning installer." >&2
      exec "${ROOT_DIR}/install.sh" --skip-onboarding
    fi
    if ! git -C "${ROOT_DIR}" diff --quiet || ! git -C "${ROOT_DIR}" diff --cached --quiet; then
      echo "Local changes detected in ${ROOT_DIR}; commit/stash before running nb update." >&2
      exit 1
    fi
    git -C "${ROOT_DIR}" fetch --depth=1 origin main
    git -C "${ROOT_DIR}" merge --ff-only origin/main
    exec "${ROOT_DIR}/install.sh" --skip-onboarding
    ;;
  start)
    shift
    if [[ ! -x "${ROOT_DIR}/broker/start.sh" ]]; then
      echo "broker/start.sh not found or not executable at ${ROOT_DIR}/broker/start.sh" >&2
      exit 1
    fi
    if [[ ! -x "${ROOT_DIR}/agents/start.sh" ]]; then
      echo "agents/start.sh not found or not executable at ${ROOT_DIR}/agents/start.sh" >&2
      exit 1
    fi
    load_northbrook_secrets
    run_broker_start "$@"
    run_agents_start
    exit $?
    ;;
  restart)
    shift
    if [[ ! -x "${ROOT_DIR}/broker/start.sh" ]]; then
      echo "broker/start.sh not found or not executable at ${ROOT_DIR}/broker/start.sh" >&2
      exit 1
    fi
    if [[ ! -x "${ROOT_DIR}/broker/stop.sh" ]]; then
      echo "broker/stop.sh not found or not executable at ${ROOT_DIR}/broker/stop.sh" >&2
      exit 1
    fi
    if [[ ! -x "${ROOT_DIR}/agents/start.sh" ]]; then
      echo "agents/start.sh not found or not executable at ${ROOT_DIR}/agents/start.sh" >&2
      exit 1
    fi
    if [[ ! -x "${ROOT_DIR}/agents/stop.sh" ]]; then
      echo "agents/stop.sh not found or not executable at ${ROOT_DIR}/agents/stop.sh" >&2
      exit 1
    fi
    load_northbrook_secrets
    run_agents_stop >/dev/null 2>&1 || true
    "${ROOT_DIR}/broker/stop.sh" >/dev/null 2>&1 || true
    run_broker_start "$@"
    run_agents_start
    exit $?
    ;;
  stop)
    shift
    if [[ ! -x "${ROOT_DIR}/broker/stop.sh" ]]; then
      echo "broker/stop.sh not found or not executable at ${ROOT_DIR}/broker/stop.sh" >&2
      exit 1
    fi
    if [[ ! -x "${ROOT_DIR}/agents/stop.sh" ]]; then
      echo "agents/stop.sh not found or not executable at ${ROOT_DIR}/agents/stop.sh" >&2
      exit 1
    fi
    run_agents_stop
    "${ROOT_DIR}/broker/stop.sh" "$@"
    exit $?
    ;;
  jobs)
    shift
    if [[ ! -x "${ROOT_DIR}/agents/jobs.sh" ]]; then
      echo "agents/jobs.sh not found or not executable at ${ROOT_DIR}/agents/jobs.sh" >&2
      exit 1
    fi
    exec "${ROOT_DIR}/agents/jobs.sh" "$@"
    ;;
  help|-h|--help)
    print_nb_help
    exit 0
    ;;
  run)
    shift
    source "${CLI_DIR}/tui.sh"
    ;;
  *)
    source "${CLI_DIR}/tui.sh"
    ;;
esac
