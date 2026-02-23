# Broker Daemon

`broker-daemon` is the long-running backend for broker execution.

## Responsibilities

- maintain session state to IB Gateway/TWS
- route requests from CLI/SDK clients
- persist audit events for traceability

## Interfaces

- local CLI: `broker`
- SDKs: `broker_sdk` (Python), `@broker/sdk-typescript`

## Runtime Context

Service lifecycle commands:

```bash
broker daemon start --paper
broker daemon status
broker daemon stop
```
