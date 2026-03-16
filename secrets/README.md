## Secret Bundle Contract

- `codex.env.age` is the single encrypted source of truth for workspace, infra, and agent runtime secrets.
- `age.recipients` stores non-secret public recipients used to encrypt `codex.env.age`.
- `backups/` is local-only rollover history for previous encrypted bundles and must not be committed.

Primary commands:

- `bash ../bootstrap.sh seal-secrets`
- `make -C .. rotate-keys`
- `bash ../bootstrap.sh render-runtime-env infra /run/llm-architecture/infra.env`

First-time setup:

1. Replace the placeholder entry in `age.recipients` with the real operator and VPS age public keys.
2. Ensure the matching private key exists at `~/.config/age/keys.txt` locally and on the VPS.
3. Run `bash ../bootstrap.sh seal-secrets` once to migrate any legacy plaintext inputs into `codex.env.age`.
