# broker-cli

Multi-component project: Python daemon + Bun CLI + Bun SDK + Next.js website.

## Structure
- `daemon/` — Python (uv, pytest). The core trading daemon.
- `cli/` — Bun/TypeScript CLI client.
- `sdk/` — Bun/TypeScript SDK.
- `website/` — Next.js marketing site at brokercli.com.
- `scripts/` — Build/release scripts.
- `install/` — Installation helpers.

## Development
- Daemon: `cd daemon && uv sync && uv run pytest`
- CLI/SDK: `bun install && bun run build`
- Website: `cd website && bun install && bun dev`

## Co-author
Always include: `Co-authored-by: Bryce Bjork <brycedbjork@gmail.com>`
