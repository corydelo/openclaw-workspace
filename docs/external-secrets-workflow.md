# External Secrets Workflow

Because `openclaw-workspace` contains multiple microservices (`agent`, `infra`) managed via `docker-compose`, it enforces a strict external secrets policy (ID-130).

## Hardening Policies

1. **No Plaintext Secrets in Configs**:
   Configuration files (`*.json`, `*.yml`, etc.) must not contain literal plaintext secrets (e.g., `sk-xxx`, `llm_xxx`, or `apiKey: "plaintext"`).
2. **Environment Variable References**:
   Instead of hardcoded values, config surfaces should rely on environment variable references (e.g., `apiKey: "${ORACLE_API_KEY}"`).
3. **Automated Guardrails**:
   A validator script (`make secret-guard` or `python3 scripts/plaintext_secret_guard.py`) enforces this pattern by failing if a plaintext key pattern is detected in tracked configuration surfaces.

## Reload / Apply Workflow

When you need to rotate a key or add a new variable:

1. Update the `.env` files (e.g., `/agent/config/.env`, `/infra/.env`, or the root `openclaw-workspace/.env`). These `.env` files are `.gitignore`d.
2. If adding a new key, ensure the corresponding `${VAR_NAME}` is referenced in `openclaw-workspace/agent/config/openclaw.json` or `docker-compose.yml`.
3. To apply the modified secrets, you **must** recreate the containers so `docker compose` can source the new env-file:

   ```bash
   make down
   make up
   ```

   *(Note: Simply running `docker restart <container>` is insufficient, as it will inherit the environment variables from the previous `docker compose up` invocation.)*

## Exemptions

The guardrail intentionally overlooks:

- Files named `*.env.example`
- Environment expressions wrapped in `${...}` or `<...>`
- Hardcoded test keys that do not strictly match the length/complexity requirements of real infrastructure keys.
