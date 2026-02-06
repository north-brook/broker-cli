# daemon

Daemon/runtime package for IB execution:

- `broker-daemon` process and command routing
- IB connection manager
- risk/audit engines
- shared protocol and domain models consumed by Python/TS SDKs

## Reliability and Tests

- Validation hardening for malformed RPC payloads (`INVALID_ARGS` with suggestions)
- Connection error mapping (`IB_DISCONNECTED`, `TIMEOUT`, `INVALID_SYMBOL`, `IB_REJECTED`)
- Recovery and stress tests under `tests/test_daemon/`
