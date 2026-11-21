#!/usr/bin/env python3
"""Render Prometheus and Alertmanager configuration from templates.

Reads a dotenv-style file (default: .env) and substitutes ${PLACEHOLDER}
references in the templates, writing the runtime configuration files that the
Docker Compose stack mounts. Secrets are supplied through the environment and
never stored in git.

Precedence: process environment variables override values from the env file.

Environment:
    RENDER_ENV_FILE   Path to the env file (default: <repo>/.env)
    RENDER_OUT_DIR    Output root (default: <repo>)
"""

import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ENV_FILE = Path(os.environ.get("RENDER_ENV_FILE", ROOT / ".env"))
OUT_DIR = Path(os.environ.get("RENDER_OUT_DIR", ROOT))

TEMPLATES = [
    (
        ROOT / "prometheus" / "prometheus.yml.template",
        OUT_DIR / "prometheus" / "prometheus.yml",
    ),
    (
        ROOT / "alertmanager" / "alertmanager.yml.template",
        OUT_DIR / "alertmanager" / "alertmanager.yml",
    ),
]

PLACEHOLDER = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)")


def load_env(path: Path) -> dict:
    env = {}
    if not path.exists():
        return env
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
            value = value[1:-1]
        env[key.strip()] = value
    return env


def main() -> int:
    file_env = load_env(ENV_FILE)
    values = dict(file_env)
    for key, value in os.environ.items():
        if value != "":
            values[key] = value

    missing = set()

    def substitute(match: "re.Match[str]") -> str:
        key = match.group(1) or match.group(2)
        if key not in values:
            missing.add(key)
            return match.group(0)
        return values[key]

    for src, dst in TEMPLATES:
        if not src.exists():
            sys.exit(f"Template not found: {src}")
        rendered = PLACEHOLDER.sub(substitute, src.read_text(encoding="utf-8"))
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_text(rendered, encoding="utf-8")
        print(f"Rendered {src.relative_to(ROOT)} -> {dst}")

    if missing:
        sys.exit("Missing environment variables: " + ", ".join(sorted(missing)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())