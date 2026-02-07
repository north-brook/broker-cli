# North Brook

**Autonomous AI hedge fund**
Empower AI to identify, evaluate, and execute investment strategies. Stay high level or get in the details. Use fake money or real money.

## Repo Layout
- `terminal` (human interface - monitor agents, enact strategy)
- `agents` (background runtime and skills for agent services, heartbeats, and jobs)
- `broker/daemon` (execution runtime — IB connection, risk, audit)
- `broker/cli` (operator CLI for broker-daemon)
- `broker/sdk/python` and `broker/sdk/typescript` (agent-facing SDKs)

## Repo Tasks
From repo root:

```bash
bun run typecheck
bun run lint
bun run check
```

## Connections
- Interactive Brokers
- Anthropic
- OpenAI
- Google
- X API
- Brave Search
