# sdk/python

Async Python SDK for `broker-daemon`.

## Install

```bash
pip install broker-sdk-python
```

Local workspace install (for broker development):

```bash
# from broker/
.venv/bin/python -m pip install -e './packages/daemon[dev]' -e './packages/sdk/python[dev]'
```

## Import Surface

```python
from broker_sdk import (
    Client,
    AGENT_TOPICS,
    ORDER_SIDES,
    TIME_IN_FORCE_VALUES,
    RISK_PARAMS,
)
```

## Example

```python
import asyncio
from broker_sdk import Client

async def main() -> None:
    async with Client() as broker:
        status = await broker.daemon_status()
        quote = await broker.quote("AAPL", "MSFT")
        check = await broker.risk_check(side="buy", symbol="AAPL", qty=25, tif="DAY")
        if check["ok"]:
            await broker.order(side="buy", symbol="AAPL", qty=25, limit=180.0, tif="DAY")

asyncio.run(main())
```

## Method Groups

- Daemon: `daemon_status`, `daemon_stop`
- Market: `quote`, `history`, `chain`
- Orders: `order`, `bracket`, `order_status`, `orders`, `cancel`, `cancel_all`, `fills`
- Portfolio: `positions`, `pnl`, `balance`, `exposure`
- Risk: `risk_check`, `risk_limits`, `risk_set`, `risk_halt`, `risk_resume`, `risk_override`
- Agent: `heartbeat`, `subscribe`
- Audit: `audit_commands`, `audit_orders`, `audit_risk`, `audit_export`

The SDK connects only to `broker-daemon`, so daemon-side risk checks and audit logging are always applied.
