#!/usr/bin/env python3
"""
Contract test for LLM-Architecture OpenAI-compatible endpoint.

Assumes infra running at http://127.0.0.1:8000

Env (can be set via shell OR via .env file in repo root):
  LLM_ARCH_BASE_URL  (default http://127.0.0.1:8000)
  ORACLE_API_KEY     (preferred)
  LLM_ARCH_API_KEY   (fallback)
"""

import os
import sys
import json
import urllib.request
import urllib.error
from pathlib import Path

def load_dotenv(dotenv_path: str = ".env") -> None:
    """
    Minimal .env loader (KEY=VALUE lines). No external deps.
    - Ignores blank lines and comments
    - Removes surrounding quotes
    - Does not overwrite already-set env vars
    """
    p = Path(dotenv_path)
    if not p.exists():
        return
    for raw in p.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        k = k.strip()
        v = v.strip().strip('"').strip("'")
        os.environ.setdefault(k, v)

def post_json(base_url: str, path: str, payload: dict, headers: dict):
    url = f"{base_url}{path}"
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.status, resp.read().decode("utf-8")

def main():
    # Load repo-root .env (so `make contract-test` works cleanly)
    load_dotenv(".env")

    base_url = os.environ.get("LLM_ARCH_BASE_URL", "http://127.0.0.1:8000")
    api_key = (
        os.environ.get("ORACLE_API_KEY")
        or os.environ.get("LLM_ARCH_API_KEY")
        or os.environ.get("API_KEY")
        or ""
    )

    headers = {"Content-Type": "application/json"}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"

    payload = {
        "model": "oracle/auto",
        "messages": [{"role": "user", "content": "Reply with exactly: ok"}],
        "stream": False,
    }

    try:
        status, body = post_json(base_url, "/v1/chat/completions", payload, headers)
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        print("FAIL: HTTP error from infra.")
        print("Status:", e.code)
        print("Reason:", e.reason)
        print("Body:", body[:2000])
        sys.exit(1)
    except Exception as e:
        print("FAIL: Could not reach infra OpenAI endpoint.")
        print("Base URL:", base_url)
        print("Error:", repr(e))
        print("\nStart infra in another terminal:")
        print("  cd /Users/corydelouche/Codex/openclaw-workspace && make infra-up")
        sys.exit(1)

    try:
        obj = json.loads(body)
    except Exception:
        print("FAIL: response was not JSON.")
        print(body[:2000])
        sys.exit(1)

    required = ["id", "object", "created", "model", "choices"]
    missing = [k for k in required if k not in obj]
    if missing:
        print("FAIL: missing keys:", missing)
        print(json.dumps(obj, indent=2)[:2000])
        sys.exit(1)

    if not isinstance(obj["choices"], list) or not obj["choices"]:
        print("FAIL: choices empty")
        print(json.dumps(obj, indent=2)[:2000])
        sys.exit(1)

    choice0 = obj["choices"][0]
    msg = choice0.get("message", {})
    content = (msg.get("content") or "").strip()

    if content.lower() != "ok":
        print("FAIL: expected 'ok' content, got:", repr(content))
        print(json.dumps(obj, indent=2)[:2000])
        sys.exit(1)

    print("PASS: OpenAI-compat response received.")
    print("Content:", repr(content))
    if "x_oracle" in obj:
        xo = obj["x_oracle"]
        print("x_oracle:", {k: xo.get(k) for k in ("confidence", "tier_used", "cost_estimate")})

if __name__ == "__main__":
    main()
