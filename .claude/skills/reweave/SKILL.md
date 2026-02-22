---
name: reweave
description: Reweave agent artifacts to restore structure and clean state. Includes bounded quarantine and structured verify mechanisms.
---
# Reweave Skill

Bounded reliability slice to maintain consistency of generated artifacts over time.

## Rules
- When processing artifacts, you must **verify** inputs and outputs against the defined **schema**.
- If an artifact is malformed, place it in the **quarantine** queue for manual inspection.
- When you successfully restore an artifact, update the **last-reweaved** timestamp.
- Provide a **confidence** score (0.0 to 1.0) along with your outputs.

## Parameters
- \`inputs\`: The corrupted or unverified objects.
- \`outputs\`: The fixed outputs.
