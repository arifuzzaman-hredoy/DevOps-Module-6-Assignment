#!/usr/bin/env bash
# =============================================================================
# Import the Grafana community dashboard "Node Exporter Full" (ID 1860) into a
# running Grafana instance via the HTTP API.
#
# The dashboard is fetched from grafana.com at import time and is NOT stored in
# this repository (its author, rfmoz, does not publish an explicit redistribution
# license). The recommended method remains the Grafana UI: Dashboards -> Import
# -> enter 1860. This script automates the same import for convenience.
#
# Usage:
#     GRAFANA_URL=http://127.0.0.1:3000 \
#     GRAFANA_ADMIN_USER=admin \
#     GRAFANA_ADMIN_PASSWORD=... \
#     ./scripts/import-community-dashboard.sh [DASHBOARD_ID]
# =============================================================================
set -euo pipefail

DASHBOARD_ID="${1:-${DASHBOARD_ID:-1860}}"
GRAFANA_URL="${GRAFANA_URL:-http://127.0.0.1:3000}"
GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:?Set GRAFANA_ADMIN_PASSWORD}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "==> Fetching dashboard ${DASHBOARD_ID} from grafana.com"
curl -fsSL "https://grafana.com/api/dashboards/${DASHBOARD_ID}/revisions/latest/download" \
    -o "$TMP_DIR/dashboard.json"

echo "==> Building import payload"
python3 - "$TMP_DIR/dashboard.json" "$TMP_DIR/payload.json" <<'PY'
import json
import sys

src, dst = sys.argv[1], sys.argv[2]
dashboard = json.load(open(src, encoding="utf-8"))
payload = {
    "dashboard": dashboard,
    "overwrite": True,
    "message": "Imported by scripts/import-community-dashboard.sh",
    "inputs": [
        {
            "name": "DS_PROMETHEUS",
            "type": "datasource",
            "pluginId": "prometheus",
            "value": "Prometheus",
        }
    ],
}
with open(dst, "w", encoding="utf-8") as handle:
    json.dump(payload, handle)
print(f"Payload written to {dst}")
PY

echo "==> Importing into Grafana at ${GRAFANA_URL}"
curl -fsS \
    -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
    -H "Content-Type: application/json" \
    -X POST "${GRAFANA_URL}/api/dashboards/import" \
    --data-binary @"$TMP_DIR/payload.json"

echo
echo "==> Import complete"