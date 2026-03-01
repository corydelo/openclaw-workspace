#!/usr/bin/env python3
"""
ID-130 Plaintext Secret Guard
Validates that config surfaces (*.json, *.yml) within openclaw-workspace
do not contain raw plaintext keys (e.g., sk-..., llm_...).
Allows ${VAR_NAME} environment references.
"""
import re
import sys
from pathlib import Path

# Common plaintext key patterns to block in config surfaces
# We allow environment variable references like "${ORACLE_API_KEY}"
SECRET_PATTERNS = [
    re.compile(r'[''"]?sk-[a-zA-Z0-9]{20,}[''"]?'),             # sk-xxx
    re.compile(r'[''"]?llm_[a-zA-Z0-9]{20,}[''"]?'),             # llm_xxx
    re.compile(r'(?i)(api_?key|secret)\s*[:=]\s*["\']([^$<\s][^"\']{8,})["\']') # apiKey: "plaintext"
]

def scan_file(filepath: Path) -> list[str]:
    findings = []
    try:
        content = filepath.read_text(encoding="utf-8")
        for i, line in enumerate(content.splitlines(), start=1):
            if "# noqa: secrets" in line:
                continue
            for pattern in SECRET_PATTERNS:
                match = pattern.search(line)
                if match:
                    if "${" in match.group(0):
                        continue
                    findings.append(f"{filepath}:{i} - Potential plaintext secret found")
    except Exception as e:
        print(f"Warning: Could not read {filepath}: {e}", file=sys.stderr)

    return findings

def main():
    repo_root = Path(__file__).parent.parent

    # Target surfaces: agent/config/, agent/docker/, etc.
    targets = [
        repo_root / "agent" / "config",
        repo_root / "agent" / "docker",
        repo_root / "config",
    ]

    all_findings = []
    for target in targets:
        if not target.exists():
            continue

        for ext in ("*.json", "*.yml", "*.yaml"):
            for filepath in target.rglob(ext):
                all_findings.extend(scan_file(filepath))

    if all_findings:
        print("ERROR: Plaintext secrets detected in config surfaces!", file=sys.stderr)
        for finding in all_findings:
            print(f"  {finding}", file=sys.stderr)
        print("\nPlease replace plaintext keys with environment variable references (e.g., ${API_KEY}).", file=sys.stderr)
        sys.exit(1)

    print("plaintext-secret-guard: ok (no plaintext secrets found in config surfaces)")
    sys.exit(0)

if __name__ == "__main__":
    main()
