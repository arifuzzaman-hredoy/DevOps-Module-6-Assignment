#!/usr/bin/env bash
# =============================================================================
# Verify the deployed Nexora app + monitoring stack and print real evidence.
#
# Usage (on the deployment host):
#     set -a; source /opt/nexora/secrets.env; set +a
#     bash scripts/verify-deployment.sh
#
# Environment:
#     HOST, PROMETHEUS_PORT, GRAFANA_PORT, GRAFANA_ADMIN_USER,
#     GRAFANA_ADMIN_PASSWORD, BACKEND_CONTAINER
# =============================================================================
set -euo pipefail

HOST="${HOST:-127.0.0.1}"
PROMETHEUS_PORT="${PROMETHEUS_PORT:-9090}"
GRAFANA_PORT="${GRAFANA_PORT:-3000}"
GRAFANA_USER="${GRAFANA_ADMIN_USER:-admin}"
GRAFANA_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-}"
BACKEND_CONTAINER="${BACKEND_CONTAINER:-nexora-local-backend-1}"

echo "=============================================="
echo " App health"
echo "=============================================="
printf 'GET /health  -> '; curl -fsS "http://$HOST/health";  echo
printf 'GET /ready   -> '; curl -fsS "http://$HOST/ready";   echo
printf 'GET /healthz -> '; curl -fsS "http://$HOST/healthz"; echo

echo
echo "=============================================="
echo " Backend /metrics sample"
echo "=============================================="
docker exec "$BACKEND_CONTAINER" curl -fsS http://127.0.0.1:3000/metrics \
    | grep -E '^(http_requests_total|nexora_up|nexora_build_info)' | head -10 || true

echo
echo "=============================================="
echo " Prometheus targets"
echo "=============================================="
curl -fsS "http://$HOST:$PROMETHEUS_PORT/api/v1/targets" | python3 -c '
import sys, json
d = json.load(sys.stdin)
for t in d["data"]["activeTargets"]:
    print("%-20s %-8s %s" % (t["labels"].get("job", "?"), t["health"], t["scrapeUrl"]))
'

echo
echo "=============================================="
echo " PromQL queries"
echo "=============================================="
run_query() {
    local title="$1" query="$2"
    echo "--- $title"
    echo "    $query"
    curl -fsS -G "http://$HOST:$PROMETHEUS_PORT/api/v1/query" \
        --data-urlencode "query=$query" | python3 -c '
import sys, json
d = json.load(sys.stdin)
if d.get("status") != "success":
    print("    ERROR:", d); sys.exit(0)
result = d["data"]["result"]
if not result:
    print("    (no data yet)")
for r in result[:8]:
    print("   ", r["metric"], "=>", r["value"][1])
'
    echo
}

run_query "1. HTTP request rate per route" \
    'sum by (route) (rate(http_requests_total{job="nexora-backend"}[5m]))'
run_query "2. Backend 5xx error ratio" \
    'sum(rate(http_requests_total{job="nexora-backend", status=~"5.."}[5m])) / clamp_min(sum(rate(http_requests_total{job="nexora-backend"}[5m])), 1e-9)'
run_query "3. Database connection utilisation" \
    'sum(pg_stat_database_numbackends{job="postgres"}) / clamp_min(sum(pg_settings_max_connections{job="postgres"}) - sum(pg_settings_superuser_reserved_connections{job="postgres"}), 1)'

echo "=============================================="
echo " Grafana"
echo "=============================================="
printf 'GET /api/health -> '; curl -fsS "http://$HOST:$GRAFANA_PORT/api/health"; echo

if [ -n "$GRAFANA_PASSWORD" ]; then
    echo
    echo "--- Datasources"
    curl -fsS -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
        "http://$HOST:$GRAFANA_PORT/api/datasources" | python3 -c '
import sys, json
for d in json.load(sys.stdin):
    print("   ", d["name"], "|", d["type"], "|", d["url"])
'
    echo
    echo "--- Datasource health"
    DS_UID=$(curl -fsS -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
        "http://$HOST:$GRAFANA_PORT/api/datasources" \
        | python3 -c 'import sys,json; print(json.load(sys.stdin)[0]["uid"])')
    curl -fsS -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
        "http://$HOST:$GRAFANA_PORT/api/datasources/uid/$DS_UID/health"
    echo
    echo
    echo "--- Dashboards"
    curl -fsS -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
        "http://$HOST:$GRAFANA_PORT/api/search?type=dash-db" | python3 -c '
import sys, json
for d in json.load(sys.stdin):
    print("   ", d["title"], "| uid:", d["uid"], "|", d["url"])
'
else
    echo "GRAFANA_ADMIN_PASSWORD not set; skipping datasource/dashboard checks"
fi

echo
echo "Verification complete."