# Screenshot Evidence — Ostad Module 6

Genuine screenshots captured from the live production deployment and GitHub Actions.
No screenshots are fabricated or simulated. Each file was captured from the running
system (headless Chrome) or the public GitHub Actions pages.

## Live URLs

- Main application: **https://nexora.oxytumzone.com**
- Grafana: **https://grafananex.oxytumzone.com** (admin login; password never stored here)
- Prometheus / Alertmanager: private (`127.0.0.1:9090` / `9093`, accessed via SSH tunnel)

## Directory structure

```text
screenshots/
├── prometheus/             # Task 1
├── grafana/                # Task 2
├── community-dashboard/    # Task 3
├── three-tier-dashboard/   # Task 4
├── alerting/               # Task 5
├── github-actions/         # Task 6
├── production-deployment/  # Live deployment + SSL
└── README.md
```

## Task mapping

| Task | Evidence files |
|---|---|
| **Task 1 — Prometheus (15)** | `prometheus/01-targets-up.png`, `02-query-request-rate.png`, `03-query-error-ratio.png`, `04-query-db-connections.png` |
| **Task 2 — Grafana (10)** | `grafana/05-grafana-home.png`, `06-datasource.png`, `07-datasource-health.png` |
| **Task 3 — Community dashboard (10)** | `community-dashboard/01-node-exporter-full.png` |
| **Task 4 — Three-Tier dashboard (20)** | `three-tier-dashboard/01-overview.png`, `02-frontend-row.png`, `03-backend-row.png`, `04-database-row.png`, `05-server-row.png` |
| **Task 5 — Alerting (20)** | `alerting/01-alertmanager-status.png`, `02-alert-rules.png`, `03-alertmanager-alerts.png`, `04-database-alert-firing.png`, `05-database-alert-resolved.png`, `06-telegram-delivery.png`, `07-telegram-delivery-log.png`, `08-webhook-notification.png` |
| **Task 6 — GitHub CI/CD (15)** | `github-actions/01-successful-run.png` (Validate + Deploy), `03-failed-run.png` (intentional invalid config) |
| **Task 7 — Questions (10)** | Answered in the main `README.md` §23 (no screenshots needed) |
| **Production** | `production-deployment/01-nexora-home.png`, `02-nexora-healthz.png`, `03-grafana-public.png`, `04-three-tier-public.png`, `05-node-exporter-public.png`, `06-ssl-certificate.png` |

## Notes

- **Telegram:** delivery is verified by Alertmanager metrics (`06-telegram-delivery.png`:
  2 successful sends, 0 failures) and the delivery log (`07-telegram-delivery-log.png`).
  The actual Telegram chat screenshots are **user-only** (they require the user's
  Telegram app) and are not included.
- **Database alert:** `04-database-alert-firing.png` and `05-database-alert-resolved.png`
  are genuine captures of the real `NexoraDatabaseDown` alert during a controlled
  outage and after recovery. The database was restored immediately and health was
  re-verified.
- **Grafana:** screenshots are captured through the public HTTPS domain
  `https://grafananex.oxytumzone.com`; the admin password is never shown.
- **SSL:** `06-ssl-certificate.png` shows the Let's Encrypt certificate served by both
  domains (SANs `nexora.oxytumzone.com`, `grafananex.oxytumzone.com`).