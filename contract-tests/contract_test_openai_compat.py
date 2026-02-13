#!/usr/bin/env python3
"""
Contract test for LLM-Architecture OpenAI-compatible endpoint.

Assumes infra running at http://127.0.0.1:8000

Env:
  LLM_ARCH_BASE_URL (optional, default http://127.0.0.1:8000)
  LLM_ARCH_API_KEY  (optional, if your server enforces auth)
"""
import os, sys, json
import urllib.request

BASE_URL = os.environ.get("LLM_ARCH_BASE_URL", "http://127.0.0.1:8000")
API_KEY = os.environ.get("LLM_ARCH_API_KEY")

def post_json(path: str, payload: dict):
    url = f"{BASE_URL}{path}"
    data = json.dumps(payload).encode("utf-8")
    headers = {"Content-Type": "application/json"}
    if API_KEY:
        headers["Authorization"] = f"Bearer {API_KEY}"
    req = urllib.request.Request(url, data=data, headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.status, resp.read().decode("utf-8")

def main():
    payload = {
        "model": "oracle/auto",
        "messages": [{"role": "user", "content": "Reply with exactly: ok"}],
        "stream": False
    }

    try:
        status, body = post_json("/v1/chat/completions", payload)
    except Exception as e:
        print("FAIL: Could not reach infra OpenAI endpoint.")
        print("Base URL:", BASE_URL)
        print("Error:", repr(e))
        print("\nStart infra in another terminal:")
        print("  cd /Users/corydelouche/Codex/openclaw-workspace && make infra-up")
        sys.exit(1)

    if status != 200:
        print("FAIL: HTTP", status)
        print(body[:2000])
        sys.exit(1)

    try:
        obj = json.loads(body)
    except Exception:
        print("FAIL: response not JSON")
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
    content = msg.get("content", "")

    print("PASS: OpenAI-compat response received.")
    if content:
        print("INFO: content:", repr(content[:160]))
    else:
        print("WARN: no message.content found; first choice was:")
        print(json.dumps(choice0, indent=2)[:2000])

    if "x_oracle" in obj:
        xo = obj["x_oracle"]
        print("INFO: x_oracle:", {k: xo.get(k) for k in ("confidence", "tier_used", "cost_estimate")})

if __name__ == "__main__":
    main()
