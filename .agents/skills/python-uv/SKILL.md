---
name: python-uv
description: Python project management with uv. Use when creating, building, testing, or managing Python projects with pyproject.toml, uv, pytest, and related tooling.
---

# Python + uv

## Project Structure

```
project/
├── pyproject.toml          # Package metadata + dependencies
├── .python-version         # Pin Python version (e.g. "3.12")
├── uv.lock                 # Cross-platform lockfile (commit this)
├── .venv/                  # Virtual environment (gitignored)
├── src/
│   └── package_name/       # Source layout (src/)
│       ├── __init__.py
│       └── ...
├── tests/
│   ├── conftest.py
│   └── test_*/
└── README.md
```

Use **src layout** (`src/package_name/`) — prevents accidental imports from the project root.

## pyproject.toml

```toml
[build-system]
requires = ["hatchling>=1.25.0"]
build-backend = "hatchling.build"

[project]
name = "my-package"
version = "0.1.0"
description = "..."
readme = "README.md"
requires-python = ">=3.12"
license = { text = "MIT" }
dependencies = [
  "pydantic>=2.8",
  "httpx>=0.27",
]

[project.optional-dependencies]
dev = [
  "pytest>=8.3",
  "pytest-asyncio>=0.24",
  "ruff>=0.8",
]

[project.scripts]
my-cli = "my_package.main:main"

[tool.hatch.build.targets.wheel]
packages = ["src/my_package"]

[tool.pytest.ini_options]
asyncio_mode = "auto"
testpaths = ["tests"]

[tool.ruff]
target-version = "py312"
line-length = 120

[tool.ruff.lint]
select = ["E", "F", "I", "N", "UP", "RUF"]
```

## uv Commands

```bash
# Create project
uv init my-project
cd my-project

# Pin Python version
uv python pin 3.12

# Create venv + install deps
uv sync

# Add/remove dependencies
uv add pydantic httpx
uv add --dev pytest ruff
uv add --optional reauth playwright
uv remove some-package

# Run commands in project env
uv run python script.py
uv run pytest
uv run ruff check .

# Lock without syncing
uv lock

# Upgrade a specific package
uv lock --upgrade-package httpx

# Install editable in workspace
uv pip install -e ./subpackage
```

## Multi-Package Workspace

For monorepos with multiple Python packages (like daemon + CLI + SDK):

```toml
# Root pyproject.toml
[tool.uv.workspace]
members = ["daemon", "cli", "sdk/python"]
```

Each member has its own `pyproject.toml`. Cross-references use path deps:

```toml
# cli/pyproject.toml
dependencies = [
  "my-daemon",  # resolved via workspace
]

[tool.uv.sources]
my-daemon = { workspace = true }
```

## Testing with pytest

```bash
# Run all tests
uv run pytest

# Verbose with output
uv run pytest -v -s

# Run specific test file/function
uv run pytest tests/test_orders.py::test_place_order

# Run with coverage
uv run pytest --cov=src/my_package --cov-report=term-missing

# Parallel (install pytest-xdist)
uv run pytest -n auto
```

### Async tests (pytest-asyncio)

```python
import pytest

@pytest.mark.asyncio
async def test_async_operation():
    result = await some_async_func()
    assert result.ok
```

With `asyncio_mode = "auto"` in pyproject.toml, the `@pytest.mark.asyncio` decorator is optional.

### Fixtures

```python
# conftest.py
import pytest

@pytest.fixture
def sample_config():
    return {"host": "127.0.0.1", "port": 4001}

@pytest.fixture
async def async_client():
    client = AsyncClient()
    yield client
    await client.close()
```

## Type Checking

Prefer inline type hints. Use `pyright` or `mypy` for checking:

```bash
uv run pyright
# or
uv run mypy src/
```

Pydantic models provide runtime validation + type safety:

```python
from pydantic import BaseModel, Field

class Config(BaseModel):
    host: str = "127.0.0.1"
    port: int = 4001
    tags: list[str] = Field(default_factory=list)
```

## Linting + Formatting

Use **ruff** (replaces black, isort, flake8):

```bash
# Check
uv run ruff check .

# Fix auto-fixable issues
uv run ruff check --fix .

# Format
uv run ruff format .
```

## CI Script Pattern

```bash
#!/usr/bin/env bash
set -euo pipefail

uv sync --frozen          # Install from lockfile exactly
uv run ruff check .       # Lint
uv run ruff format --check .  # Format check
uv run pyright            # Type check
uv run pytest             # Tests
```

`--frozen` ensures CI uses the exact lockfile without modifying it.

## Common Patterns

### Entry points (CLI)

```toml
[project.scripts]
broker = "broker_cli.main:main"
```

```python
# src/broker_cli/main.py
import typer
app = typer.Typer()

@app.command()
def status():
    print("ok")

def main():
    app()
```

### Async main

```python
import asyncio

async def run():
    ...

def main():
    asyncio.run(run())
```

### Environment-based config

```python
import os
from pathlib import Path

CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME", "~/.config")).expanduser()
STATE_HOME = Path(os.environ.get("XDG_STATE_HOME", "~/.local/state")).expanduser()
```

### Error hierarchy

```python
from enum import Enum

class ErrorCode(str, Enum):
    INVALID_ARGS = "INVALID_ARGS"
    TIMEOUT = "TIMEOUT"
    INTERNAL = "INTERNAL"

class AppError(Exception):
    def __init__(self, code: ErrorCode, message: str, **kwargs):
        self.code = code
        self.message = message
        self.details = kwargs
        super().__init__(message)
```
