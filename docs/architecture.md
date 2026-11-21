# Monitoring Architecture

## 1. Overview

The monitoring stack observes the existing Nexora three-tier application using a
Prometheus-centric, pull-based metrics pipeline with Grafana visualization and
Alertmanager notifications. For this assignment, the Nexora application (frontend,
backend, PostgreSQL) and the monitoring stack all run on **one dedicated EC2
instance**; the application tiers are isolated as Docker Compose services on a shared
`nexora-net` network. Node Exporter therefore monitors that single host, not three
separate servers.

Public access is through the host Nginx TLS reverse proxy (ports 80/443) with a
Let's Encrypt certificate: `https://nexora.oxytumzone.com/` → app Nginx
`127.0.0.1:8080`, and `https://grafananex.oxytumzone.com/` → Grafana `127.0.0.1:3000`.
Prometheus, Alertmanager, PostgreSQL, and all exporters remain private.

## 2. Component diagram

```text
                          ┌──────────────────────────────────────────┐
                          │        nexora-monitoring (Docker)         │
                          │                                          │
   ┌────────────┐  scrape  │  ┌────────────┐   rules   ┌───────────┐ │
   │  Nexora    │◀─────────┤  │ Prometheus │──────────▶│ Alertman- │ │
   │  targets   │  (pull)  │  │   :9090    │           │  ager     │ │
   │            │          │  └─────┬──────┘           │  :9093    │ │
   └────────────┘          │        │ query            └─────┬─────┘ │
                          │        │                        │notify │
                          │  ┌─────▼──────┐          ┌──────▼─────┐  │
                          │  │  Grafana   │          │  Telegram  │  │
                          │  │   :3000    │          │  (or SMTP) │  │
                          │  └────────────┘          └────────────┘  │
                          └──────────────────────────────────────────┘
```

## 3. Data flow

1. **Exporters expose metrics** on internal ports inside the `nexora-monitoring`
   network:
   - `node-exporter:9100` — host CPU/memory/disk/filesystem.
   - `postgres-exporter:9187` — PostgreSQL status, connections, settings.
   - `blackbox-exporter:9115` — HTTP probes for frontend/backend availability.
   - The **backend itself** exposes `http_requests_total` and
     `http_request_duration_seconds` at `GET /metrics`.
2. **Prometheus scrapes** every target on its `scrape_interval` (15 s) using the
   configuration rendered from `prometheus/prometheus.yml.template`.
3. **Prometheus evaluates alerting rules** every `evaluation_interval` (15 s) and
   sends firing/resolved alerts to Alertmanager.
4. **Alertmanager** groups, throttles, inhibits, and routes notifications to
   Telegram (preferred) and/or SMTP email.
5. **Grafana** queries Prometheus (proxy) to render the community dashboard and the
   custom `Three-Tier App - Production` dashboard.

## 4. Components and ports

| Component | Image | Container port | Published | Purpose |
|---|---|---|---|---|
| Prometheus | `prom/prometheus:v2.53.0` | 9090 | `${PROMETHEUS_BIND_ADDRESS:-127.0.0.1}:${PROMETHEUS_PORT}` (loopback) | Scraping, rule evaluation, TSDB |
| Grafana | `grafana/grafana-oss:11.4.0` | 3000 | `${GRAFANA_BIND_ADDRESS:-127.0.0.1}:${GRAFANA_PORT}` (0.0.0.0 in this deployment, admin /24 only) | Dashboards |
| Alertmanager | `prom/alertmanager:v0.27.0` | 9093 | `${ALERTMANAGER_BIND_ADDRESS:-127.0.0.1}:${ALERTMANAGER_PORT}` (loopback) | Alert routing/notifications |
| Node Exporter | `prom/node-exporter:v1.8.2` | 9100 | none (internal) | Host metrics |
| postgres_exporter | `prometheuscommunity/postgres-exporter:v0.17.1` | 9187 | none (internal) | PostgreSQL metrics |
| Blackbox Exporter | `prom/blackbox-exporter:v0.25.0` | 9115 | none (internal) | HTTP availability probes |

## 5. Networking and volumes

- **Network:** `nexora-monitoring` (bridge). Only this network connects the
  components; exporters are not reachable from outside.
- **Volumes:** `nexora-monitoring-prometheus-data`, `nexora-monitoring-alertmanager-data`,
  `nexora-monitoring-grafana-data` — persistent TSDB, alert state, and dashboards.
- **Host reachability:** Prometheus, postgres_exporter, and blackbox-exporter get
  `extra_hosts: host.docker.internal:host-gateway` so they can reach services running
  on the host / other tiers.

## 6. Configuration rendering

Prometheus and Alertmanager do not interpolate environment variables, so both use a
template rendered at deploy time:

```
*.yml.template  --(scripts/render_config.py, reads .env)-->  *.yml  (git-ignored)
```

This keeps secrets (Telegram token, SMTP password, DB password) out of git while
allowing environment-specific targets.

## 7. Technology stack

| Area | Choice |
|---|---|
| Metrics | Prometheus 2.53 |
| Visualization | Grafana OSS 11.4 |
| Alerting | Alertmanager 0.27 |
| Host metrics | Node Exporter 1.8 |
| DB metrics | postgres_exporter 0.17.1 |
| Probes | Blackbox Exporter 0.25 |
| Backend instrumentation | Rust `metrics` 0.24 + `metrics-exporter-prometheus` 0.18 |
| Orchestration | Docker Compose v2 |
| CI/CD | GitHub Actions |
| Config rendering | Python 3 (stdlib only) |

## 8. Reliability and safety properties

- Restart policy `unless-stopped` on every long-running service.
- Health checks for Prometheus, Grafana, Alertmanager, and blackbox.
- Persistent volumes for all stateful components.
- No exporter port is published; Prometheus/Alertmanager bind to loopback, Grafana binds to `0.0.0.0:3000` restricted by the security group to the admin `/24`.
- Least-privilege database monitoring role (`pg_monitor` only).
- Idempotent deployment script; only recreates containers whose config changed.