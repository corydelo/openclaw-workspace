# openclaw-workspace

Integration workspace for OpenClaw agent (`agent/`) and LLM architecture (`infra/`).

## Quick Commands

```bash
make sync
make up
make contract-test
make e2e
make down
```

## Code Factory Migration

This workspace now includes a deterministic Code Factory loop for autonomous routine changes.

### Added contract and gates

- Contract: `.code-factory.yaml`
- Schema: `.code-factory.schema.json`
- Preflight gate: `scripts/preflight.sh`
- CI workflow: `.github/workflows/code-factory-preflight-gate.yml`
- Contract validator: `scripts/validate_contract.py`
- Example queue: `tasks/tasks.json`
- Operations runbook: `docs/code-factory-operations.md`

### Loop behavior

The loop runs this sequence per task:

1. Claim next pending task from `tasks/tasks.json`
2. Run implementation command
3. Run deterministic preflight gate
4. Run reviewer sub-agent decision
5. Record ship result and update contract merge history
6. Emit heartbeat and trace to:
- `logs/session.jsonl`
- `logs/factory-trace.sqlite`

### Start the autonomous loop

```bash
make factory-loop
```

or directly:

```bash
cd infra
python3 -m src.agents.factory_loop --tasks ../tasks/tasks.json
```

### Run gate manually

```bash
./scripts/preflight.sh
./scripts/preflight.sh infra/src/agents/workflows.py
```

### Operational overrides

```bash
CODE_FACTORY_SHIP_MODE_OVERRIDE=report_only make factory-loop
touch .pause-autonomous
```
