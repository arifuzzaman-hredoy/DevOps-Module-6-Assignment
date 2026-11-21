# Evidence / Screenshots

Genuine screenshots were captured automatically with headless Chrome against the live
deployment (and the public GitHub Actions pages). The files below are real; no
screenshots were fabricated.

## Captured

### prometheus/
- `01-targets-up.png` — Status → Targets, all six targets UP.
- `02-query-request-rate.png` — PromQL query 1 (request rate per route).
- `03-query-error-ratio.png` — PromQL query 2 (5xx error ratio).
- `04-query-db-connections.png` — PromQL query 3 (DB connection utilisation).

### grafana/
- `01-three-tier-dashboard.png` — `Three-Tier App - Production`.
- `02-community-node-exporter.png` — Node Exporter Full (ID 1860).
- `03-datasource.png` — provisioned Prometheus data source.
- `03b-datasource-health.png` — data source health check (working).

### alerting/
- `01-alertmanager-ui.png` — Alertmanager status page.
- `02-alert-firing.png` — `NexoraDatabaseDown` firing during the deliberate outage.
- `04-alert-resolved.png` — resolved notification payload. (The Alertmanager UI does
  not retain resolved alerts, so the resolved state is evidenced by the webhook
  payload.)
- `05-webhook-notification.png`, `webhook-notification.txt` — genuine firing + resolved
  webhook payloads.

### github-actions/
- `01-successful-run.png` — successful run `44905993282` (Validate + Deploy).
- `02-failed-run.png` — failed run `44905470131` (intentionally invalid rule).

## Pending (user-only)

- `alerting/03-telegram-notification.png` — requires the user's Telegram bot token and
  chat id, then a real alert to capture the Telegram message.