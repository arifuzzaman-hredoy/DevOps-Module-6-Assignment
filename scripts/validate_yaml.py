#!/usr/bin/env python3
"""Parse generic YAML files (Grafana provisioning, blackbox, workflow) to catch
syntax errors. Prometheus/Alertmanager files are validated by promtool/amtool in
validate.sh, so they are intentionally excluded here.

If PyYAML is not installed the check is skipped with a clear message.
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

FILES = [
    ROOT / "blackbox" / "blackbox.yml",
    ROOT / "grafana" / "provisioning" / "datasources" / "prometheus.yml",
    ROOT / "grafana" / "provisioning" / "dashboards" / "provider.yml",
    ROOT / ".github" / "workflows" / "monitoring-cicd.yml",
]


def main() -> int:
    try:
        import yaml  # type: ignore
    except ImportError:
        print("SKIP: PyYAML not installed; generic YAML parse skipped")
        return 0

    errors = []
    for path in FILES:
        if not path.exists():
            errors.append(f"missing file: {path.relative_to(ROOT)}")
            continue
        try:
            list(yaml.safe_load_all(path.read_text(encoding="utf-8")))
        except yaml.YAMLError as exc:
            errors.append(f"invalid YAML in {path.relative_to(ROOT)}: {exc}")

    if errors:
        print("YAML VALIDATION FAILED:")
        for err in errors:
            print(f"  - {err}")
        return 1

    print(f"PASS: {len(FILES)} YAML files parsed successfully")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())