# Prometheus

## 1. Configuration

- Template: `prometheus/prometheus.yml.template`
- Rendered file: `prometheus/prometheus.yml` (git-ignored, produced by
  `scripts/render_config.py`)
- Alert rules: `prometheus/rules/alerts.yml`

Global settings:

| Setting | Value | Rationale |
|---|---|---|
| `scrape_interval` | 15s | Good resolution for a small stack without excessive storage |
| `scrape_timeout` | 10s | Below the scrape interval |
| `evaluation_interval` | 15s | Rule evaluation cadence |
| `external_labels` | `monitor=nexora-three-tier`, `environment=${MONITORING_ENV}` | Identifies the source in multi-cluster setups |

## 2. Scrape targets

| Job | Target (env var) | Interval | Metrics path | Purpose |
|---|---|---|---|---|
| `prometheus` | `localhost:9090` | 15s | `/metrics` | Prometheus self-monitoring |
| `node` | `${NODE_EXPORTER_TARGET}` | 15s | `/metrics` | Host metrics |
| `postgres` | `${NEXORA_DB_EXPORTER_TARGET}` | 15s | `/metrics` | Database metrics |
| `nexora-backend` | `${NEXORA_APP_METRICS_TARGET}` | 15s | `/metrics` | Backend HTTP metrics |
| `blackbox-frontend` | `${NEXORA_FRONTEND_PROBE_TARGET}` | 15s | `/probe` | Frontend availability |
| `blackbox-backend` | `${NEXORA_BACKEND_PROBE_TARGET}` | 15s | `/probe` | Backend readiness |

The two blackbox jobs use `relabel_configs` to set `__param_target` to the real
target and point `__address__` at `blackbox-exporter:9115` (the standard blackbox
pattern).

### Service discovery

The stack is small and static, so `static_configs` is used. Every address is supplied
through an environment variable (`.env`), never hardcoded in a public file. To add
targets dynamically later, switch a job to `file_sd_configs` or a cloud SD mechanism
without changing the rest of the config.

## 3. Backend metrics

The instrumented Nexora backend exposes (see `integration/backend/README.md`):

| Metric | Type | Labels |
|---|---|---|
| `http_requests_total` | counter | `method`, `route`, `status` |
| `http_request_duration_seconds` | histogram | `method`, `route`, `status` |
| `nexora_up` | gauge | — |
| `nexora_build_info` | gauge | `version` |

Labels are intentionally low-cardinality: the route is the **matched template**
(e.g. `/api/tasks/{id}`), never the concrete URL, and there are no user/request IDs.

## 4. Three custom PromQL queries

### Query 1 — HTTP request rate per route

```promql
sum by (route) (rate(http_requests_total{job="nexora-backend"}[5m]))
```

**What it answers:** how many requests per second each backend route is handling
right now (averaged over 5 minutes).

**Expected output:** one series per route, e.g.

```text
{route="/api/auth/login"}   0.02
{route="/api/tasks"}        1.87
{route="/api/tasks/{id}"}   0.65
{route="/health"}           0.07
```

Use it to spot traffic shifts, hot endpoints, and whether a deploy changed call
patterns.

### Query 2 — Backend 5xx error ratio

```promql
sum(rate(http_requests_total{job="nexora-backend", status=~"5.."}[5m]))
/
clamp_min(sum(rate(http_requests_total{job="nexora-backend"}[5m])), 1e-9)
```

**What it answers:** the fraction of backend responses that are server errors
(5xx) over the last 5 minutes. `clamp_min(..., 1e-9)` avoids division by zero when
there is no traffic.

**Expected output:** a value between 0 and 1, e.g. `0.0` normally, `0.12` during an
incident (12% errors). This is the expression behind the error-rate alerts.

### Query 3 — Database connection utilisation

```promql
sum(pg_stat_database_numbackends{job="postgres"})
/
clamp_min(
  sum(pg_settings_max_connections{job="postgres"})
  - sum(pg_settings_superuser_reserved_connections{job="postgres"}),
  1
)
```

**What it answers:** how much of the usable PostgreSQL connection budget is in use
(0.0–1.0). It excludes connections reserved for superusers.

**Expected output:** e.g. `0.08` (8% of connections used). Above `0.8` for 10
minutes triggers `NexoraDatabaseConnectionsHigh`.

### Bonus — p95 request latency

```promql
histogram_quantile(
  0.95,
  sum by (le) (rate(http_request_duration_seconds_bucket{job="nexora-backend"}[5m]))
)
```

Expected output is a duration in seconds (e.g. `0.08`), used by the latency alert
and dashboard.

## 5. Validation

```bash
# Render + validate the whole stack
./scripts/validate.sh

# Or just Prometheus
promtool check config prometheus/prometheus.yml
promtool check rules  prometheus/rules/alerts.yml
```

`scripts/validate.sh` downloads `promtool`/`amtool` on first run (into `.cache/tools`)
if they are not already on `PATH`.

## 6. Operational notes

- Reload configuration without downtime:
  `curl -X POST http://127.0.0.1:9090/-/reload` (requires `--web.enable-lifecycle`,
  which is set) or `docker compose restart prometheus`.
- Retention defaults to 15 days (`PROMETHEUS_RETENTION_TIME`); adjust for your disk.
- Do not expose `:9090` publicly; keep it on loopback or behind Nginx with auth.