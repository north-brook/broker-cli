# Agent Integration

`broker` exposes two agent surfaces:

- Request/response API through Python SDK (`broker_sdk.Client`)
- Request/response API through TypeScript SDK (`@northbrook/broker-sdk-typescript`)
- Streaming JSONL through `broker agent subscribe`

## Python SDK example

```python
import asyncio
from broker_sdk import AGENT_TOPICS, Client

async def main() -> None:
    async with Client() as ib:
        await ib.heartbeat()
        quote = await ib.quote("AAPL")
        print(quote)

        async for event in ib.subscribe([AGENT_TOPICS[0], AGENT_TOPICS[1]]):
            print(event)

asyncio.run(main())
```

## TypeScript SDK example

```ts
import { AGENT_TOPICS, Client } from "@northbrook/broker-sdk-typescript";

const ib = await Client.fromConfig();
const quote = await ib.quote("AAPL");
console.log(quote.quotes[0]);

for await (const event of ib.subscribe([AGENT_TOPICS[0], AGENT_TOPICS[1]])) {
  console.log(event.topic, event.data);
}
```

## Operational guidance

- Always call `heartbeat` periodically.
- Use `risk.check` before generating large orders.
- Consume `risk` and `connection` topics in your event stream.
