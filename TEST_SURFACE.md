# openclaw-workspace: Test Surface

## Snapshot
- Last reviewed: 2026-02-17
- Commit: `87657a6`

## Current Automated Checks
- Contract: `contract-tests/contract_test_openai_compat.py`
- E2E smoke: `e2e/smoke_e2e.py`
- Pin integrity: `make submodule-check`

## Contract Test Behavior
`contract-tests/contract_test_openai_compat.py` validates:
- Infra endpoint reachability.
- OpenAI-compatible response shape keys (`id`, `object`, `created`, `model`, `choices`).
- Content assertion for prompt "Reply with exactly: ok".
- Optional `x_oracle` metadata readout.

## E2E Behavior
`e2e/smoke_e2e.py` is currently a placeholder that prints intended next steps and does not assert behavior.

## Standard Commands
```bash
# Full integration bring-up and contract test
make up

# Contract test only
make contract-test

# Placeholder e2e smoke
make e2e

# Validate submodule pin cleanliness
make submodule-check
```

## Coverage Gaps
- No real end-to-end assertions across agent -> infra -> response.
- No health-check gate before running E2E test.
- No negative tests (bad API key, missing env, infra unavailable).
- Contract test asserts exact content `ok`, which can be brittle across model behavior changes.

## Suggested Next Additions
- Replace `e2e/smoke_e2e.py` placeholder with real request/response assertions.
- Add a deterministic health target (`make health`) used by both contract and E2E flows.
- Add a contract test variant for auth failure and malformed payload handling.

## Living-Doc Maintenance
Update this file when test scripts, acceptance criteria, or make targets change.
