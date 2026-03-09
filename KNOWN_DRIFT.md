# openclaw-workspace: Known Drift

## Snapshot
- Last reviewed: 2026-02-17
- Commit: `87657a6`

## Drift Register

### DRIFT-001: Core automation depends on untracked bootstrap script
- Evidence: `Makefile` targets call `./bootstrap.sh`; working tree currently shows `bootstrap.sh` as untracked.
- Impact: clean clones may not reproduce local bring-up behavior.
- Status: open

### DRIFT-002: E2E test target is non-assertive placeholder
- Evidence: `e2e/smoke_e2e.py` prints guidance and exits without validating behavior.
- Impact: `make e2e` can pass while system behavior is broken.
- Status: open

### DRIFT-003: Runtime artifacts are not fully ignored
- Evidence: `.infra.log` and `.infra.pid` appear as untracked runtime files in working tree.
- Impact: noisy diffs and accidental commits.
- Status: open

### DRIFT-004: Submodule operational drift risk
- Evidence: integration relies on submodules under active branch heads; manual pulls can diverge from pinned SHAs.
- Impact: integration regressions can appear without changes in this repo.
- Status: open

### DRIFT-005: Legacy OpenClaw docs still reference port 18789 as the active path
- Evidence: multiple documents under `agent/` and ancillary guides still describe the commented-out OpenClaw gateway instead of the Oracle + Signal runtime.
- Impact: operators can follow stale recovery guidance even when the canonical stack is Oracle on `:8000` plus Signal bridge on `:8080`.
- Status: open

### DRIFT-006: Ollama health checks do not prove inference readiness
- Evidence: Docker health checks report the Ollama container healthy and `/api/tags` lists models, but direct `POST /api/generate` against `127.0.0.1:11435` times out for a tiny prompt.
- Impact: Oracle can come online cleanly while the local-model path still hangs long enough to force cloud fallback or contract-test timeouts.
- Status: open

## Review Protocol
When closing drift:
1. Record the exact commit and command used for verification.
2. Update `ARCHITECTURE.md` and `TEST_SURFACE.md` if workflow changed.
3. Keep this register append-only for auditability.
