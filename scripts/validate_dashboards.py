#!/usr/bin/env python3
"""Validate the custom Grafana dashboard JSON for required structure.

Checks that the dashboard exists, is valid JSON, has the exact required title,
contains at least six non-row panels, at least three visualization types, and
rows for every tier. Exits non-zero on failure.
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DASHBOARD = ROOT / "grafana" / "dashboards" / "three-tier-production.json"

REQUIRED_TITLE = "Three-Tier App - Production"
REQUIRED_ROWS = ["frontend", "backend api", "database", "server"]


def main() -> int:
    errors = []

    if not DASHBOARD.exists():
        print(f"DASHBOARD VALIDATION FAILED: {DASHBOARD} not found")
        return 1

    try:
        data = json.loads(DASHBOARD.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        print(f"DASHBOARD VALIDATION FAILED: invalid JSON: {exc}")
        return 1

    if data.get("title") != REQUIRED_TITLE:
        errors.append(f"title must be exactly {REQUIRED_TITLE!r}, got {data.get('title')!r}")

    if not data.get("uid"):
        errors.append("missing dashboard uid")

    panels = data.get("panels")
    if not isinstance(panels, list) or not panels:
        errors.append("panels must be a non-empty list")
        panels = []

    non_row = [p for p in panels if p.get("type") != "row"]
    if len(non_row) < 6:
        errors.append(f"expected at least 6 non-row panels, found {len(non_row)}")

    viz_types = {p.get("type") for p in non_row}
    if len(viz_types) < 3:
        errors.append(f"expected at least 3 visualization types, found {sorted(viz_types)}")

    rows = [str(p.get("title", "")).lower() for p in panels if p.get("type") == "row"]
    for required in REQUIRED_ROWS:
        if not any(required in row for row in rows):
            errors.append(f"missing a row for {required!r} (found rows: {rows})")

    for panel in non_row:
        if not panel.get("targets"):
            errors.append(f"panel {panel.get('title')!r} has no targets")
        if not panel.get("gridPos"):
            errors.append(f"panel {panel.get('title')!r} has no gridPos")

    if errors:
        print("DASHBOARD VALIDATION FAILED:")
        for err in errors:
            print(f"  - {err}")
        return 1

    print(
        "PASS: dashboard JSON valid "
        f"({len(panels)} panels, {len(non_row)} non-row, types={sorted(viz_types)})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())