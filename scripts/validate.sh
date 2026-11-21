#!/usr/bin/env bash
# =============================================================================
# Local validation for the Nexora monitoring stack.
# Validates Prometheus config + rules, Alertmanager config, Docker Compose,
# Grafana dashboard JSON, generic YAML, shell syntax, and scans for secrets.
#
# Usage:  ./scripts/validate.sh
# Tools:  promtool and amtool are downloaded on first run into .cache/tools
#         (override by putting them on PATH).
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TOOLS_DIR="$ROOT/.cache/tools"
PROMTOOL_VERSION="2.53.0"
AMTOOL_VERSION="0.27.0"
mkdir -p "$TOOLS_DIR"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

download() {
    local url="$1" dest="$2"
    echo "Downloading $(basename "$url") ..."
    curl -fsSL "$url" -o "$dest"
}

# ---------------------------------------------------------------------------
# Ensure promtool / amtool are available (PATH or cached Linux binaries).
# ---------------------------------------------------------------------------
if command -v promtool >/dev/null 2>&1; then
    PROMTOOL="$(command -v promtool)"
elif [ -x "$TOOLS_DIR/promtool" ]; then
    PROMTOOL="$TOOLS_DIR/promtool"
else
    archive="$TOOLS_DIR/prometheus.tar.gz"
    download "https://github.com/prometheus/prometheus/releases/download/v${PROMTOOL_VERSION}/prometheus-${PROMTOOL_VERSION}.linux-amd64.tar.gz" "$archive"
    tar -xzf "$archive" -C "$TOOLS_DIR" "prometheus-${PROMTOOL_VERSION}.linux-amd64/promtool"
    mv "$TOOLS_DIR/prometheus-${PROMTOOL_VERSION}.linux-amd64/promtool" "$TOOLS_DIR/promtool"
    rm -rf "$TOOLS_DIR/prometheus-${PROMTOOL_VERSION}.linux-amd64" "$archive"
    PROMTOOL="$TOOLS_DIR/promtool"
fi

if command -v amtool >/dev/null 2>&1; then
    AMTOOL="$(command -v amtool)"
elif [ -x "$TOOLS_DIR/amtool" ]; then
    AMTOOL="$TOOLS_DIR/amtool"
else
    archive="$TOOLS_DIR/alertmanager.tar.gz"
    download "https://github.com/prometheus/alertmanager/releases/download/v${AMTOOL_VERSION}/alertmanager-${AMTOOL_VERSION}.linux-amd64.tar.gz" "$archive"
    tar -xzf "$archive" -C "$TOOLS_DIR" "alertmanager-${AMTOOL_VERSION}.linux-amd64/amtool"
    mv "$TOOLS_DIR/alertmanager-${AMTOOL_VERSION}.linux-amd64/amtool" "$TOOLS_DIR/amtool"
    rm -rf "$TOOLS_DIR/alertmanager-${AMTOOL_VERSION}.linux-amd64" "$archive"
    AMTOOL="$TOOLS_DIR/amtool"
fi

echo "Using promtool: $PROMTOOL"
echo "Using amtool:   $AMTOOL"
echo

# ---------------------------------------------------------------------------
# 1. Render configuration from the example env (placeholders, never real secrets)
# ---------------------------------------------------------------------------
export RENDER_ENV_FILE="${RENDER_ENV_FILE:-$ROOT/.env.example}"
python3 "$ROOT/scripts/render_config.py"
pass "configuration rendering"

# ---------------------------------------------------------------------------
# 2. Prometheus configuration
# ---------------------------------------------------------------------------
( cd "$ROOT/prometheus" && "$PROMTOOL" check config prometheus.yml )
pass "prometheus configuration"

# ---------------------------------------------------------------------------
# 3. Prometheus alert rules
# ---------------------------------------------------------------------------
( cd "$ROOT/prometheus" && "$PROMTOOL" check rules rules/alerts.yml )
pass "prometheus alert rules"

# ---------------------------------------------------------------------------
# 4. Alertmanager configuration
# ---------------------------------------------------------------------------
( cd "$ROOT/alertmanager" && "$AMTOOL" check-config alertmanager.yml )
pass "alertmanager configuration"

# ---------------------------------------------------------------------------
# 5. Docker Compose configuration
# ---------------------------------------------------------------------------
docker compose --env-file "$ROOT/.env.example" -f "$ROOT/docker-compose.yml" config --quiet
pass "docker compose configuration"

# ---------------------------------------------------------------------------
# 6. Grafana dashboard JSON
# ---------------------------------------------------------------------------
python3 "$ROOT/scripts/validate_dashboards.py"
pass "grafana dashboard JSON"

# ---------------------------------------------------------------------------
# 7. Generic YAML files
# ---------------------------------------------------------------------------
python3 "$ROOT/scripts/validate_yaml.py"
pass "generic YAML files"

# ---------------------------------------------------------------------------
# 8. Shell script syntax
# ---------------------------------------------------------------------------
for script in "$ROOT"/scripts/*.sh; do
    bash -n "$script" || fail "syntax error in $script"
done
pass "shell script syntax"

# ---------------------------------------------------------------------------
# 9. Secret scan
# ---------------------------------------------------------------------------
python3 "$ROOT/scripts/secret_scan.py"
pass "secret scan"

# ---------------------------------------------------------------------------
# 10. GitHub Actions workflow (optional, if actionlint is available)
# ---------------------------------------------------------------------------
if command -v actionlint >/dev/null 2>&1; then
    actionlint "$ROOT/.github/workflows/monitoring-cicd.yml"
    pass "github actions workflow (actionlint)"
else
    echo "SKIP: actionlint not installed; workflow syntax checked by generic YAML parse"
fi

echo
echo "All local validations passed."