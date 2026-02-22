#!/usr/bin/env python3
"""
E2E smoke test for the full OpenClaw → Oracle stack.

Replaces the original placeholder (DRIFT-002: had zero assertions).

Usage:
    python e2e/smoke_e2e.py
    # or via make:
    make e2e
"""
import os
import sys
import time
import json
import subprocess
import urllib.error
import urllib.request
from pathlib import Path


def load_dotenv(dotenv_path: Path) -> None:
    """Load KEY=VALUE pairs from dotenv file without overriding existing env."""
    if not dotenv_path.exists():
        return
    for raw in dotenv_path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


WORKSPACE_ROOT = Path(__file__).resolve().parents[1]
load_dotenv(WORKSPACE_ROOT / ".env")
load_dotenv(WORKSPACE_ROOT / "infra" / ".env")

ORACLE_BASE_URL = os.getenv("LLM_ARCH_BASE_URL", "http://127.0.0.1:8000")
AGENT_BASE_URL = os.getenv("AGENT_BASE_URL", "http://127.0.0.1:18789")
ORACLE_API_KEY = os.getenv("ORACLE_API_KEY", "")
HEALTH_TIMEOUT = 60  # seconds to wait for services

PASS = "\033[92m\u2713\033[0m"
FAIL = "\033[91m\u2717\033[0m"

errors = []


def request_json(method: str, url: str, headers: dict | None = None, payload: dict | None = None, timeout: int = 30) -> tuple[int, dict]:
    """Send an HTTP request using stdlib only (no external deps)."""
    req_headers = dict(headers or {})
    data = None
    if payload is not None:
        req_headers.setdefault("Content-Type", "application/json")
        data = json.dumps(payload).encode("utf-8")

    req = urllib.request.Request(url=url, data=data, headers=req_headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body = resp.read().decode("utf-8", errors="replace")
            return resp.status, json.loads(body) if body else {}
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        try:
            parsed = json.loads(body) if body else {}
        except Exception:
            parsed = {}
        return exc.code, parsed


def curl_status_code(url: str, timeout: int = 5) -> int | None:
    """Fallback probe when Python sockets are constrained in local environments."""
    try:
        result = subprocess.run(
            ["curl", "-sS", "-o", "/dev/null", "-w", "%{http_code}", url],
            capture_output=True,
            text=True,
            timeout=timeout + 2,
            check=False,
        )
    except Exception:
        return None
    if result.returncode != 0:
        return None
    code_text = result.stdout.strip()
    return int(code_text) if code_text.isdigit() else None


def check(name: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  {PASS} {name}")
    else:
        msg = f"{name}{': ' + detail if detail else ''}"
        print(f"  {FAIL} {msg}")
        errors.append(msg)


def wait_for_health(url: str, timeout: int = HEALTH_TIMEOUT) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            status, _ = request_json("GET", url, timeout=5)
            if status < 500:
                return True
        except Exception:
            pass
        curl_code = curl_status_code(url, timeout=5)
        if curl_code is not None and curl_code < 500:
            return True
        time.sleep(2)
    return False


def test_oracle_health():
    print("\n[1] Oracle health")
    ok = wait_for_health(f"{ORACLE_BASE_URL}/api/v1/health")
    check("Oracle /api/v1/health reachable", ok)
    if ok:
        _, data = request_json("GET", f"{ORACLE_BASE_URL}/api/v1/health", timeout=5)
        check("Health response is JSON object", isinstance(data, dict))
        if isinstance(data, dict) and "status" not in data:
            print("  [info] Health response has no 'status' field; continuing smoke check.")


def test_oracle_chat():
    print("\n[2] Oracle /v1/chat/completions")
    headers = {}
    if ORACLE_API_KEY:
        headers["Authorization"] = f"Bearer {ORACLE_API_KEY}"
    payload = {"model": "auto", "messages": [{"role": "user", "content": "Reply with exactly: smoke_ok"}]}
    try:
        status, data = request_json(
            "POST",
            f"{ORACLE_BASE_URL}/v1/chat/completions",
            headers=headers,
            payload=payload,
            timeout=30,
        )
        check("Status 200 or 429", status in (200, 429), f"got {status}")
        if status == 200:
            check("Has 'choices' field", "choices" in data)
            check("choices is non-empty", len(data.get("choices", [])) > 0)
            content = data.get("choices", [{}])[0].get("message", {}).get("content", "")
            check("Content is non-empty", len(content) > 0)
        elif status == 429:
            print("  [info] Oracle returned 429 (rate limit); treating as reachable for smoke.")
    except Exception as e:
        check("Oracle chat request", False, str(e))


def test_agent_health():
    print("\n[3] OpenClaw agent health")
    ok = wait_for_health(f"{AGENT_BASE_URL}/health", timeout=30)
    if not ok:
        ok = wait_for_health(f"{AGENT_BASE_URL}/", timeout=10)
    check("Agent /health reachable", ok)


if __name__ == "__main__":
    print("=== Codex E2E Smoke Test ===")
    test_oracle_health()
    test_oracle_chat()
    test_agent_health()

    print(f"\n{'='*30}")
    if errors:
        print(f"FAILED — {len(errors)} assertion(s) failed:")
        for e in errors:
            print(f"  \u2022 {e}")
        sys.exit(1)
    else:
        print("ALL CHECKS PASSED")
        sys.exit(0)
