# Broker CLI

`broker` is the operator CLI for `broker-daemon`.

## Prerequisites

- `broker-daemon` running (`broker daemon start`)
- IB Gateway or TWS reachable and authenticated

## Quick Commands

```bash
broker --help
broker quote AAPL MSFT
broker snapshot --symbols AAPL,MSFT
broker positions
broker order buy AAPL 5 --limit 180 --tif DAY --idempotency-key strat-42-aapl
broker order buy AAPL 5 --limit 180 --dry-run
broker chain AAPL --type call --strike-range 0.95:1.05 --limit 100 --fields strike,expiry,bid,ask
broker limits
broker audit commands --request-id <request_id>
broker schema quote.snapshot
```

## Notes

- `--help` is available on all command groups
- output is machine-first JSON in a stable envelope (`ok/data/error/meta`)
- `--strict` enables stricter empty-result validation where supported (`history`, `chain`)
- when daemon is down, run `broker daemon status` and `broker daemon start`
