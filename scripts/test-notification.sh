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

AM="${ALERTMANAGER_URL:-http://127.0.0.1:9093}"
LOG="${WEBHOOK_LOG:-/opt/nexora/webhook.log}"
LISTENER="${WEBHOOK_LISTENER:-/opt/nexora/webhook_listener.py}"

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
sleep 8
echo "==> Webhook log after firing:"
cat "$LOG"

echo
echo "==> Resolving test alert"
curl -s -X POST "$AM/api/v2/alerts" -H 'Content-Type: application/json' -d '[
  {"labels":{"alertname":"TestWebhook","severity":"test","tier":"test"},
   "annotations":{"summary":"resolved notification test"},
   "endsAt":"2000-01-01T00:00:00Z"}
]'
sleep 8
echo "==> Webhook log after resolved:"
cat "$LOG"

echo
echo "==> Notification test complete"