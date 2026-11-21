# Exporters

This directory documents the metrics exporters used by the Nexora monitoring stack.
The exporter containers themselves are defined in `docker-compose.yml`; this
document explains what each one does, how it is configured, and how to grant the
least-privilege access it needs.

| Exporter | Image | Port (internal) | Purpose |
|---|---|---|---|
| Node Exporter | `prom/node-exporter:v1.8.2` | 9100 | Host / server metrics (CPU, memory, disk, filesystem) |
| postgres_exporter | `prometheuscommunity/postgres-exporter:v0.17.1` | 9187 | PostgreSQL 16 metrics (uptime, connections, transactions, locks) |
| Blackbox Exporter | `prom/blackbox-exporter:v0.25.0` | 9115 | HTTP availability probes for the frontend and backend health endpoints |

None of these ports are published to the host. They are reachable only inside the
`nexora-monitoring` Docker network and are scraped by Prometheus over service names
(`node-exporter:9100`, `postgres-exporter:9187`, `blackbox-exporter:9115`).

---

## 1. Node Exporter

Collects host-level metrics from the machine that runs the monitoring stack.

Key arguments (see `docker-compose.yml`):

- `--path.rootfs=/host` with `/:/host:ro,rslave` so the exporter can read the host
  filesystem.
- `pid: host` so process metrics are accurate.
- Filesystem mount-point exclusions for pseudo filesystems.

Key metrics used by the dashboards and alerts:

- `node_cpu_seconds_total{mode="idle"}`
- `node_memory_MemAvailable_bytes`, `node_memory_MemTotal_bytes`
- `node_filesystem_avail_bytes`, `node_filesystem_size_bytes`

> To monitor the app and database EC2 instances too, run one Node Exporter per
> instance (systemd service or a small Docker container) and add a `static_configs`
> entry to each host under the `node` job in `prometheus.yml`. This is optional for
> the assignment but recommended for full coverage.

---

## 2. postgres_exporter

Collects PostgreSQL metrics using a dedicated **least-privilege** monitoring role.

### Create the monitoring role

Run the following once, as a PostgreSQL superuser on the Nexora database server:

```bash
sudo -u postgres psql -d nexora -f exporters/postgres-monitor-role.sql
```

This creates (or reuses) a `nexora_monitoring` login role, grants it `pg_monitor`
(read-only access to statistics views and settings), and nothing else. It does not
grant write access to any application table.

### Configure the connection

The exporter reads a single `DATA_SOURCE_NAME` environment variable, supplied via
`NEXORA_DB_EXPORTER_DSN` in `.env`:

```
postgresql://nexora_monitoring:PASSWORD@HOST:5432/nexora?sslmode=disable   # local
postgresql://nexora_monitoring:PASSWORD@HOST:5432/nexora?sslmode=require   # AWS (app/db tiers)
```

### Key metrics used

- `pg_up` - scrape success (1 = up, 0 = down).
- `pg_stat_database_numbackends{datname}` - current connections per database.
- `pg_settings_max_connections`, `pg_settings_superuser_reserved_connections`.
- `pg_stat_database_xact_commit`, `pg_stat_database_xact_rollback`, `pg_database_size_bytes`.

---

## 3. Blackbox Exporter

Performs synthetic HTTP probes from inside the monitoring network.

- Probes the public frontend URL (`NEXORA_FRONTEND_PROBE_TARGET`).
- Probes the backend readiness endpoint (`NEXORA_BACKEND_PROBE_TARGET`).
- Uses the `http_2xx` module defined in `blackbox/blackbox.yml`.

Key metrics used:

- `probe_success` - 1 when the probe succeeded, 0 otherwise.
- `probe_http_status_code` - HTTP status returned by the target.
- `probe_duration_seconds` - total probe duration.