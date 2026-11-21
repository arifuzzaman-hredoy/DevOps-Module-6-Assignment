#!/usr/bin/env bash
# =============================================================================
# Health check for the Nexora monitoring stack.
# Verifies Prometheus, Alertmanager and Grafana HTTP endpoints.
#
# Usage: ./scripts/health-check.sh
# Environment: PROMETHEUS_PORT, ALERTMANAGER_PORT, GRAFANA_PORT, HOST
# =============================================================================
set -euo pipefail

HOST="${HOST:-127.0.0.1}"
PROMETHEUS_PORT="${PROMETHEUS_PORT:-9090}"
ALERTMANAGER_PORT="${ALERTMANAGER_PORT:-9093}"
GRAFANA_PORT="${GRAFANA_PORT:-3000}"

check() {
    local name="$1" url="$2"
    local code
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$url" || echo 000)"
    if [[ "$code" == "200" ]]; then
        echo "PASS: $name ($url) -> $code"
    else
        echo "FAIL: $name ($url) -> $code" >&2
        return 1
    fi
}

status=0
check "prometheus-healthy" "http://$HOST:$PROMETHEUS_PORT/-/healthy" || status=1
check "prometheus-ready"   "http://$HOST:$PROMETHEUS_PORT/-/ready"   || status=1
check "alertmanager-healthy" "http://$HOST:$ALERTMANAGER_PORT/-/healthy" || status=1
check "grafana-health"     "http://$HOST:$GRAFANA_PORT/api/health"   || status=1

exit "$status"