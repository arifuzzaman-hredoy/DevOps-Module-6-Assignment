# Night Watch: Monitoring the Three-Tier App

Production-oriented monitoring for the existing **Nexora** three-tier application:
Prometheus metrics, Grafana dashboards, Alertmanager notifications, and GitHub
Actions CI/CD — built for Ostad Module 6, **PART A (implementation)**.

> **PART A status:** implementation, documentation, and local validation complete.
> No live deployment, notification delivery, or runtime testing is performed in this
> phase. See [PART B checklist](#part-b--manual-work-checklist).

---

## 1. Project overview

This repository adds a complete, secure, repeatable observability layer on top of an
**existing** three-tier application (Module 4 Nexora). It does **not** create a new
application and does **not** modify the Module 4 repository or its production
deployment. Backend instrumentation is delivered as a separate, documented patch.

## 2. Assignment information

| Field | Value |
|---|---|
| Assignment | Night Watch: Monitoring the Three-Tier App |
| Module | Ostad Module 6 — Monitoring Fundamentals, Prometheus, Visualization, Alerting & Production Monitoring |
| Organization | Ostad |
| Target repository | `https://github.com/arifuzzaman-hredoy/DevOps-Module-6-Assignment` |
| License | MIT |

## 3. Project objectives

- Monitor all three tiers (frontend, backend API, database) plus the host.
- Expose meaningful, low-cardinality backend application metrics.
- Provide a community server-health dashboard and a custom tier-by-tier dashboard.
- Ship production-oriented alert rules and Alertmanager routing.
- Validate every configuration automatically in CI and deploy safely via GitHub
  Actions.

## 4. Existing Nexora application overview

Verified from the Module 4 source (not assumed):

| Tier | Technology | Notes |
|---|---|---|
| Frontend | **React 19 + Vite + TypeScript**, served by **Nginx** | container health `GET /healthz` |
| Backend API | **Rust + Axum 0.8**, `0.0.0.0:3000` | `GET /health`, `GET /ready` |
| Database | **PostgreSQL 16**, self-hosted on EC2 (not RDS) | `nexora` DB, `nexora_app` role |
| Reverse proxy | **Nginx** on the web tier, `/api/` → backend:3000 | |
| Process manager | **systemd** (`nexora-backend.service`) | |
| Cloud | AWS, 3 × Ubuntu 24.04 EC2 across public/private subnets | |

Deployment topology:

```text
Internet ──HTTPS──▶ [ Web tier: Nginx + React ] 10.30.1.217 (public)
                          │ /api/ → TCP 3000
                     [ App tier: Rust/Axum ] 10.30.2.82 (private)
                          │ PostgreSQL 5432
                     [ DB tier: PostgreSQL 16 ] 10.30.3.195 (private)
```

Full analysis and integration strategy: [`docs/nexora-integration.md`](docs/nexora-integration.md).

## 5. Monitoring architecture

```text
                 nexora-monitoring (Docker network)
   ┌───────────────────────────────────────────────────────────┐
   │  node-exporter ─┐                                          │
   │  postgres-exp ──┼──▶ Prometheus ──▶ Alertmanager ──▶ Telegram│
   │  blackbox-exp ──┤        │              (or SMTP)           │
   │  backend /metrics┘       │                                  │
   │                          ▼                                  │
   │                       Grafana                               │
   └───────────────────────────────────────────────────────────┘
```

- Prometheus **pulls** metrics from exporters and the instrumented backend.
- Alertmanager **routes** firing/resolved alerts to Telegram (preferred) / email.
- Grafana **visualizes** via provisioned data source + dashboards.
- Everything runs in an isolated Compose project; no exporter port is published.

Details: [`docs/architecture.md`](docs/architecture.md).

## 6. Architecture diagram

```text
                      ┌───────────────────────┐
   Nexora web tier ──▶│  nexora-monitoring     │
   (Docker Compose)   │  prometheus :9090      │──┐
                      │  grafana    :3000      │  │ scrape (pull)
                      │  alertmanager :9093    │  │
                      │  node-exporter         │  │
                      │  postgres-exporter     │  │
                      │  blackbox-exporter     │  │
                      └────────────────────────┘  │
                                                  ▼
             ┌──────────────┬──────────────┬──────────────┐
             │ node-exporter│ postgres-exp │ nexora-backend│
             │  :9100       │  :9187       │  /metrics     │
             └──────────────┴──────────────┴──────────────┘
                                                  ▲
                              blackbox probes ────┘ (frontend URL, /ready)
```

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
| CI/CD | GitHub Actions + actionlint/promtool/amtool |
| Config rendering | Python 3 (stdlib only) |

## 8. Repository structure

```text
DevOps-Module-6-Assignment/
├── prometheus/
│   ├── prometheus.yml.template        # rendered to prometheus.yml (git-ignored)
│   └── rules/alerts.yml               # 12 alert rules
├── alertmanager/
│   └── alertmanager.yml.template      # rendered to alertmanager.yml (git-ignored)
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/prometheus.yml
│   │   └── dashboards/provider.yml
│   └── dashboards/three-tier-production.json
├── exporters/
│   ├── README.md
│   └── postgres-monitor-role.sql
├── blackbox/blackbox.yml
├── docker-compose.yml
├── integration/backend/
│   ├── README.md
│   ├── metrics.rs
│   └── nexora-prometheus.patch
├── scripts/
│   ├── render_config.py  render-config.sh  validate.sh
│   ├── validate_dashboards.py  validate_yaml.py  secret_scan.py
│   ├── deploy.sh  health-check.sh  import-community-dashboard.sh
├── .github/workflows/monitoring-cicd.yml
├── docs/
│   ├── architecture.md  deployment.md  prometheus.md  grafana.md
│   ├── alerting.md  cicd.md  nexora-integration.md
├── screenshots/            # PART B evidence (README checklist)
├── .env.example
├── .gitignore
├── LICENSE
└── README.md
```

## 9. Prometheus setup

Prometheus config is rendered from `prometheus/prometheus.yml.template` using
`scripts/render_config.py` (reads `.env`). It defines six scrape jobs:

| Job | Target | Metrics |
|---|---|---|
| `prometheus` | `localhost:9090` | self |
| `node` | `${NODE_EXPORTER_TARGET}` | host |
| `postgres` | `${NEXORA_DB_EXPORTER_TARGET}` | database |
| `nexora-backend` | `${NEXORA_APP_METRICS_TARGET}` | backend HTTP |
| `blackbox-frontend` | `${NEXORA_FRONTEND_PROBE_TARGET}` | frontend availability |
| `blackbox-backend` | `${NEXORA_BACKEND_PROBE_TARGET}` | backend readiness |

Scrape interval 15s; evaluation 15s; retention 15d. Full details:
[`docs/prometheus.md`](docs/prometheus.md).

## 10. Exporter configuration

| Exporter | Role | Access |
|---|---|---|
| Node Exporter | host CPU/mem/disk | internal only |
| postgres_exporter | DB metrics via least-privilege `nexora_monitoring` role (`pg_monitor`) | internal only |
| Blackbox Exporter | HTTP probes (frontend URL, backend `/ready`) | internal only |

Setup and the least-privilege SQL: [`exporters/README.md`](exporters/README.md) and
`exporters/postgres-monitor-role.sql`.

## 11. PromQL queries

Three custom queries (full explanations and expected outputs in
[`docs/prometheus.md`](docs/prometheus.md) §4):

**1. HTTP request rate per route**
```promql
sum by (route) (rate(http_requests_total{job="nexora-backend"}[5m]))
```
Expected: per-route req/s, e.g. `{route="/api/tasks"} 1.87`.

**2. Backend 5xx error ratio**
```promql
sum(rate(http_requests_total{job="nexora-backend", status=~"5.."}[5m]))
/
clamp_min(sum(rate(http_requests_total{job="nexora-backend"}[5m])), 1e-9)
```
Expected: `0.0` normally, e.g. `0.12` during an incident (12% errors).

**3. Database connection utilisation**
```promql
sum(pg_stat_database_numbackends{job="postgres"})
/
clamp_min(sum(pg_settings_max_connections{job="postgres"})
        - sum(pg_settings_superuser_reserved_connections{job="postgres"}), 1)
```
Expected: e.g. `0.08` (8% of usable connections).

## 12. Community dashboard

| Field | Value |
|---|---|
| Name | **Node Exporter Full** |
| ID | **1860** |
| Why | Comprehensive, widely used, actively maintained server-health dashboard for `node_exporter` |
| Import | Grafana → Dashboards → Import → `1860`, or `./scripts/import-community-dashboard.sh 1860` |
| Redistribution | Fetched at import time; **not** committed (author `rfmoz` has no explicit license) |

Details: [`docs/grafana.md`](docs/grafana.md) §2.

## 13. Custom dashboard

**Exact name:** `Three-Tier App - Production` (`grafana/dashboards/three-tier-production.json`)

- 12 non-row panels across 4 rows: **Frontend, Backend API, Database, Server**.
- Visualization types: **timeseries, stat, gauge, table**.
- Refresh 30s, default range last 6h, thresholds/units/legends set per panel.
- Auto-provisioned via `grafana/provisioning/dashboards/provider.yml`.

Panel map: [`docs/grafana.md`](docs/grafana.md) §3.

## 14. Alert rules

12 rules in 4 groups (`prometheus/rules/alerts.yml`):

| Group | Alerts |
|---|---|
| Availability | `NexoraBackendDown`, `NexoraFrontendDown`, `NexoraDatabaseDown`, `NexoraNodeExporterDown`, `NexoraBackendHealthProbeFailing` |
| API performance | `NexoraBackendHighErrorRate`, `NexoraBackendCriticalErrorRate`, `NexoraBackendHighLatency` |
| Database | `NexoraDatabaseConnectionsHigh` |
| Server | `NexoraHighCpuUsage`, `NexoraHighMemoryUsage`, `NexoraLowDiskSpace` |

Thresholds and `for` durations: [`docs/alerting.md`](docs/alerting.md) §1.

## 15. Notification setup

Alertmanager routes to **Telegram** (preferred) with `send_resolved: true`, optional
SMTP email, grouping, and inhibition. Secrets come from the environment, never git.

Manual steps (PART B): [`docs/alerting.md`](docs/alerting.md) §4. In short:

1. Create a bot with @BotFather → copy the token.
2. Get the numeric chat id.
3. Put `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID` in `.env`.
4. `./scripts/render-config.sh && docker compose restart alertmanager`.
5. Send a test alert and confirm receipt.

> Notifications are **not** claimed to work until a real message is received (PART B).

## 16. Docker Compose deployment

```bash
cp .env.example .env          # fill in real values
./scripts/validate.sh         # optional but recommended
./scripts/render-config.sh    # render prometheus.yml + alertmanager.yml
docker compose up -d
./scripts/health-check.sh
```

Services: `prometheus`, `grafana`, `alertmanager`, `node-exporter`,
`postgres-exporter`, `blackbox-exporter`. Full guide:
[`docs/deployment.md`](docs/deployment.md).

## 17. GitHub Actions CI/CD

`.github/workflows/monitoring-cicd.yml`:

- **PR to `main`:** validates Prometheus config/rules, Alertmanager, Compose,
  dashboard JSON, YAML, shell, secrets, and workflow syntax (actionlint). Fails on
  invalid config.
- **Push to `main`:** validate → SSH deploy → render → `up -d` → reload → health-check.

Details: [`docs/cicd.md`](docs/cicd.md).

## 18. Required GitHub Secrets

| Secret | Purpose |
|---|---|
| `DEPLOY_HOST` | Deployment server host/IP |
| `DEPLOY_USER` | SSH user |
| `DEPLOY_PORT` | SSH port |
| `DEPLOY_PATH` | Repo path on the server |
| `DEPLOY_SSH_KEY` | Private SSH key |

Runtime secrets (Telegram, SMTP, DB DSN, Grafana password) live in the server's
git-ignored `.env.deploy`.

## 19. Configuration validation

```bash
./scripts/validate.sh
```

Validates: Prometheus config + rules (`promtool`), Alertmanager (`amtool`), Docker
Compose (`docker compose config`), Grafana dashboard JSON, generic YAML, shell
syntax, secret scan, and (if installed) actionlint. Tools are downloaded on first
run into `.cache/tools`.

## 20. Troubleshooting

| Symptom | Check |
|---|---|
| Target DOWN in Prometheus | `docker compose exec prometheus wget -qO- http://<target>/metrics` |
| postgres_exporter down | DSN, role existence, DB reachability |
| Blackbox probe fails | Probe URL reachable from blackbox container; module config |
| Grafana "No data" | Data source + Prometheus has data; panel query |
| No Telegram messages | Token/chat id; `docker compose restart alertmanager` |
| Config change ignored | Re-run `render-config.sh` and restart the service |

More: [`docs/deployment.md`](docs/deployment.md) §9.

## 21. Security considerations

- No hardcoded credentials; secrets via `.env` / GitHub Secrets only.
- `.env` is git-ignored; `.env.example` has placeholders only.
- UIs bind to loopback by default; exporters are not published.
- Least-privilege DB monitoring role (`pg_monitor` only).
- Backend `/metrics` should not be publicly exposed.
- CI uses `permissions: contents: read`; deploy is gated to `push` on `main`.

## 22. Assignment questions and answers

### Q1. Pull vs push model; which does Prometheus use?

**Pull model:** the monitoring server (Prometheus) periodically scrapes metrics from
each target over HTTP, on a schedule it controls. Targets expose a `/metrics`
endpoint and otherwise do nothing.

**Push model:** the application or an agent sends metrics to a central collector
(e.g. Graphite, StatsD, or Prometheus via `remote_write` / a Pushgateway for
short-lived jobs).

**Prometheus uses the pull model** by default. Advantages: the collector controls
scrape frequency and timeouts; target health is directly observable (the `up`
metric); no delivery logic or buffering is needed in the app; and configuration is
centralized. Push is used only for short-lived/batch jobs via a Pushgateway.

### Q2. Monitoring vs observability

**Monitoring** is observing known metrics and known failure modes against predefined
thresholds and alerting when they are breached. It answers "is X broken?" for X you
already thought of.

**Observability** is the ability to understand the internal state of a system from
its external outputs (metrics, logs, traces) well enough to ask and answer **new**
questions — including unknown unknowns — without shipping new code. Observability is
broader: it emphasizes high-cardinality, exploratory data (structured logs,
distributed tracing, exemplars) and correlation across signals. Monitoring is a
subset of observability practice; dashboards and alerts are the monitoring layer
built on top of observable data.

### Q3. Users say "the website is slow" — which panels first, in what order?

Follow the request path, from the user inward, checking one tier at a time:

1. **Frontend availability / probe duration** — is the site even up, and how long
   does the blackbox HTTP probe take? A slow/failed probe points at the edge/DNS/TLS
   before touching the app.
2. **Backend API response time (p50/p95) and request rate** — is the API itself slow?
   High p95 with normal rate suggests app/DB latency; a request-rate spike suggests a
   traffic surge.
3. **Backend HTTP error rate** — are 5xx/4xx contributing to perceived slowness
   (retries, timeouts)?
4. **Database: active connections and connection usage** — saturation or lock
   contention makes every request slow; check connections vs max.
5. **Server resources: CPU, memory, disk I/O** — resource exhaustion (CPU steal,
   memory pressure, disk I/O wait) explains broad slowness across the backend.

Order rationale: isolate the failing tier first (frontend vs backend vs DB), then
drill into the most specific signal, then confirm with host resources. This avoids
guessing and quickly narrows the blast radius.

### Q4. Alert fatigue, and how did you avoid it?

**Alert fatigue** is desensitization caused by too many noisy, duplicate, or
low-value alerts, so operators start ignoring or disabling them — and miss real
incidents.

How this project avoids it:

- **Thresholds tied to user impact** (5xx ratio, p95 latency, connection saturation)
  rather than alerting on every metric spike.
- **`for` durations** (2m–10m) so transient blips and isolated errors do not page.
- **Severity tiers** (`warning` vs `critical`) with faster routing only for
  critical alerts.
- **Grouping** (`group_by: [alertname, tier, service]`) so related alerts arrive as
  one notification.
- **Inhibition** (node-down suppresses per-service alerts; DB-down suppresses
  connection alerts) to remove redundant noise.
- **Actionable annotations** (summary + description with the value) so responders
  know what to do.
- **Resolved notifications** so alerts close themselves and do not linger.
- **Validated rules** in CI (`promtool`) so broken/noisy rules never ship.

## 23. Evidence / screenshots

PART A contains no runtime screenshots (nothing is deployed yet). PART B captures
Prometheus targets, PromQL queries, both Grafana dashboards, alert firing/resolved,
Telegram delivery, and CI runs. Checklist: [`screenshots/README.md`](screenshots/README.md).

## 24. References

- Prometheus documentation — https://prometheus.io/docs/
- Prometheus alerting rules — https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/
- Alertmanager configuration — https://prometheus.io/docs/alerting/latest/configuration/
- Grafana provisioning — https://grafana.com/docs/grafana/latest/administration/provisioning/
- Node Exporter — https://github.com/prometheus/node_exporter
- postgres_exporter — https://github.com/prometheus-community/postgres_exporter
- Blackbox Exporter — https://github.com/prometheus/blackbox_exporter
- Grafana dashboard 1860 — https://grafana.com/grafana/dashboards/1860
- `metrics` (Rust) — https://docs.rs/metrics
- `metrics-exporter-prometheus` — https://docs.rs/metrics-exporter-prometheus
- GitHub Actions — https://docs.github.com/actions

---

## PART B — Manual Work Checklist

Everything below is **pending** and must be done manually during PART B. Nothing in
PART A performs these actions.

### Deployment & infrastructure
- [ ] Apply `integration/backend/nexora-prometheus.patch` to the Module 4 backend and rebuild/restart it.
- [ ] Create the `nexora_monitoring` PostgreSQL role (`exporters/postgres-monitor-role.sql`).
- [ ] Confirm/adjust security groups so the monitoring host can reach backend:3000 and the DB.
- [ ] Populate the server `.env.deploy` with real targets, DSN, Grafana password, Telegram/SMTP.
- [ ] Deploy the stack (`docker compose up -d` / `./scripts/deploy.sh`).

### Verification evidence
- [ ] Prometheus **Status → Targets**: all targets `UP` (`screenshots/prometheus/01-targets-up.png`).
- [ ] Run the three PromQL queries in Explore (`screenshots/prometheus/02..04`).
- [ ] Confirm the provisioned Prometheus data source (`screenshots/grafana/03-datasource.png`).
- [ ] Open `Three-Tier App - Production` and confirm all rows/panels populate (`screenshots/grafana/01-three-tier-dashboard.png`).
- [ ] Import `Node Exporter Full` (1860) (`screenshots/grafana/02-community-node-exporter.png`).
- [ ] Alertmanager shows loaded rules/receivers (`screenshots/alerting/01-alertmanager-ui.png`).

### Alerting
- [ ] Configure Telegram bot token + chat id and restart Alertmanager.
- [ ] Trigger a real alert (stop backend / break frontend probe) and capture firing (`screenshots/alerting/02-alert-firing.png`).
- [ ] Confirm the Telegram message arrives (`screenshots/alerting/03-telegram-notification.png`).
- [ ] Resolve the condition and capture the resolved notification (`screenshots/alerting/04-alert-resolved.png`).

### CI/CD
- [ ] Configure the `DEPLOY_*` GitHub Secrets.
- [ ] Capture a successful **Validate configuration** run (`screenshots/github-actions/01-successful-run.png`).
- [ ] Create a throwaway branch with invalid config, capture the failed run, then delete the branch (`screenshots/github-actions/02-failed-run.png`).
- [ ] Push to `main` and capture the deploy run (`screenshots/github-actions/03-deploy-run.png`).

### Final
- [ ] Complete all screenshots and update this checklist.
- [ ] Submit the repository URL and evidence.

---

**PART A status:** implementation, documentation, and local validation complete.
Runtime deployment, notification delivery, and screenshots are **pending PART B**.