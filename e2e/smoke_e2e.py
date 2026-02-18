#!/usr/bin/env python3
"""Minimal reproducible smoke test for integration bring-up."""

import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path


def load_dotenv(dotenv_path: str = ".env") -> None:
    p = Path(dotenv_path)
    if not p.exists():
        return
    for raw in p.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


def wait_for_health(url: str, timeout_seconds: int = 90) -> dict:
    deadline = time.time() + timeout_seconds
    last_error = None

    while time.time() < deadline:
        try:
            req = urllib.request.Request(url, method="GET")
            with urllib.request.urlopen(req, timeout=10) as resp:
                body = resp.read().decode("utf-8", errors="replace")
                if resp.status != 200:
                    last_error = f"status={resp.status} body={body[:200]}"
                else:
                    try:
                        return json.loads(body)
                    except Exception:
                        return {"raw": body}
        except urllib.error.URLError as exc:
            last_error = repr(exc)
        except Exception as exc:
            last_error = repr(exc)
        time.sleep(1)

    raise RuntimeError(f"agent health did not become ready: {last_error}")


def main() -> None:
    load_dotenv(".env")
    agent_url = os.environ.get("AGENT_BASE_URL", "http://127.0.0.1:18789").rstrip("/")
    health_url = f"{agent_url}/health"

    try:
        payload = wait_for_health(health_url)
    except Exception as exc:
        print("FAIL: smoke health check failed")
        print("Agent URL:", agent_url)
        print("Error:", repr(exc))
        sys.exit(1)

    raw = str(payload.get("raw", ""))
    if raw and "openclaw" not in raw.lower():
        print("FAIL: health endpoint returned unexpected body")
        print("Agent URL:", agent_url)
        print("Body:", raw[:400])
        sys.exit(1)

    print("PASS: agent health endpoint ready")
    print("Agent URL:", agent_url)
    print("Health payload:", json.dumps(payload)[:400])


if __name__ == "__main__":
    main()
