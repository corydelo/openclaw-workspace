# Code Factory Operations

This runbook defines the guarded operational behavior for the Code Factory loop.

## Ship modes

- `report_only`: Always allowed. Records approval with no git side effects.
- `branch_pr`: Guarded branch/PR mode. Critical-risk changes against protected branches require human handling.
- `auto_merge_guarded`: Only allowed for configured low/medium risk tiers. Protected branches require explicit `ship.allow_protected_branch=true`.

The loop never silently falls back to an implicit ship behavior. Unsupported modes are routed to `needs_human`.

## Queue lifecycle

Deterministic task transitions are enforced:

- `pending -> in_progress`
- `in_progress -> failed -> pending` (bounded retry)
- `in_progress -> failed -> dead_letter` (retry budget exhausted)
- `in_progress -> needs_human`
- `in_progress -> completed`

Claim locks are persisted per task (`claim_lock` with `expires_at`). Stale locks are reclaimed, and repeated anomalies trigger an automatic pause by writing `.pause-autonomous`.

## Rollback and override controls

- `CODE_FACTORY_SHIP_MODE_OVERRIDE=report_only`: Forces all tasks into report-only mode.
- `.pause-autonomous`: Stops shell-side effects and pauses loop progress until removed.
