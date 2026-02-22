# openclaw-workspace: Architecture

## Snapshot
- Last reviewed: 2026-02-17
- Commit: `87657a6`
- Working tree at review: dirty (Makefile, contract test, submodule state, runtime artifacts)

## First-Read Files
- `AGENTS.md`
- `Makefile`
- `bootstrap.sh`
- `.gitmodules`
- `contract-tests/contract_test_openai_compat.py`
- `e2e/smoke_e2e.py`

## Repo Role
This repo is an integration harness for the full stack:
- `infra/` submodule (LLM-Architecture)
- `agent/` submodule (sturdy-journey)
- Integration checks in `contract-tests/` and `e2e/`

## Bring-Up Flow (`make up`)
`make up` -> `./bootstrap.sh up` ->
1. Ensure root `.env` (`ORACLE_API_KEY`, `LLM_ARCH_BASE_URL`).
2. Ensure `infra/.env` and `agent/config/.env` are present and synced.
3. Sync + verify submodule pins.
4. Install infra deps in `infra/venv`.
5. Start agent compose stack.
6. Start infra uvicorn app.
7. Run contract test (`contract-tests/contract_test_openai_compat.py`).

## Source-of-Truth Commands
From `Makefile`:
- `make sync`
- `make up`
- `make down`
- `make contract-test`
- `make e2e`
- `make submodule-check`

## Environment and Auth Coupling
- Workspace root `.env` drives integration-level values.
- `bootstrap.sh` propagates `ORACLE_API_KEY` and Oracle base URL into agent + infra env files.
- Contract test reads `.env` and hits `/v1/chat/completions` with bearer key when present.

## Operational Commands
```bash
# Sync pinned submodules
make sync

# Full bring-up + contract test
make up

# Contract only
make contract-test

# E2E smoke
make e2e

# Tear down
make down
```

## Subsystems & Capabilities
- **Prompt Caching**: The `OrchestratorAgent` utilizes Prompt Caching Architecture v2 (ID-056) to optimize LLM calls.
- **System Governance (Thread 6)**: The system enforces terminal states for governance artifacts, requiring ledger entries for accepted changes and utilizing refusal language for missing terminal artifacts.
- **Security & Autonomy**: The agent architecture includes a dedicated security review subsystem, Docker isolation for runtime evaluation, and an autonomous learning loop with context drift detection.
- **Execution Topology**: The execution flow relies on a localized Graph Orchestrator, Execution Dispatcher, and Code Factory Loop synced between the agent codebase and `llm-architecture`.

## Cost & Routing Strategy
The workspace utilizes a Venice burn configuration with a daily token budget of 0 (letting Venice enforce the quota). It falls back to the `eco` profile to prioritize free and then cheaper API tiers.

## Living-Doc Maintenance
Update this file whenever:
- Makefile targets change semantics.
- bootstrap env propagation logic changes.
- submodule paths/urls or integration boundaries change.
