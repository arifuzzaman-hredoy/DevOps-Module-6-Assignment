# Nexora Integration

This document records the **actual** architecture of the existing Module 4 Nexora
application (verified from source, not assumed) and explains exactly how the Module 6
monitoring stack integrates with it without modifying or breaking it.

## 1. Verified Module 4 architecture

Source of truth: the Module 4 repository
(`.../Module -4 Assignment/nexora`) and its `README.md`, `docker-compose.yml`,
`backend/`, `frontend/`, and `nginx/` directories.

### 1.1 Technologies

| Tier | Technology | Evidence |
|---|---|---|
| Frontend | **React 19 + Vite + TypeScript**, served as static files by **Nginx** | `frontend/package.json`, `frontend/Dockerfile`, `frontend/nginx.conf` |
| Backend API | **Rust + Axum 0.8**, listening on `0.0.0.0:3000` | `backend/Cargo.toml`, `backend/src/main.rs` |
| Database | **PostgreSQL 16** (self-hosted on EC2, **not RDS**) | `docker-compose.yml` (`postgres:16`), `README.md` |
| Reverse proxy | **Nginx** on the web tier, proxies `/api/` to the backend | `nginx/nexora-http.conf.template`, `nginx/local.conf` |
| Process manager | **systemd** (`nexora-backend.service`) on the app tier | `README.md` |

### 1.2 Application endpoints

From `backend/src/router.rs`:

| Method | Route | Purpose |
|---|---|---|
| GET | `/health` | Liveness (always healthy if process is up) |
| GET | `/ready` | Readiness (runs `SELECT 1` against PostgreSQL) |
| POST | `/api/auth/register` | Register |
| POST | `/api/auth/login` | Login (rate-limited) |
| GET | `/api/auth/me` | Current user |
| GET | `/api/auth/csrf` | CSRF token |
| POST | `/api/auth/logout` | Logout |
| GET/POST | `/api/tasks` | List / create tasks |
| GET/PUT/DELETE | `/api/tasks/{id}` | Get / update / delete task |
| GET | `/metrics` | **Added by this project** (Prometheus exposition) |

Frontend container health endpoint: `GET /healthz` (Nginx, `frontend/nginx.conf`).

### 1.3 Network topology (AWS)

Three Ubuntu 24.04 EC2 instances in a custom VPC (`10.30.0.0/16`):

```
Internet
   | HTTPS 443
[ Web tier  ]  EC2 + Nginx + React build     10.30.1.217  (public, Elastic IP)
   | /api/  -> TCP 3000
[ App tier  ]  EC2 + Rust/Axum (systemd)     10.30.2.82   (private)
   | PostgreSQL 5432
[ DB tier   ]  EC2 + PostgreSQL 16           10.30.3.195  (private)
```

Security groups (from Module 4 README):

| SG | Port | Source | Purpose |
|---|---|---|---|
| Web | 80, 443 | `0.0.0.0/0` | HTTP/HTTPS |
| Web | 22 | admin CIDR | SSH |
| App | 3000 | Web SG | Backend API |
| DB | 5432 | App SG | PostgreSQL |

## 2. Monitoring integration approach

### 2.1 Where the monitoring stack runs

The monitoring stack is designed to run on the **web tier** (the only public tier),
as a separate Docker Compose project (`nexora-monitoring`). It does not touch the
existing Nexora containers/systemd services.

- Prometheus, Grafana, Alertmanager, Node Exporter, postgres_exporter, and
  blackbox-exporter all run in one dedicated Docker network (`nexora-monitoring`).
- No exporter ports are published. Prometheus (9090), Grafana (3000), and
  Alertmanager (9093) are published on **loopback only** by default
  (`MONITORING_BIND_ADDRESS=127.0.0.1`). Access them via SSH tunnel or put them
  behind the existing Nginx.

### 2.2 How Prometheus reaches each target

| Target | Address used by Prometheus | Reachable because |
|---|---|---|
| Node Exporter | `node-exporter:9100` | Same Docker network |
| postgres_exporter | `postgres-exporter:9187` | Same Docker network; exporter connects to DB via `NEXORA_DB_EXPORTER_DSN` |
| Backend `/metrics` | `${NEXORA_APP_METRICS_TARGET}` (e.g. `10.30.2.82:3000`) | App SG must allow TCP 3000 from the Web SG (already true) |
| Frontend probe | `${NEXORA_FRONTEND_PROBE_TARGET}` (public HTTPS URL) | Public internet / blackbox-exporter egress |
| Backend health probe | `${NEXORA_BACKEND_PROBE_TARGET}` (e.g. `http://10.30.2.82:3000/ready`) | App SG allows Web SG |

Containers that need to reach the host (local Docker Desktop) use
`extra_hosts: host.docker.internal:host-gateway`.

### 2.3 Required manual infrastructure changes (PART B)

These are **not** performed by this repository. Document them for the deployment:

1. **Backend instrumentation** — apply `integration/backend/nexora-prometheus.patch`
   to the Module 4 backend, rebuild the image / binary, and restart
   `nexora-backend.service`. See `integration/backend/README.md`.
2. **Block `/metrics` at the edge** — the backend now exposes `/metrics`. If Nginx
   proxies `/api/` only, `/metrics` is already not exposed (Nginx does not proxy
   `/metrics`). If you ever proxy `/metrics`, restrict it to the monitoring source.
3. **PostgreSQL monitoring role** — run `exporters/postgres-monitor-role.sql` once on
   the DB server and put the DSN in `.env` as `NEXORA_DB_EXPORTER_DSN`.
4. **Security group** — confirm the App SG allows TCP 3000 from the Web SG (it does),
   so Prometheus (on the web tier) can scrape the backend. No DB SG change is needed
   for postgres_exporter because it connects from the web tier; if you run the
   exporter on the DB tier instead, allow 9187 from the Web SG.
5. **Optional full host coverage** — run one Node Exporter per EC2 instance and add
   each host to the `node` job in `prometheus.yml` to monitor app and DB hosts too.

### 2.4 Target configuration: local vs AWS

All addresses are environment variables in `.env` (see `.env.example`).

| Variable | Local (Docker Desktop) | AWS (web tier) |
|---|---|---|
| `NEXORA_APP_METRICS_TARGET` | `host.docker.internal:3000` | `10.30.2.82:3000` |
| `NEXORA_DB_EXPORTER_DSN` | `postgresql://nexora_monitoring:***@host.docker.internal:5432/nexora?sslmode=disable` | `postgresql://nexora_monitoring:***@10.30.3.195:5432/nexora?sslmode=require` |
| `NEXORA_FRONTEND_PROBE_TARGET` | `https://nexora.oxytumzone.com` (or local Nginx URL) | `https://nexora.oxytumzone.com` |
| `NEXORA_BACKEND_PROBE_TARGET` | `http://host.docker.internal:3000/ready` | `http://10.30.2.82:3000/ready` |

> Never commit a real `.env`. Use `.env.example` as the template and supply real
> values on the server (and via GitHub Secrets for CI/CD).

### 2.5 What is explicitly not changed

- The Module 4 repository is not modified by this project.
- No Nexora containers, systemd units, Nginx config, or database data are touched.
- The monitoring stack uses its own Compose project name, network, volumes, and
  container names (`nexora-prometheus`, `nexora-grafana`, ...) to avoid collisions.