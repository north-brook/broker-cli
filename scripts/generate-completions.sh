#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BROKER_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUT_DIR="${1:-${BROKER_ROOT}/completions}"

if [[ -n "${BROKER_BIN:-}" ]]; then
  BROKER_CMD="${BROKER_BIN}"
elif [[ -x "${BROKER_ROOT}/.venv/bin/broker" ]]; then
  BROKER_CMD="${BROKER_ROOT}/.venv/bin/broker"
else
  BROKER_CMD="broker"
fi

mkdir -p "${OUT_DIR}"

echo "Generating broker shell completion scripts into ${OUT_DIR}"

env "_BROKER_COMPLETE=source_bash" "${BROKER_CMD}" > "${OUT_DIR}/broker.bash"
echo "  wrote ${OUT_DIR}/broker.bash"

# Typer's generated zsh file defines _broker_completion and then compdef's it.
# Installer writes this file to _broker, so it must export a _broker function.
cat > "${OUT_DIR}/broker.zsh" <<'EOF'
#compdef broker

_broker() {
  eval $(env _TYPER_COMPLETE_ARGS="${words[1,$CURRENT]}" _BROKER_COMPLETE=complete_zsh broker)
}
EOF
echo "  wrote ${OUT_DIR}/broker.zsh"

env "_BROKER_COMPLETE=source_fish" "${BROKER_CMD}" > "${OUT_DIR}/broker.fish"
echo "  wrote ${OUT_DIR}/broker.fish"

echo "Done."
