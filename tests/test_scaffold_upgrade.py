from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


WORKSPACE_ROOT = Path(__file__).resolve().parents[1]
CLI = WORKSPACE_ROOT / "scripts" / "scaffold_upgrade.py"


def _run(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(CLI), *args],
        check=False,
        capture_output=True,
        text=True,
        cwd=WORKSPACE_ROOT,
    )


def test_check_reports_blocked_missing_python(tmp_path: Path) -> None:
    version_file = tmp_path / ".python-version"
    version_file.write_text("9.99", encoding="utf-8")
    requirements = tmp_path / "requirements.txt"
    requirements.write_text("pytest>=7.0\n", encoding="utf-8")

    manifest = {
        "schema_version": "scaffold-upgrade.v1",
        "default_lane": "safe",
        "lanes": {"safe": ["code_graph_runtime"]},
        "steps": {
            "code_graph_runtime": {
                "kind": "python_venv",
                "description": "Pinned runtime",
                "venv_path": str(tmp_path / "venv-py999"),
                "requirements": str(requirements),
                "python_version_file": str(version_file),
                "approval_required": True,
            }
        },
    }
    manifest_path = tmp_path / "manifest.json"
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

    proc = _run("check", "--manifest", str(manifest_path), "--json")

    assert proc.returncode == 1
    payload = json.loads(proc.stdout)
    assert payload["status"] == "action_required"
    assert payload["steps"][0]["status"] == "blocked"


def test_apply_requires_explicit_approval(tmp_path: Path) -> None:
    manifest = {
        "schema_version": "scaffold-upgrade.v1",
        "default_lane": "safe",
        "lanes": {"safe": ["verify"]},
        "steps": {
            "verify": {
                "kind": "command",
                "description": "Echo check",
                "command": [sys.executable, "-c", "print('ok')"],
                "approval_required": True,
            }
        },
    }
    manifest_path = tmp_path / "manifest.json"
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

    proc = _run("apply", "--manifest", str(manifest_path), "--json")

    assert proc.returncode == 2
    payload = json.loads(proc.stdout)
    assert payload["status"] == "approval_required"


def test_apply_runs_command_when_approved(tmp_path: Path) -> None:
    marker = tmp_path / "marker.txt"
    manifest = {
        "schema_version": "scaffold-upgrade.v1",
        "default_lane": "safe",
        "lanes": {"safe": ["verify"]},
        "steps": {
            "verify": {
                "kind": "command",
                "description": "Create marker",
                "command": [
                    sys.executable,
                    "-c",
                    (
                        "from pathlib import Path; "
                        f"Path(r'{marker}').write_text('done', encoding='utf-8')"
                    ),
                ],
                "approval_required": True,
            }
        },
    }
    manifest_path = tmp_path / "manifest.json"
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

    proc = _run("apply", "--manifest", str(manifest_path), "--approve", "--json")

    assert proc.returncode == 0
    payload = json.loads(proc.stdout)
    assert payload["status"] == "applied"
    assert marker.read_text(encoding="utf-8") == "done"
