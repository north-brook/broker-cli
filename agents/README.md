# agents

Background agents daemon for Northbrook.

- Runtime: TypeScript via Bun
- Persistent state: `~/.northbrook/agents`
- Jobs file: `~/.northbrook/workspace/scheduled-jobs.json`
- Planned framework alignment: `pi.dev`

## Service scripts

```bash
./agents/start.sh
./agents/status.sh
./agents/stop.sh
```

## Scheduled jobs skill

```bash
./agents/jobs.sh create --agent alpha --in 30m --prompt "Rebalance watchlist"
./agents/jobs.sh list
./agents/jobs.sh edit <job_id> --in 2h
./agents/jobs.sh remove <job_id>
```

The daemon currently includes a stub executor that marks due jobs as `queued_for_pi_dev` and logs execution intents for future pi.dev loop integration.
