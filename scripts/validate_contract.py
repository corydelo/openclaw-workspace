#!/usr/bin/env python3
"""Validate Code Factory contract and print a machine-readable result."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from code_factory_contract import ContractValidationError, load_contract


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate Code Factory contract")
    parser.add_argument("--contract", required=True)
    parser.add_argument("--schema", required=True)
    args = parser.parse_args()

    contract_path = Path(args.contract).resolve()
    schema_path = Path(args.schema).resolve()

    result = {
        "contract": str(contract_path),
        "schema": str(schema_path),
        "status": "failed",
    }

    try:
        contract = load_contract(contract_path, schema_path)
        result["status"] = "passed"
        result["schema_version"] = contract.get("schema_version")
        result["risk_tier_count"] = len(contract.get("risk_tiers", []))
    except ContractValidationError as exc:
        result["error"] = str(exc)

    print(json.dumps(result, sort_keys=True))
    return 0 if result["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
