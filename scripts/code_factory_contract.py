#!/usr/bin/env python3
"""Code Factory contract loader and lightweight JSON Schema validator."""

from __future__ import annotations

import fnmatch
import json
from pathlib import Path
from typing import Any


class ContractValidationError(RuntimeError):
    """Raised when a contract fails schema validation."""


def _type_name(expected: str) -> type[Any]:
    mapping: dict[str, type[Any]] = {
        "object": dict,
        "array": list,
        "string": str,
        "integer": int,
        "number": (int, float),
        "boolean": bool,
    }
    if expected not in mapping:
        raise ContractValidationError(f"unsupported schema type: {expected}")
    return mapping[expected]


def _validate_against_schema(data: Any, schema: dict[str, Any], path: str = "$") -> None:
    expected_type = schema.get("type")
    if expected_type:
        type_cls = _type_name(expected_type)
        if not isinstance(data, type_cls):
            raise ContractValidationError(
                f"{path}: expected {expected_type}, got {type(data).__name__}"
            )
        if expected_type == "integer" and isinstance(data, bool):
            raise ContractValidationError(f"{path}: expected integer, got boolean")

    enum_values = schema.get("enum")
    if enum_values is not None and data not in enum_values:
        raise ContractValidationError(
            f"{path}: value {data!r} is not in enum {enum_values!r}"
        )

    if "minimum" in schema and isinstance(data, (int, float)):
        if data < schema["minimum"]:
            raise ContractValidationError(
                f"{path}: value {data} is lower than minimum {schema['minimum']}"
            )

    if isinstance(data, dict):
        required = schema.get("required", [])
        for key in required:
            if key not in data:
                raise ContractValidationError(f"{path}: missing required key '{key}'")

        properties: dict[str, Any] = schema.get("properties", {})
        additional = schema.get("additionalProperties", None)

        for key, value in data.items():
            child_path = f"{path}.{key}"
            if key in properties:
                _validate_against_schema(value, properties[key], child_path)
            elif isinstance(additional, dict):
                _validate_against_schema(value, additional, child_path)

    if isinstance(data, list):
        min_items = schema.get("minItems")
        if min_items is not None and len(data) < min_items:
            raise ContractValidationError(
                f"{path}: expected at least {min_items} item(s), got {len(data)}"
            )

        item_schema = schema.get("items")
        if isinstance(item_schema, dict):
            for idx, value in enumerate(data):
                _validate_against_schema(value, item_schema, f"{path}[{idx}]")


def _read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ContractValidationError(f"{path}: invalid JSON/YAML content: {exc}") from exc


def load_contract(contract_path: Path, schema_path: Path) -> dict[str, Any]:
    """Load and validate a Code Factory contract document."""
    contract_raw = _read_json(contract_path)
    schema_raw = _read_json(schema_path)

    if not isinstance(contract_raw, dict):
        raise ContractValidationError("contract root must be an object")
    if not isinstance(schema_raw, dict):
        raise ContractValidationError("schema root must be an object")

    _validate_against_schema(contract_raw, schema_raw)
    return contract_raw


def required_checks_for_files(contract: dict[str, Any], changed_files: list[str]) -> list[str]:
    """Return the de-duplicated set of checks required by all matched risk tiers."""
    checks: list[str] = ["contract_validate"]
    for changed in changed_files:
        for tier in contract.get("risk_tiers", []):
            for path_glob in tier.get("path_globs", []):
                if fnmatch.fnmatch(changed, path_glob):
                    for check in tier.get("required_checks", []):
                        if check not in checks:
                            checks.append(check)
                    break
    return checks


def docs_drift_violations(contract: dict[str, Any], changed_files: list[str]) -> list[dict[str, Any]]:
    """Validate docs-drift rules against a set of changed files."""
    changed_set = set(changed_files)
    violations: list[dict[str, Any]] = []

    for rule in contract.get("docs_drift_rules", []):
        path_glob = rule.get("path_glob", "")
        triggered = any(fnmatch.fnmatch(path, path_glob) for path in changed_files)
        if not triggered:
            continue

        missing = [doc for doc in rule.get("must_update", []) if doc not in changed_set]
        if missing:
            violations.append(
                {
                    "path_glob": path_glob,
                    "missing": missing,
                    "human_notify": bool(rule.get("human_notify", False)),
                }
            )

    return violations
