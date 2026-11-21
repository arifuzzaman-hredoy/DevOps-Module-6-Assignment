# Evidence / Screenshots

This directory holds PART B runtime evidence. Screenshots are intentionally **not**
included in PART A because no live deployment or runtime testing is performed in this
phase. Capture the following during PART B and save them in the matching folder.

## prometheus/

- `01-targets-up.png` — Prometheus **Status → Targets** showing every target `UP`
  (`prometheus`, `node`, `postgres`, `nexora-backend`, `blackbox-frontend`,
  `blackbox-backend`).
- `02-explore-request-rate.png` — PromQL query 1 executed in **Explore**.
- `03-explore-error-ratio.png` — PromQL query 2 executed.
- `04-explore-db-connections.png` — PromQL query 3 executed.

## grafana/

- `01-three-tier-dashboard.png` — the `Three-Tier App - Production` dashboard with
  all four rows populated.
- `02-community-node-exporter.png` — the imported `Node Exporter Full` (ID 1860)
  dashboard.
- `03-datasource.png` — the provisioned `Prometheus` data source.

## alerting/

- `01-alertmanager-ui.png` — Alertmanager showing loaded rules/receivers.
- `02-alert-firing.png` — an alert in **Firing** state (e.g. after stopping the
  backend or breaking the frontend probe).
- `03-telegram-notification.png` — the Telegram message for a firing alert.
- `04-alert-resolved.png` — the resolved notification / resolved alert state.

## github-actions/

- `01-successful-run.png` — a green **Validate configuration** run (PR or push).
- `02-failed-run.png` — a red run caused by intentionally invalid configuration on a
  throwaway branch (see `docs/cicd.md` §5).
- `03-deploy-run.png` — the deploy job running on `main` (PART B).

> Do not fabricate screenshots. Capture them from the real running stack.