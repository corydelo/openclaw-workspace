# Deferred k8s Transport Artifacts (STABILIZE)

Date: 2026-02-22

## Decision
The `k8s/` runtime transport path is deferred during STABILIZE. Runtime policy is compose-only for this phase.

## Why Deferred
- Live cluster evidence showed `chromadb-0` on stale controller revision `chromadb-7788f7f855` with probe failures on `GET /api/v1/heartbeat` returning `410`.
- STABILIZE policy requires transport containment and avoiding in-place k8s remediation during this kickoff.

## Reactivation Gate (Exception Protocol)
Reactivation of k8s transport requires an approved exception and explicit pass criteria per:
- `/Users/corydelouche/Codex/threads/governance/exception-protocol.md`

Minimum gate before re-enable:
1. Approved exception record naming owner thread, expiry, rollback trigger, and complexity delta.
2. Fresh k8s rollout plan with health checks verified against current image behavior.
3. Post-rollout evidence proving no CrashLoopBackOff and parity with compose health checks.

## Evidence Snapshot
See kickoff gate evidence:
- `/Users/corydelouche/Codex/_shared/handoffs/2026-02-22-gate-evidence-stabilize-kickoff.md`

## Scope Note
This directory preserves manifests exactly as deferred artifacts. No runtime activation is authorized by keeping these files in-repo.
