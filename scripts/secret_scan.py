#!/usr/bin/env python3
"""Static secret scan for the repository.

Scans tracked files for common credential/token patterns and fails if any are
found. This is a defense-in-depth check; it is not a substitute for a full
secret-scanning service. Real values must live in .env / GitHub Secrets only.
"""

import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

SKIP_DIRS = {".git", ".cache", "node_modules", "target"}
SKIP_FILES = {".env", "package-lock.json", "Cargo.lock"}
TEXT_EXTENSIONS = {
    ".yml", ".yaml", ".json", ".md", ".sh", ".py", ".toml", ".sql",
    ".txt", ".env", ".template", ".conf", ".cfg", ".ini", ".ts", ".tsx",
}

PATTERNS = [
    ("Telegram bot token", re.compile(r"\b\d{8,10}:[A-Za-z0-9_-]{30,}\b")),
    ("GitHub token", re.compile(r"\bgh[pousr]_[A-Za-z0-9]{30,}\b")),
    ("AWS access key id", re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    ("Private key block", re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----")),
    ("Slack token", re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{10,}\b")),
    ("Generic api key assignment", re.compile(r"(?i)\b(api[_-]?key|secret[_-]?key)\s*[:=]\s*['\"]?[A-Za-z0-9]{24,}")),
]


def should_skip(path: Path) -> bool:
    parts = set(path.parts)
    if parts & SKIP_DIRS:
        return True
    if path.name in SKIP_FILES:
        return True
    if path.suffix not in TEXT_EXTENSIONS and path.name != ".env.example":
        return True
    return False


def main() -> int:
    findings = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            path = Path(dirpath) / name
            if should_skip(path):
                continue
            try:
                text = path.read_text(encoding="utf-8")
            except (UnicodeDecodeError, OSError):
                continue
            for lineno, line in enumerate(text.splitlines(), start=1):
                for label, pattern in PATTERNS:
                    if pattern.search(line):
                        rel = path.relative_to(ROOT)
                        findings.append(f"  - {label} in {rel}:{lineno}")

    if findings:
        print("SECRET SCAN FAILED: possible hardcoded credentials found:")
        print("\n".join(findings))
        return 1

    print("PASS: no hardcoded secrets detected")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())