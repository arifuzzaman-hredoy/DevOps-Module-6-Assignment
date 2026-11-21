# Grafana

## 1. Grafana setup (Task 2)

Grafana is configured entirely as code (no manual clicking required for the custom
dashboard or data source).

### 1.1 Deployment

- Service `grafana` (`grafana/grafana-oss:11.4.0`) in `docker-compose.yml`.
- Published on `0.0.0.0:3000` in this deployment (admin `/24` only).
- Public URL: `https://grafananex.oxytumzone.com/` — served through the host Nginx TLS reverse proxy.
- `GF_SERVER_ROOT_URL=https://grafananex.oxytumzone.com/` and `GF_SERVER_DOMAIN=grafananex.oxytumzone.com` are set in the deployment override.
- Admin credentials from `GRAFANA_ADMIN_USER` / `GRAFANA_ADMIN_PASSWORD` in `.env`.
- Dashboards and database persist in the `nexora-monitoring-grafana-data` volume.
- Provisioning is mounted read-only from `grafana/provisioning/`.

### 1.2 Provisioned files

| File | Effect |
|---|---|
| `grafana/provisioning/datasources/prometheus.yml` | Creates the `Prometheus` data source (`http://prometheus:9090`, default) |
| `grafana/provisioning/dashboards/provider.yml` | Loads every JSON file in `/var/lib/grafana/dashboards` into the `Nexora` folder |
| `grafana/dashboards/three-tier-production.json` | The custom dashboard |

### 1.3 Prometheus datasource configuration

`grafana/provisioning/datasources/prometheus.yml` defines:

| Setting | Value |
|---|---|
| Name | `Prometheus` |
| Type | `prometheus` |
| URL | `http://prometheus:9090` |
| Access | `proxy` |
| Default | yes |
| HTTP method | POST |

### 1.4 Datasource connection verification

After `docker compose up -d`:

1. **UI:** Grafana → **Connections → Data sources → Prometheus → Test** → expect
   "Data source is working".
2. **API:** `curl -u admin:$GRAFANA_ADMIN_PASSWORD http://127.0.0.1:3000/api/datasources`
   lists the `Prometheus` entry; `GET /api/datasources/uid/<uid>/health` returns
   `"status": "OK"`.
3. **Explore:** Grafana → **Explore** → `Prometheus` → run `up`; series confirm the
   proxy path works.
4. **Targets:** Prometheus → **Status → Targets** must show `UP` before dashboards
   render data.

## 2. Community dashboard — server health

### Selected dashboard

| Field | Value |
|---|---|
| Name | **Node Exporter Full** |
| Grafana.com ID | **1860** |
| Slug | `node-exporter-full` |
| Author / org | `rfmoz` |
| Source | https://github.com/rfmoz/grafana-dashboards |

### Why it was selected

- It is one of the most widely used and maintained Node Exporter dashboards
  (150M+ downloads at the time of writing).
- It graphs essentially all default `node_exporter` metrics: CPU, load, memory,
  disk I/O, filesystem, network, and more — exactly the server-health view this
  assignment needs.
- It is actively maintained and compatible with modern node_exporter (v0.18+).
- It requires only the default `job_name: node` scrape target, which this stack
  already provides.

### Import procedure

**Option A — Grafana UI (recommended):**

1. Open Grafana (`http://<host>:3000`).
2. **Dashboards → New → Import**.
3. Enter `1860` in "Import via grafana.com" and click **Load**.
4. Select the **Prometheus** data source when prompted.
5. Click **Import**.

**Option B — API script (automated):**

```bash
GRAFANA_URL=http://127.0.0.1:3000 \
GRAFANA_ADMIN_USER=admin \
GRAFANA_ADMIN_PASSWORD="$GRAFANA_ADMIN_PASSWORD" \
./scripts/import-community-dashboard.sh 1860
```

The script fetches the dashboard JSON from grafana.com at import time and posts it to
Grafana. **The dashboard JSON is not committed to this repository**, because its
author does not publish an explicit redistribution license; importing by ID keeps the
author's canonical artifact authoritative.

### Required variables / data source

- Data source: `Prometheus` (created by provisioning). During import, map the
  dashboard's `DS_PROMETHEUS` input to the provisioned `Prometheus` data source.
- No other variables are required; the dashboard targets the default `node` job.

## 3. Custom dashboard — `Three-Tier App - Production`

File: `grafana/dashboards/three-tier-production.json`

| Property | Value |
|---|---|
| Exact title | `Three-Tier App - Production` |
| UID | `nexora-three-tier-prod` |
| Refresh | 30s |
| Default time range | last 6 hours |
| Rows | Frontend, Backend API, Database, Server |

### Panels

| Row | Panel | Type | Query (summary) |
|---|---|---|---|
| Frontend | Frontend Availability | stat | `probe_success{job="blackbox-frontend"}` |
| Frontend | Frontend Health (HTTP Status) | stat | `probe_http_status_code{job="blackbox-frontend"}` |
| Backend API | HTTP Request Rate | timeseries | `sum by (route) (rate(http_requests_total{job="nexora-backend"}[5m]))` |
| Backend API | HTTP Error Rate (5xx) | timeseries | 5xx and 4xx rates |
| Backend API | API Response Time (p50/p95) | timeseries | `histogram_quantile(...)` on `http_request_duration_seconds_bucket` |
| Backend API | Request Status Distribution | table | `sum by (status) (increase(http_requests_total[1h]))` |
| Database | Database Health | stat | `pg_up{job="postgres"}` |
| Database | Active Database Connections | timeseries | `pg_stat_database_numbackends` |
| Database | Connection Usage (% of max) | gauge | backends / usable max connections |
| Server | CPU Utilization | timeseries | `100 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100` |
| Server | Memory Utilization | gauge | `1 - MemAvailable / MemTotal` |
| Server | Disk Utilization (/) | gauge | `1 - avail / size` on `/` |

Visualization types used: **timeseries, stat, gauge, table** (and row separators),
which exceeds the "at least three visualization types" requirement. Thresholds,
units, and legends are set per panel.

### Data source

The dashboard uses a `DS_PROMETHEUS` datasource template variable, so it works with
any Prometheus data source. Provisioning creates the `Prometheus` data source
automatically; the dashboard binds to it without manual edits.

## 4. Validation

```bash
python3 scripts/validate_dashboards.py
```

This checks the exact title, at least six non-row panels, at least three visualization
types, required rows, and that every panel has targets and a grid position.