# Codex Instructions — Integrated System Repo

## Objective
Treat this repo as the source of truth for running the full system:
- bring up infra + agent
- run contract tests (interface)
- run e2e smoke tests (behavior)

## Repo layout
- ./infra  (submodule: LLM-Architecture)
- ./agent  (submodule: sturdy-journey)
- ./contract-tests
- ./e2e
- ./scripts

## Golden path commands (Codex should prefer these)
- Setup submodules: `make sync`
- Bring system up: `make up`
- Contract tests: `make contract-test`
- E2E smoke: `make e2e`
- Tear down: `make down`

## Rules
- Fix infra issues in ./infra (open PR in infra repo).
- Fix agent issues in ./agent (open PR in agent repo).
- Update this repo only to bump pinned submodule SHAs + integration tests.
- When a user asks to update a specific file/domain, edit ONLY the corresponding file and nothing else.
- In every change response, list changed files explicitly.
