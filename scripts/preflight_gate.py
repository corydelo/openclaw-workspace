#!/usr/bin/env python3
"""Deterministic preflight gate for Code Factory workflows."""

from __future__ import annotations

import argparse
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from code_factory_contract import (
    ContractValidationError,
    docs_drift_violations,
    load_contract,
    required_checks_for_files,
)


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _discover_changed_files(repo_root: Path) -> list[str]:
    diff_cmd = ["git", "-C", str(repo_root), "diff", "--name-only", "HEAD"]
    untracked_cmd = [
        "git",
        "-C",
        str(repo_root),
        "ls-files",
        "--others",
        "--exclude-standard",
    ]

    changed: set[str] = set()
    for cmd in (diff_cmd, untracked_cmd):
        proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
        if proc.returncode != 0:
            continue
        for line in proc.stdout.splitlines():
            path = line.strip()
            if path:
                changed.add(path)

    return sorted(changed)


def _run_check(check_name: str, check_def: dict[str, Any], repo_root: Path) -> dict[str, Any]:
    command = str(check_def.get("command", "")).strip()
    timeout_sec = int(check_def.get("timeout_sec", 300))
    if not command:
        return {
            "name": check_name,
            "status": "failed",
            "reason": "missing_command",
            "command": command,
            "exit_code": 127,
        }

    proc = subprocess.run(
        command,
        shell=True,
        cwd=repo_root,
        capture_output=True,
        text=True,
        timeout=timeout_sec,
        check=False,
    )

    return {
        "name": check_name,
        "status": "passed" if proc.returncode == 0 else "failed",
        "command": command,
        "exit_code": proc.returncode,
        "stdout": proc.stdout[-8000:],
        "stderr": proc.stderr[-8000:],
    }


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run Code Factory preflight gate")
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--contract", required=True)
    parser.add_argument("--schema", required=True)
    parser.add_argument("--report", required=True)
    parser.add_argument("--changed-file", action="append", default=[])
    return parser


def main() -> int:
    args = _build_parser().parse_args()
    repo_root = Path(args.repo_root).resolve()
    contract_path = Path(args.contract).resolve()
    schema_path = Path(args.schema).resolve()
    report_path = Path(args.report).resolve()

    changed_files = sorted(set(args.changed_file)) or _discover_changed_files(repo_root)

    report: dict[str, Any] = {
        "generated_at": _utc_now(),
        "repo_root": str(repo_root),
        "contract": str(contract_path),
        "schema": str(schema_path),
        "changed_files": changed_files,
        "required_checks": [],
        "checks": [],
        "docs_drift": {
            "status": "passed",
            "violations": [],
        },
        "status": "failed",
    }

    try:
        contract = load_contract(contract_path, schema_path)
        report["checks"].append(
            {
                "name": "contract_validate",
                "status": "passed",
                "command": "schema-validate",
                "exit_code": 0,
            }
        )
    except ContractValidationError as exc:
        report["checks"].append(
            {
                "name": "contract_validate",
                "status": "failed",
                "command": "schema-validate",
                "exit_code": 1,
                "stderr": str(exc),
            }
        )
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
        return 1

    required = required_checks_for_files(contract, changed_files)
    report["required_checks"] = required

    for check in required:
        if check == "contract_validate":
            continue
        if check == "reviewer_subagent":
            report["checks"].append(
                {
                    "name": "reviewer_subagent",
                    "status": "deferred",
                    "command": "handled_by_factory_loop",
                    "exit_code": 0,
                }
            )
            continue

        check_def = contract.get("checks", {}).get(check)
        if not isinstance(check_def, dict):
            report["checks"].append(
                {
                    "name": check,
                    "status": "failed",
                    "reason": "missing_check_definition",
                    "command": "",
                    "exit_code": 127,
                }
            )
            continue

        report["checks"].append(_run_check(check, check_def, repo_root))

    drift_violations = docs_drift_violations(contract, changed_files)
    if drift_violations:
        report["docs_drift"] = {
            "status": "failed",
            "violations": drift_violations,
        }

    failed_checks = [item for item in report["checks"] if item.get("status") == "failed"]
    docs_failed = report["docs_drift"]["status"] == "failed"
    report["status"] = "passed" if not failed_checks and not docs_failed else "failed"

    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
