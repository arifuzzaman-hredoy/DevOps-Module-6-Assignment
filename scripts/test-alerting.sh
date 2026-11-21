#!/usr/bin/env bash
# =============================================================================
# Deliberately break the database tier to demonstrate a real alert firing and
# then resolving. Restores the database on exit. Captures evidence to stdout
# and to /opt/nexora/alert-test.log.
#
# Usage (on the deployment host):
#     bash scripts/test-alerting.sh
# =============================================================================
set -euo pipefail

HOST="${HOST:-127.0.0.1}"
PROM_PORT="${PROMETHEUS_PORT:-9090}"
AM_PORT="${ALERTMANAGER_PORT:-9093}"
LOG="${ALERT_TEST_LOG:-/opt/nexora/alert-test.log}"
PG_CONTAINER="${PG_CONTAINER:-nexora-local-postgres-1}"

exec > >(tee "$LOG") 2>&1
trap 'docker start "$PG_CONTAINER" >/dev/null 2>&1 || true' EXIT

echo "=== Alert test started $(date -u) ==="

echo
echo "--- Stopping postgres (deliberate database outage)"
docker stop "$PG_CONTAINER"

echo
echo "--- Generating 503 traffic for 30s (backend /ready)"
for _ in $(seq 1 15); do
    code="$(curl -s -o /dev/null -w '%{http_code}' "http://$HOST/ready" || echo 000)"
    echo "GET /ready -> $code"
    sleep 2
done

echo
echo "--- Waiting 140s for NexoraDatabaseDown (for: 2m) to fire"
sleep 140

echo
echo "--- Prometheus firing alerts"
curl -s "http://$HOST:$PROM_PORT/api/v1/query?query=ALERTS%7Balertstate%3D%22firing%22%7D" \
    | python3 -m json.tool

echo
echo "--- Alertmanager alerts (state)"
curl -s "http://$HOST:$AM_PORT/api/v2/alerts" | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
except Exception as exc:
    print("could not parse alerts:", exc); sys.exit(0)
for a in data:
    print(a["labels"].get("alertname"), "|", a["status"]["state"], "|", a["labels"].get("severity"))
'

echo
echo "--- Backend 5xx error ratio during outage"
curl -s -G "http://$HOST:$PROM_PORT/api/v1/query" \
    --data-urlencode 'query=sum(rate(http_requests_total{job="nexora-backend", status=~"5.."}[5m])) / clamp_min(sum(rate(http_requests_total{job="nexora-backend"}[5m])), 1e-9)' \
    | python3 -m json.tool

echo
echo "--- Restoring postgres"
docker start "$PG_CONTAINER"
sleep 45

echo
echo "--- Prometheus firing alerts after restore"
curl -s "http://$HOST:$PROM_PORT/api/v1/query?query=ALERTS%7Balertstate%3D%22firing%22%7D" \
    | python3 -m json.tool

echo
echo "--- Alertmanager alerts after restore (state)"
curl -s "http://$HOST:$AM_PORT/api/v2/alerts" | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
except Exception as exc:
    print("could not parse alerts:", exc); sys.exit(0)
for a in data:
    print(a["labels"].get("alertname"), "|", a["status"]["state"], "|", a["labels"].get("severity"))
'

echo
echo "--- App health after restore"
printf 'GET /ready -> '; curl -fsS "http://$HOST/ready"; echo

echo
echo "=== Alert test finished $(date -u) ==="