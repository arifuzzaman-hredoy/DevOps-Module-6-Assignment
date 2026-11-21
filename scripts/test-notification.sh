#!/usr/bin/env bash
# =============================================================================
# Demonstrate Alertmanager notification delivery without Telegram credentials.
# Sends a synthetic severity="test" alert and verifies that Alertmanager posts
# the firing and resolved payloads to a local webhook receiver.
#
# Usage (on the deployment host):
#     bash scripts/test-notification.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AM="${ALERTMANAGER_URL:-http://127.0.0.1:9093}"
LOG="${WEBHOOK_LOG:-/opt/nexora/webhook.log}"
LISTENER="${WEBHOOK_LISTENER:-$SCRIPT_DIR/webhook_listener.py}"

if ! pgrep -f webhook_listener.py >/dev/null 2>&1; then
    echo "==> Starting webhook listener"
    nohup python3 "$LISTENER" >/dev/null 2>&1 &
    sleep 2
fi

: > "$LOG"

echo "==> Sending firing test alert"
curl -s -X POST "$AM/api/v2/alerts" -H 'Content-Type: application/json' -d '[
  {"labels":{"alertname":"TestWebhook","severity":"test","tier":"test"},
   "annotations":{"summary":"firing notification test","description":"verifies Alertmanager webhook delivery"}}
]'
sleep 10
echo "==> Webhook log after firing:"
cat "$LOG"

echo
ENDS="$(date -u -d '+8 seconds' +%Y-%m-%dT%H:%M:%SZ)"
echo "==> Resolving test alert (endsAt=$ENDS)"
RESOLVE_PAYLOAD="$(cat <<EOF
[{"labels":{"alertname":"TestWebhook","severity":"test","tier":"test"},"annotations":{"summary":"resolved notification test"},"endsAt":"$ENDS"}]
EOF
)"
curl -s -X POST "$AM/api/v2/alerts" -H 'Content-Type: application/json' -d "$RESOLVE_PAYLOAD"
sleep 20
echo "==> Webhook log after resolved:"
cat "$LOG"

echo
echo "==> Notification test complete"