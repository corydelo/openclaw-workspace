#!/usr/bin/env python3
"""
E2E smoke test placeholder.

Once OpenClaw boots reliably, this will:
- check agent health endpoint
- send a minimal request through agent that uses infra
- assert a successful response
"""
import os

def main():
    agent_url = os.environ.get("AGENT_BASE_URL", "http://127.0.0.1:18789")
    print("E2E placeholder. Agent URL:", agent_url)
    print("Next step: make OpenClaw container boot cleanly (agent repo notes schema mismatch).")

if __name__ == "__main__":
    main()
