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
- `02-alert-firing.png` — `NexoraDatabaseDown` firing during the earlier deliberate outage.
- `05-database-alert-firing.png` — actual `NexoraDatabaseDown` firing (re-verified).
- `06-database-alert-resolved.png` — actual `NexoraDatabaseDown` resolved (Alertmanager UI shows no active alert; API returns 0 alerts).
- `07-telegram-delivery-attempts.png`, `database-alert-log.txt` — genuine Alertmanager log of the `NexoraDatabaseDown` Telegram delivery attempts (firing + resolved). The log shows Telegram returning `chat not found` because the user has not started the bot.
- `04-alert-resolved.png`, `05-webhook-notification.png`, `webhook-notification.txt` — genuine firing + resolved webhook payloads.

### github-actions/
- `01-successful-run.png` — successful run `44905993282` (Validate + Deploy).
- `02-failed-run.png` — failed run `44905470131` (intentionally invalid rule).

## Pending (user-only)

- `alerting/03-telegram-firing.png`, `alerting/04-telegram-resolved.png` — require the
  user to open Telegram, start **@granfana_alert_manager_bot** (send `/start`), then
  re-run the delivery test to capture the real Telegram messages.