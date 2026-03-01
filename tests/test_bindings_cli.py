import json
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
CLI = REPO_ROOT / "agent" / "scripts" / "bindings.py"


def _write_config(path: Path) -> None:
    payload = {
        "agents": {
            "defaults": {
                "intentRouting": {
                    "enabled": True,
                    "channelBindings": {},
                }
            }
        }
    }
    path.write_text(json.dumps(payload), encoding="utf-8")


def _run(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(CLI), *args],
        check=False,
        capture_output=True,
        text=True,
    )


def test_bindings_inspect_empty(tmp_path: Path) -> None:
    cfg = tmp_path / "openclaw.json"
    _write_config(cfg)

    proc = _run("--config", str(cfg), "inspect")

    assert proc.returncode == 0
    assert "No explicit channel bindings configured." in proc.stdout


def test_bindings_bind_then_inspect_json(tmp_path: Path) -> None:
    cfg = tmp_path / "openclaw.json"
    _write_config(cfg)

    bind_proc = _run("--config", str(cfg), "bind", "signal", "--agent", "main")
    inspect_proc = _run("--config", str(cfg), "inspect", "--json")

    assert bind_proc.returncode == 0
    assert inspect_proc.returncode == 0

    data = json.loads(inspect_proc.stdout)
    assert data["channelBindings"] == {"signal": "main"}


def test_bindings_unbind_removes_mapping(tmp_path: Path) -> None:
    cfg = tmp_path / "openclaw.json"
    _write_config(cfg)

    _run("--config", str(cfg), "bind", "signal", "--agent", "main")
    unbind_proc = _run("--config", str(cfg), "unbind", "signal")
    inspect_proc = _run("--config", str(cfg), "inspect", "--json")

    assert unbind_proc.returncode == 0
    assert inspect_proc.returncode == 0
    assert json.loads(inspect_proc.stdout)["channelBindings"] == {}


def test_bindings_unbind_missing_fails_no_fallback(tmp_path: Path) -> None:
    cfg = tmp_path / "openclaw.json"
    _write_config(cfg)

    proc = _run("--config", str(cfg), "unbind", "missing-channel")

    assert proc.returncode == 2
    assert "Implicit fallback is not supported." in proc.stderr
