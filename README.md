# openclaw-workspace

Canonical deploy workspace for the live Oracle runtime.

## Live Contract

- Deploy from this workspace only.
- Oracle HTTP API listens on `127.0.0.1:8000`.
- Signal bridge listens on `127.0.0.1:8080`.
- Chroma runs internal-only in Docker.
- OpenClaw gateway and VM-local Ollama are not part of the default live path.

## Repo Role

- `infra/`: pinned Oracle runtime component.
- `agent/`: pinned `sturdy-journey` mirror for Signal config, docs, and archived OpenClaw fixtures.
- `contract-tests/` and `e2e/`: workspace-level validation for the live stack.

## Standard Commands

```bash
make prepare
make upgrade
make agent-up
make infra-up
make contract-test
make e2e
make down
```

## Scaffold Upgrade

Use `make upgrade` or `bash ./bootstrap.sh upgrade` as the single scaffold-reconciliation entrypoint.

- Default behavior is approval-gated apply mode.
- `bash ./bootstrap.sh upgrade --check` is the non-destructive automation lane.
- The workflow is manifest-driven by `config/scaffold-upgrade.json`.
- The pinned Python 3.12 code-graph runtime is refreshed as part of the safe lane.

## Default Environment

- `CLOUD_ONLY=true`
- `LLM_ARCH_BASE_URL=http://127.0.0.1:8000`
- `SIGNAL_ENABLED=true`
- `SIGNAL_API_URL=http://127.0.0.1:8080`
- `ORACLE_API_KEY` required

`OLLAMA_BASE_URL` is no longer part of the default deploy contract. Local Ollama remains optional future capability only when `CLOUD_ONLY=false`.

## Legacy Scope

OpenClaw-specific configs and guides remain only for compatibility history and archive review. Do not use them as live deployment instructions.
