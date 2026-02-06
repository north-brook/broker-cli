# Quickstart

## 1) One-Time Machine Setup (macOS + zsh)

```bash
brew install pyenv uv pipx direnv
pipx ensurepath
```

Add this block to `~/.zshrc`:

```bash
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

export PIP_REQUIRE_VIRTUALENV=true

if command -v direnv >/dev/null 2>&1; then
  eval "$(direnv hook zsh)"
fi
```

Restart shell:

```bash
exec zsh
```

Install/select Python:

```bash
pyenv install 3.12.12
pyenv global 3.12.12
```

## 2) Bootstrap Broker Workspace

```bash
cd broker
uv venv --python 3.12 --seed
direnv allow
.venv/bin/python -m pip install -e './packages/daemon[dev]' -e './packages/sdk/python[dev]' -e './packages/cli[dev]'
```

Notes:

- `.envrc` auto-activates `.venv` when you `cd broker`.
- There is no `requirements.txt`; package dependencies are managed via `pyproject.toml`.

Optional TypeScript SDK setup:

```bash
cd packages/sdk/typescript
npm install
npm run build
```

## 3) Start and Authenticate IB Gateway

`broker` does not embed IB Gateway. Gateway must be installed and logged in.

- Authentication is handled by IB Gateway (IBKR credentials + 2FA).
- No API key is required for the Gateway socket API.
- Common Gateway API ports: paper/live = `4002` / `4001`.

From repo root, `./build.sh` can install IB Gateway directly from the official installer URL.

Optional install controls:

```bash
BROKER_INSTALL_IB_APP=0 ./build.sh             # skip IB install step
BROKER_IB_CHANNEL=latest ./build.sh            # stable|latest (default stable)
BROKER_IB_INSTALL_DIR="$HOME/Applications/IB Gateway" ./build.sh
```

## 4) Configure

Create `~/.broker/config.toml`:

```toml
[gateway]
host = "127.0.0.1"
port = 4002
client_id = 1
```

## 5) Run daemon

```bash
broker daemon start --paper
broker daemon status
```

From repository root, the wrapper script now includes IB app bootstrap behavior:

```bash
./start.sh
```

- On macOS, `./start.sh` attempts to launch local `IB Gateway.app` if no IB API listener is detected.
- It targets `IB Gateway.app`.
- It then starts/restarts broker-daemon and prints connection diagnostics.

Useful wrapper flags:

```bash
./start.sh --no-launch-ib
./start.sh --ib-app-path "/Applications/IB Gateway.app"
./start.sh --ib-wait 60
```

## 6) Use CLI

```bash
broker --help
broker quote AAPL MSFT
broker positions
broker limits
```

If you mistype a command, the CLI returns close-match suggestions (for example `qoute` -> `quote`).

## 7) Stop daemon

```bash
broker daemon stop
```

## 8) Optional: Generate Shell Completions

```bash
bash scripts/generate-completions.sh
```

See `docs/hardening-testing.md` for full hardening, recovery/load testing, and completion workflows.
