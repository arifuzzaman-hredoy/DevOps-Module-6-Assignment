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
ALERT_NAME="TestWebhook-$(date -u +%Y%m%d%H%M%S)"

if ! curl -s -o /dev/null http://127.0.0.1:5000/ 2>/dev/null; then
    echo "==> Starting webhook listener"
    setsid python3 "$LISTENER" >/dev/null 2>&1 < /dev/null &
    sleep 2
fi

: > "$LOG"

echo "==> Sending firing test alert: $ALERT_NAME"
curl -s -o /dev/null -w '    HTTP %{http_code}\n' -X POST "$AM/api/v2/alerts" \
    -H 'Content-Type: application/json' \
    -d "[{\"labels\":{\"alertname\":\"$ALERT_NAME\",\"severity\":\"test\",\"tier\":\"test\"},\"annotations\":{\"summary\":\"firing notification test\",\"description\":\"verifies Alertmanager webhook delivery\"}}]"
sleep 15
echo "==> Webhook log after firing:"
cat "$LOG"

echo
ENDS="$(date -u -d '+10 seconds' +%Y-%m-%dT%H:%M:%SZ)"
echo "==> Resolving test alert (endsAt=$ENDS)"
curl -s -o /dev/null -w '    HTTP %{http_code}\n' -X POST "$AM/api/v2/alerts" \
    -H 'Content-Type: application/json' \
    -d "[{\"labels\":{\"alertname\":\"$ALERT_NAME\",\"severity\":\"test\",\"tier\":\"test\"},\"annotations\":{\"summary\":\"resolved notification test\"},\"endsAt\":\"$ENDS\"}]"
sleep 20
echo "==> Webhook log after resolved:"
cat "$LOG"

echo
echo "==> Notification status counts:"
grep -o '"status":"[a-z]*"' "$LOG" | sort | uniq -c || true
echo "==> Notification test complete"