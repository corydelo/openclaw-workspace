# ID-056 Execution Walkthrough: Prompt Caching Architecture v2

Date: 2026-02-22
Thread: 3 (Implementation)
Phase: STABILIZE

---

## Objectives

1. Administrative maintenance (pytest warnings, shellcheck, resource leaks)
2. Prompt caching architecture v2 — cache-first prompt assembly for router path
3. Full test suite verification (221 tests, 0 warnings)
4. Handoff closure

---

## Phase 2: Administrative Maintenance

### Pydantic V2 ConfigDict Migration
- **File**: `infra/src/api/models.py`
- Replaced `class Config:` (V1 deprecation warning) with `model_config = ConfigDict(json_schema_extra={...})`
- Only occurrence in codebase. Import updated to `from pydantic import BaseModel, ConfigDict, Field`

### JWT HMAC Key Fix
- **File**: `infra/tests/test_jwt_auth.py`
- Updated all 4 `monkeypatch.setenv("JWT_SECRET_KEY", ...)` calls from 15-byte to 32-byte key
- Silences PyJWT HS256 deprecation warning for short HMAC keys

### Pytest Warning Filters
- **File**: `infra/pytest.ini`
- Added `filterwarnings = error` (strict mode) with targeted ignores for google.protobuf and pkg_resources
- Surfaces hidden deprecation warnings as test failures

### Resource Leak Fix
- **File**: `infra/src/agents/workflows.py` line 207-210
- Fixed `json.loads(open(cp).read())` bare file handles to `with open(cp) as f:` context managers
- Eliminated `ResourceWarning` from `test_code_factory_loop.py`

### Shellcheck Analysis (sturdy-journey)
- Installed shellcheck 0.11.0, ran `--severity=style` across 16 scripts
- **11 findings** (0 errors, 4 warnings, 5 info, 2 style)
- **4 fixes applied**:
  - `backup-openclaw.sh:53` SC2064: trap double-quote → single-quote (prevents premature expansion)
  - `compound-review.sh:74` SC2086: Quoted `${HOURS_BACK}` in date command
  - `vps-setup.sh:249` SC2086: Quoted `$SSH_PORT` in ufw command
  - `vps-setup.sh:274` SC2086: Quoted `$OS` in curl URL
- **7 remaining** (cosmetic): 3 unused variable warnings, 2 redirect grouping style, 1 ls vs find info, 1 external source info

---

## Phase 3: ID-056 — Prompt Caching Architecture v2

### Gap Closed: DirectStrategy Assembler Integration
- **File**: `infra/src/router/strategies.py`
- DirectStrategy.execute() previously built prompts via ad-hoc string concatenation (lines 67-78)
- Replaced with `self.prompt_assembler.assemble()` — cache-first assembly
- Added cache telemetry fields to return dict: `cache_creation_input_tokens`, `cache_read_input_tokens`, `simulated_cache_hits`
- Both execution paths (OrchestratorAgent direct + Router DirectStrategy) now use CachedPromptAssembler

### Hardened CachedPromptAssembler
- **File**: `infra/src/agents/prompt_assembler.py`
- Added structured logging: `_logger = logging.getLogger("agents.prompt_assembler")`
- Added `_logger.debug()` call after token accounting — logs `prefix_tokens`, `suffix_tokens`, `cache_hit_rate`
- Expanded docstring with explicit IMMUTABLE PREFIX CONTRACT and TELEMETRY sections

### Enhanced Test Coverage
- **File**: `infra/tests/test_prompt_assembler.py`
- Added 4 new tests (total: 6 + 1 regression = 7 cache tests):
  1. `test_reminders_never_in_prefix` — splits on cache marker, verifies reminders/KB only in suffix
  2. `test_assembler_no_prefix_when_no_conversation` — no marker without context
  3. `test_assembler_empty_string_conversation` — empty string = no prefix
  4. `test_direct_strategy_uses_assembler` — async mock integration test

---

## Phase 4: Verification

### Full Test Suite
```
221 passed in 3.05s
0 failed, 0 warnings
```

### Targeted Verification (from work-item spec)

**Command 1**: `pytest -k "cache or prompt_assembler"`
```
6 passed, 215 deselected in 0.58s
```

**Command 2**: `pytest -k "session_50_turn"`
```
1 passed, 220 deselected in 0.47s
cache_hit_rate > 0.90 (assertion passes)
```

**Command 3**: `rg -n "CachedPromptAssembler|cache_control|cache_hit_rate" openclaw-workspace`
```
23 matches across source and test files:
- src/router/strategies.py (import + instantiation)
- src/agents/orchestrator.py (import + instantiation)
- src/agents/prompt_assembler.py (class def + cache_control marker + telemetry)
- tests/test_prompt_assembler.py (6 test functions)
- tests/test_session_50_turn.py (50-turn regression)
```

---

## Files Modified

| File | Change Type |
|------|-------------|
| `infra/src/api/models.py` | Pydantic V2 ConfigDict |
| `infra/src/agents/prompt_assembler.py` | Logging + contract docstring |
| `infra/src/agents/workflows.py` | Resource leak fix (with-statement) |
| `infra/src/router/strategies.py` | CachedPromptAssembler integration |
| `infra/tests/test_jwt_auth.py` | 32-byte HMAC key |
| `infra/tests/test_prompt_assembler.py` | 4 new tests |
| `infra/pytest.ini` | Warning filters (strict mode) |
| `sturdy-journey/scripts/backup-openclaw.sh` | SC2064 trap quoting fix |
| `sturdy-journey/scripts/compound-review.sh` | SC2086 variable quoting |
| `sturdy-journey/scripts/vps-setup.sh` | SC2086 variable quoting (x2) |

## Complexity Delta
- Delta Services: 0
- Delta Providers: 0
- Net complexity: -1 (removed mutable-prefix ad-hoc path in DirectStrategy)

## Status
**ID-056: COMPLETE** — All acceptance criteria verified. Handing execution status back for Thread 3 closure.
