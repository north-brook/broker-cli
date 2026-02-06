# broker TypeScript SDK

Strictly typed TypeScript SDK for `broker-daemon`.

The Python SDK and Python CLI remain the canonical runtime tooling. This package adds TS SDK access only.

## Install

```bash
# from broker/
cd packages/sdk/typescript
npm install
npm run build
```

## Usage

```ts
import {
  AGENT_TOPICS,
  Client,
  HISTORY_PERIODS,
  ORDER_STATUS_FILTERS,
  RISK_PARAMS
} from "@northbrook/broker-sdk-typescript";

const client = await Client.fromConfig();

const status = await client.daemonStatus();
const quote = await client.quote("AAPL", "MSFT");
const history = await client.history("AAPL", HISTORY_PERIODS[2], "1h");
const orders = await client.orders(ORDER_STATUS_FILTERS[0]);
const risk = await client.riskSet(RISK_PARAMS[1], 25000);
const order = await client.order({ side: "buy", symbol: "AAPL", qty: 10, limit: 180, tif: "DAY" });

for await (const event of client.subscribe([AGENT_TOPICS[0], AGENT_TOPICS[1]])) {
  console.log(event.topic, event.data);
}
```

## Strict Typing

- `Client.request` is command-keyed and returns typed results via `CommandMap`.
- High-level SDK methods (`quote`, `order`, `riskLimits`, etc.) return explicit interfaces.
- Error handling uses typed `BrokerError` with `ErrorCode`.
- Shared constant arrays (`AGENT_TOPICS`, `RISK_PARAMS`, `HISTORY_PERIODS`, etc.) make valid values discoverable.
