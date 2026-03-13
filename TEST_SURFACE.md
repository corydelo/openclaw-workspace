# openclaw-workspace: Test Surface

## Snapshot

- Last reviewed: 2026-03-11
- Default validation mode: cloud-only Oracle + Signal-first

## Automated Checks

- Contract: `contract-tests/contract_test_openai_compat.py`
- Smoke: `e2e/smoke_e2e.py`
- Health gates: `/Users/corydelouche/Codex/scripts/doctor.sh`, `/Users/corydelouche/Codex/scripts/status.sh`
- Infra unit coverage: `infra/tests/test_selector.py`, `infra/tests/test_system_factory.py`
- Pin integrity: `make submodule-check`

## What Current Checks Assert

- Oracle OpenAI-compatible endpoint is reachable and authenticated.
- Signal bridge health is reachable on `:8080`.
- Oracle signal adapter status is reachable on `:8000/api/v1/signal/status`.
- Default Tier0 behavior is cloud-only; Ollama tests are explicit opt-in with `CLOUD_ONLY=false`.

## Known Gaps

- No automated remote VM validation yet for systemd/service wiring.
- Signal end-to-end message handling still requires manual allowlisted message validation.
- Negative coverage for stale host Ollama listeners is warning-oriented in shell tooling.
