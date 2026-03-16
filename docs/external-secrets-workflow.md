# External Secrets Workflow

Because `openclaw-workspace` contains multiple services (`agent`, `infra`, and root bootstrap logic),
the live secret source of truth is the encrypted bundle at `openclaw-workspace/secrets/codex.env.age`.
Plaintext repo `.env` files are migration inputs only and are not used by the boot path anymore.

## Hardening Policies

1. **No Plaintext Secrets in Configs**:
   Configuration files (`*.json`, `*.yml`, etc.) must not contain literal plaintext secrets (e.g., `sk-xxx`, `llm_xxx`, or `apiKey: "plaintext"`).
2. **Environment Variable References**:
   Instead of hardcoded values, config surfaces should rely on environment variable references (e.g., `apiKey: "${ORACLE_API_KEY}"`).
3. **Automated Guardrails**:
   A validator script (`make secret-guard` or `python3 scripts/plaintext_secret_guard.py`) enforces this pattern by failing if a plaintext key pattern is detected in tracked configuration surfaces.

## Canonical Files

- `openclaw-workspace/secrets/codex.env.age` — encrypted source of truth
- `openclaw-workspace/secrets/age.recipients` — non-secret age public recipients
- `/run/llm-architecture/infra.env` — rendered Oracle runtime env on the VPS
- ephemeral `--env-file` pipe from `bootstrap.sh` — rendered agent runtime env for Docker Compose

## Reload / Apply Workflow

When you need to rotate a key or add a new variable:

1. Decrypt the bundle to a temp file:

   ```bash
   tmp_env="$(mktemp)"
   ./scripts/secret_bundle.sh decrypt >"$tmp_env"
   ```

2. Edit the temp file and re-seal it:

   ```bash
   $EDITOR "$tmp_env"
   ./scripts/secret_bundle.sh seal-file "$tmp_env"
   rm -f "$tmp_env"
   ```

3. If adding a new key, ensure the corresponding `${VAR_NAME}` is referenced in `agent/config/openclaw.json`,
   `agent/docker/docker-compose.yml`, or the relevant infra config surface.
4. To apply the modified secrets, restart through bootstrap so runtime env is re-rendered:

   ```bash
   make infra-up
   make agent-up
   ```

   Oracle will render `/run/llm-architecture/infra.env` on boot, and the agent stack will receive a fresh
   ephemeral envfile via `--env-file`.

5. For repo-owned tokens only, use the built-in rotation target instead of editing values manually:

   ```bash
   make rotate-keys
   ```

## Exemptions

The guardrail intentionally overlooks:

- Files named `*.env.example`
- Environment expressions wrapped in `${...}` or `<...>`
- Hardcoded test keys that do not strictly match the length/complexity requirements of real infrastructure keys.

## First-Time Setup

1. Install `age`.
2. Replace the placeholder entries in `secrets/age.recipients` with the real operator and VPS public keys.
3. Run `make seal-secrets` once to create `codex.env.age`.
