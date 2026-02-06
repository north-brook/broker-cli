# Risk Configuration

Risk limits live under `[risk]` in `~/.broker/config.toml`.

```toml
[risk]
max_position_pct = 10.0
max_order_value = 50000
max_daily_loss_pct = 2.0
max_sector_exposure_pct = 30.0
max_single_name_pct = 10.0
max_open_orders = 20
order_rate_limit = 10
duplicate_window_seconds = 60
```

Runtime updates:

```bash
broker risk set max_order_value 25000
broker risk override --param max_position_pct --value 20 --duration 1h --reason "manual"
broker risk halt
broker risk resume
```

Mutable runtime parameters for `broker risk set` / `broker risk override`:

- `max_position_pct`
- `max_order_value`
- `max_daily_loss_pct`
- `max_sector_exposure_pct`
- `max_single_name_pct`
- `max_open_orders`
- `order_rate_limit`
- `duplicate_window_seconds`
- `symbol_allowlist`
- `symbol_blocklist`
