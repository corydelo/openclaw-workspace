#!/usr/bin/env python3
"""Manifest-driven scaffold upgrade runner for openclaw-workspace."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = ROOT / "config" / "scaffold-upgrade.json"


@dataclass(frozen=True)
class Step:
    step_id: str
    kind: str
    description: str
    approval_required: bool
    raw: dict[str, Any]


def _load_manifest(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("schema_version") != "scaffold-upgrade.v1":
        raise ValueError("unsupported scaffold upgrade schema")
    if not isinstance(data.get("steps"), dict) or not isinstance(data.get("lanes"), dict):
        raise ValueError("manifest must define object maps for steps and lanes")
    return data


def _resolve_steps(manifest: dict[str, Any], lane: str) -> list[Step]:
    lane_steps = manifest.get("lanes", {}).get(lane)
    if not isinstance(lane_steps, list) or not lane_steps:
        raise ValueError(f"unknown or empty lane: {lane}")

    resolved: list[Step] = []
    raw_steps = manifest["steps"]
    for step_id in lane_steps:
        payload = raw_steps.get(step_id)
        if not isinstance(payload, dict):
            raise ValueError(f"unknown step id in lane {lane}: {step_id}")
        description = str(payload.get("description", step_id)).strip() or step_id
        kind = str(payload.get("kind", "")).strip()
        if kind not in {"bootstrap", "python_venv", "command"}:
            raise ValueError(f"unsupported step kind for {step_id}: {kind}")
        resolved.append(
            Step(
                step_id=step_id,
                kind=kind,
                description=description,
                approval_required=bool(payload.get("approval_required", False)),
                raw=payload,
            )
        )
    return resolved


def _resolve_path(raw: str) -> Path:
    return (ROOT / raw).resolve()


def _command_preview(command: list[str]) -> str:
    return " ".join(command)


def _display_path(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def _run_command(command: list[str]) -> dict[str, Any]:
    proc = subprocess.run(
        command,
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    return {
        "command": command,
        "returncode": proc.returncode,
        "stdout": proc.stdout,
        "stderr": proc.stderr,
    }


def _bootstrap_command(step: Step) -> list[str]:
    subcommand = str(step.raw.get("subcommand", "")).strip()
    if not subcommand:
        raise ValueError(f"bootstrap step {step.step_id} missing subcommand")
    return ["bash", "./bootstrap.sh", subcommand]


def _python_version_from_file(version_file: Path) -> str:
    return version_file.read_text(encoding="utf-8").strip()


def _candidate_python_binaries(version: str) -> list[str]:
    cleaned = version.strip()
    if not cleaned:
        return []
    return [f"python{cleaned}", cleaned]


def _resolve_python_binary(step: Step) -> tuple[str | None, str | None]:
    explicit = str(step.raw.get("python_executable", "")).strip()
    if explicit:
        return (shutil.which(explicit), explicit)

    version_file_raw = str(step.raw.get("python_version_file", "")).strip()
    if not version_file_raw:
        return (shutil.which("python3"), "python3")

    version_file = _resolve_path(version_file_raw)
    if not version_file.exists():
        return (None, None)

    version = _python_version_from_file(version_file)
    for candidate in _candidate_python_binaries(version):
        binary = shutil.which(candidate)
        if binary:
            return (binary, candidate)
    return (None, f"python{version}")


def _check_bootstrap(step: Step) -> dict[str, Any]:
    command = _bootstrap_command(step)
    bootstrap_file = ROOT / "bootstrap.sh"
    ready = bootstrap_file.exists()
    return {
        "id": step.step_id,
        "kind": step.kind,
        "description": step.description,
        "status": "ready" if ready else "blocked",
        "approval_required": step.approval_required,
        "command_preview": _command_preview(command),
        "details": {
            "bootstrap_exists": ready,
        },
    }


def _apply_bootstrap(step: Step) -> dict[str, Any]:
    command = _bootstrap_command(step)
    result = _run_command(command)
    return {
        "id": step.step_id,
        "kind": step.kind,
        "description": step.description,
        "status": "applied" if result["returncode"] == 0 else "failed",
        "approval_required": step.approval_required,
        "command_preview": _command_preview(command),
        "details": result,
    }


def _check_python_venv(step: Step) -> dict[str, Any]:
    venv_path = _resolve_path(str(step.raw["venv_path"]))
    requirements = _resolve_path(str(step.raw["requirements"]))
    binary_path, requested = _resolve_python_binary(step)
    current_python = venv_path / "bin" / "python"
    details = {
        "venv_path": str(venv_path),
        "venv_exists": current_python.exists(),
        "requirements": str(requirements),
        "requirements_exists": requirements.exists(),
        "requested_python": requested,
        "resolved_python": binary_path,
    }
    status = "ready"
    if not requirements.exists():
        status = "blocked"
    elif requested and binary_path is None and not current_python.exists():
        status = "blocked"
    return {
        "id": step.step_id,
        "kind": step.kind,
        "description": step.description,
        "status": status,
        "approval_required": step.approval_required,
        "command_preview": (
            f"{requested or 'python3'} -m venv {_display_path(venv_path)} && "
            f"{_display_path(venv_path)}/bin/pip install -r {_display_path(requirements)}"
        ),
        "details": details,
    }


def _apply_python_venv(step: Step) -> dict[str, Any]:
    check = _check_python_venv(step)
    if check["status"] == "blocked":
        check["status"] = "failed"
        return check

    venv_path = _resolve_path(str(step.raw["venv_path"]))
    requirements = _resolve_path(str(step.raw["requirements"]))
    current_python = venv_path / "bin" / "python"

    if not current_python.exists():
        binary_path, requested = _resolve_python_binary(step)
        if binary_path is None:
            return {
                **check,
                "status": "failed",
                "details": {
                    **check["details"],
                    "error": f"unable to resolve pinned interpreter {requested}",
                },
            }
        create_result = _run_command([binary_path, "-m", "venv", str(venv_path)])
        if create_result["returncode"] != 0:
            return {
                **check,
                "status": "failed",
                "details": create_result,
            }

    commands = [
        [str(venv_path / "bin" / "python"), "-m", "pip", "install", "--upgrade", "pip"],
        [str(venv_path / "bin" / "pip"), "install", "-r", str(requirements)],
    ]
    outputs: list[dict[str, Any]] = []
    for command in commands:
        result = _run_command(command)
        outputs.append(result)
        if result["returncode"] != 0:
            return {
                **check,
                "status": "failed",
                "details": {
                    **check["details"],
                    "runs": outputs,
                },
            }
    return {
        **check,
        "status": "applied",
        "details": {
            **check["details"],
            "runs": outputs,
        },
    }


def _check_command(step: Step, *, execute_in_check: bool) -> dict[str, Any]:
    command = [str(item) for item in step.raw.get("command", [])]
    if not command:
        raise ValueError(f"command step {step.step_id} missing command")

    if execute_in_check:
        result = _run_command(command)
        status = "verified" if result["returncode"] == 0 else "failed"
        details = result
    else:
        status = "planned"
        details = {"command": command}
    return {
        "id": step.step_id,
        "kind": step.kind,
        "description": step.description,
        "status": status,
        "approval_required": step.approval_required,
        "command_preview": _command_preview(command),
        "details": details,
    }


def _apply_command(step: Step) -> dict[str, Any]:
    result = _check_command(step, execute_in_check=True)
    if result["status"] == "verified":
        result["status"] = "applied"
    return result


def _check_step(step: Step) -> dict[str, Any]:
    if step.kind == "bootstrap":
        return _check_bootstrap(step)
    if step.kind == "python_venv":
        return _check_python_venv(step)
    return _check_command(step, execute_in_check=bool(step.raw.get("run_in_check", False)))


def _apply_step(step: Step) -> dict[str, Any]:
    if step.kind == "bootstrap":
        return _apply_bootstrap(step)
    if step.kind == "python_venv":
        return _apply_python_venv(step)
    return _apply_command(step)


def _render_text(report: dict[str, Any]) -> str:
    lines = [
        f"mode: {report['mode']}",
        f"lane: {report['lane']}",
        f"status: {report['status']}",
    ]
    if report.get("approval_required"):
        lines.append("approval_required: true")
    if report.get("next_action"):
        lines.append(f"next_action: {report['next_action']}")
    lines.append("steps:")
    for step in report["steps"]:
        lines.append(f"- {step['id']}: {step['status']} :: {step['description']}")
        lines.append(f"  command: {step['command_preview']}")
    return "\n".join(lines)


def _ask_for_approval(lane: str) -> bool:
    if not sys.stdin.isatty():
        return False
    reply = input(f"Apply scaffold upgrade lane '{lane}'? [y/N] ").strip().lower()
    return reply in {"y", "yes"}


def build_report(mode: str, lane: str, steps: list[Step], *, approve: bool) -> tuple[int, dict[str, Any]]:
    if mode == "apply":
        needs_approval = any(step.approval_required for step in steps)
        if needs_approval and not approve and not _ask_for_approval(lane):
            report = {
                "mode": mode,
                "lane": lane,
                "status": "approval_required",
                "approval_required": True,
                "next_action": f"Re-run with --approve to apply lane '{lane}'.",
                "steps": [_check_step(step) for step in steps],
            }
            return (2, report)

    reports: list[dict[str, Any]] = []
    exit_code = 0
    if mode == "check":
        reports = [_check_step(step) for step in steps]
        statuses = {item["status"] for item in reports}
        if "failed" in statuses or "blocked" in statuses:
            status = "action_required"
            exit_code = 1
        else:
            status = "ok"
    else:
        for step in steps:
            report = _apply_step(step)
            reports.append(report)
            if report["status"] == "failed":
                exit_code = 1
                break
        status = "applied" if exit_code == 0 else "failed"

    report = {
        "mode": mode,
        "lane": lane,
        "status": status,
        "approval_required": any(step.approval_required for step in steps),
        "steps": reports,
    }
    if mode == "check":
        report["next_action"] = f"Run `bash ./bootstrap.sh upgrade --approve --lane {lane}` to apply this lane."
    return (exit_code, report)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("check", "apply"))
    parser.add_argument("--manifest", default=str(DEFAULT_MANIFEST))
    parser.add_argument("--lane", default="")
    parser.add_argument("--approve", action="store_true")
    parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON output.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    manifest = _load_manifest(Path(args.manifest).resolve())
    lane = args.lane or str(manifest.get("default_lane", "safe"))
    steps = _resolve_steps(manifest, lane)
    exit_code, report = build_report(args.mode, lane, steps, approve=args.approve)
    if args.json:
        print(json.dumps(report, indent=2, sort_keys=True))
    else:
        print(_render_text(report))
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
