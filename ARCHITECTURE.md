# openclaw-workspace: Architecture

## Snapshot

- Last reviewed: 2026-03-11
- Runtime posture: cloud-only Oracle, Signal-first ingress

## Runtime Topology

- `openclaw-workspace/infra`: Oracle FastAPI runtime on `127.0.0.1:8000`
- `openclaw-workspace/agent/docker/docker-compose.yml`: Signal bridge + Chroma only
- `openclaw-workspace/agent/archive/`: archived OpenClaw config fixtures, not live runtime state

## Bring-Up Flow

`make up` runs:

1. `bootstrap.sh prepare`
2. `bootstrap.sh agent-up`
3. `bootstrap.sh infra-up`
4. `contract-tests/contract_test_openai_compat.py`

## Scaffold Maintenance

- Canonical scaffold reconciliation entrypoint: `bash ./bootstrap.sh upgrade`
- Automation-safe dry run: `bash ./bootstrap.sh upgrade --check`
- Policy source: `openclaw-workspace/config/scaffold-upgrade.json`
- Safe lane currently refreshes workspace bootstrap state, the pinned code-graph Python 3.12 env, and verification guards

## Ingress Policy

- Primary ingress: Signal via Oracle `SignalAdapter`
- Secondary ingress: authenticated HTTP `/v1/chat/completions`
- Internal memory: Chroma only

## Environment Contract

- Required: `ORACLE_API_KEY`, `LLM_ARCH_BASE_URL`, `SIGNAL_ENABLED`, `SIGNAL_NUMBER`, `SIGNAL_API_URL`, `SIGNAL_WHITELIST`
- Default safety controls: `WORKFLOW_APPROVAL_MODE`, `WORKFLOW_TOKEN_BUDGET`
- Optional local-model path: set `CLOUD_ONLY=false` and explicitly provide `OLLAMA_BASE_URL`

## Source of Truth

- Live deployment orchestration: this workspace
- Canonical agent authoring repo: `../sturdy-journey`
- Canonical Oracle authoring repo remains upstream, but live startup is expected from `openclaw-workspace/infra`
