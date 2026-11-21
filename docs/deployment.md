# Deployment Guide

This guide covers running the monitoring stack locally and on the Nexora web tier.
**PART A does not deploy anything**; these are the steps for PART B.

## 1. Prerequisites

- Docker Engine 24+ with the Compose v2 plugin (`docker compose`).
- `curl`, `python3` (3.8+), `bash`.
- Network reachability from the monitoring host to:
  - the backend `/metrics` endpoint (app tier, TCP 3000), and
  - the PostgreSQL server (DB tier, TCP 5432) if the exporter runs on the monitoring host.
- A populated `.env` (copy from `.env.example`).

## 2. Configure

```bash
cp .env.example .env
# edit .env: set real targets, DB DSN, Grafana password, Telegram/SMTP values
```

Key variables (see `.env.example` for the full list):

| Variable | Local | AWS |
|---|---|---|
| `NEXORA_APP_METRICS_TARGET` | `host.docker.internal:3000` | `<app-tier-private-ip>:3000` |
| `NEXORA_DB_EXPORTER_DSN` | `postgresql://nexora_monitoring:***@host.docker.internal:5432/nexora?sslmode=disable` | `postgresql://nexora_monitoring:***@<db-tier-ip>:5432/nexora?sslmode=require` |
| `NEXORA_FRONTEND_PROBE_TARGET` | `https://nexora.oxytumzone.com` | same |
| `NEXORA_BACKEND_PROBE_TARGET` | `http://host.docker.internal:3000/ready` | `http://<app-tier-private-ip>:3000/ready` |
| `GRAFANA_ADMIN_PASSWORD` | any strong value | any strong value |
| `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` | real values | real values |

### 2.1 One-time database role

```bash
sudo -u postgres psql -d nexora -f exporters/postgres-monitor-role.sql
```

## 3. Validate before deploying

```bash
./scripts/validate.sh
```

Fix any reported issue before continuing. This renders the configs and runs
`promtool`, `amtool`, `docker compose config`, dashboard checks, shell checks, and a
secret scan.

## 4. Start the stack

```bash
./scripts/render-config.sh          # render prometheus.yml + alertmanager.yml from .env
docker compose up -d
```

Check status and health:

```bash
docker compose ps
./scripts/health-check.sh
```

Expected output (all PASS):

```text
PASS: prometheus-healthy (http://127.0.0.1:9090/-/healthy) -> 200
PASS: prometheus-ready   (http://127.0.0.1:9090/-/ready)   -> 200
PASS: alertmanager-healthy (http://127.0.0.1:9093/-/healthy) -> 200
PASS: grafana-health     (http://127.0.0.1:3000/api/health) -> 200
```

## 5. Access the UIs

Because the UIs bind to loopback, use an SSH tunnel from your workstation:

```bash
ssh -L 9090:127.0.0.1:9090 -L 3000:127.0.0.1:3000 -L 9093:127.0.0.1:9093 <user>@<web-tier-host>
```

Then open:

- Prometheus: http://127.0.0.1:9090 (Status → Targets: all should be UP)
- Grafana: http://127.0.0.1:3000
- Alertmanager: http://127.0.0.1:9093

To expose Grafana publicly instead, put it behind the existing Nginx with TLS and
authentication. Do not publish the exporter ports.

## 6. Update / reload

```bash
git pull
./scripts/deploy.sh          # or: ENV_FILE=.env.deploy ./scripts/deploy.sh
```

`deploy.sh` renders config, pulls images, recreates only changed containers, and
health-checks. Prometheus can also be reloaded without a restart:

```bash
curl -X POST http://127.0.0.1:9090/-/reload
```

## 7. Stop / start

```bash
docker compose stop          # stop without deleting
docker compose start         # start again
docker compose down          # remove containers/networks (volumes are preserved)
```

> Do **not** run `docker system prune -a --volumes` or delete the
> `nexora-monitoring-*` volumes unless you intend to lose dashboards/TSDB data.

## 8. Rollback

The monitoring stack is stateless with respect to the app. To roll back:

```bash
git checkout <previous-good-commit>
./scripts/render-config.sh
docker compose up -d
```

## 9. Troubleshooting

| Symptom | Check |
|---|---|
| A target is DOWN in Prometheus | From inside the network: `docker compose exec prometheus wget -qO- http://<target>:<port>/metrics` |
| postgres_exporter down | Verify DSN, that the role exists, and DB reachability from the host |
| Blackbox probe fails | Verify the probe URL from the blackbox container; check `module` and redirects |
| Grafana shows "No data" | Confirm the `Prometheus` data source and that Prometheus has data; check the panel query |
| No Telegram messages | Verify `TELEGRAM_BOT_TOKEN`/`TELEGRAM_CHAT_ID`, then `docker compose restart alertmanager` |
| Config change not applied | Re-run `./scripts/render-config.sh` then restart the relevant service |

Logs:

```bash
docker compose logs -f prometheus
docker compose logs -f alertmanager
docker compose logs -f grafana
```

## 10. Security checklist

- `.env` is git-ignored and contains real secrets; never commit it.
- UIs bind to loopback by default; use SSH tunnels or Nginx + TLS + auth.
- Exporters are not published.
- Database monitoring uses a least-privilege role (`pg_monitor` only).
- Rotate the Grafana admin password and Telegram bot token if exposed.
- Restrict SSH to the deployment key/user used by CI.