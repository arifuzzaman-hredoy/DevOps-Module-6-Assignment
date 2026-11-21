# Nexora Backend Instrumentation (Prometheus metrics)

This directory contains the **minimal, separately documented** backend change that
adds a Prometheus `/metrics` endpoint to the existing Module 4 **Nexora** Rust/Axum
backend.

The Module 4 repository is **not** modified by this project. The change is delivered
as a patch that you apply to your own Module 4 checkout during PART B.

## Files

| File | Purpose |
|---|---|
| `nexora-prometheus.patch` | **Authoritative** unified diff. Applies cleanly to the current Nexora backend with `git apply`. |
| `metrics.rs` | The new source file added by the patch, included for readability/review. |

The patch modifies only:

- `Cargo.toml` — adds `metrics` and `metrics-exporter-prometheus` dependencies.
- `Cargo.lock` — updated lockfile so `cargo build --locked` (used by the Dockerfile) keeps working.
- `src/main.rs` — declares the module and installs the metrics recorder.
- `src/router.rs` — adds the `GET /metrics` route and the metrics middleware layer.
- `src/metrics.rs` — new file (recorder, handler, request middleware).

## What is instrumented

| Metric | Type | Labels | Meaning |
|---|---|---|---|
| `http_requests_total` | counter | `method`, `route`, `status` | Total HTTP requests |
| `http_request_duration_seconds` | histogram | `method`, `route`, `status` | Request latency distribution |
| `nexora_up` | gauge | — | Always 1 while the process runs (availability signal) |
| `nexora_build_info` | gauge | `version` | Build/version info |

Cardinality is deliberately kept low: labels are restricted to HTTP method, the
matched route template (e.g. `/api/tasks/{id}`, **never** the concrete URL), and the
status code class. User IDs, request IDs, and raw URLs are never used as labels.

The `http_requests_total` counter and `http_request_duration_seconds` histogram are
exactly what the Grafana dashboard and the error-rate / latency alert rules consume.

## Apply the patch (PART B)

From the Nexora backend directory (adjust the paths to your machine):

```bash
cd "/mnt/g/My Skill Learn Plan/Technology/Cloud & DevOps/DevSecOps/DevOps/Ostad/Module -4 Assignment/nexora/backend"

# 1. Preview / verify it applies cleanly
git apply --check "/mnt/g/My Skill Learn Plan/Technology/Cloud & DevOps/DevSecOps/DevOps/Ostad/Module -6 Assignment/integration/backend/nexora-prometheus.patch"

# 2. Apply
git apply "/mnt/g/My Skill Learn Plan/Technology/Cloud & DevOps/DevSecOps/DevOps/Ostad/Module -6 Assignment/integration/backend/nexora-prometheus.patch"

# 3. Verify it compiles
cargo check

# 4. Build the image / restart the service using your normal deployment process
```

> The patch is generated against the **current working tree** of the Module 4
> backend. If you have changed `Cargo.toml`, `Cargo.lock`, `main.rs`, or `router.rs`
> since then, review the patch with `git apply --3way` or re-generate it.

## Verify at runtime

```bash
# Local (Docker Compose or cargo run)
curl -s http://127.0.0.1:3000/metrics | head

# You should see (after some traffic):
#   http_requests_total{method="GET",route="/health",status="200"} 1
#   http_request_duration_seconds_bucket{...,le="0.1"} ...
#   nexora_up 1
#   nexora_build_info{version="0.1.0"} 1
```

The `/metrics` endpoint is unauthenticated. It should only be reachable from the
monitoring network / Prometheus. If the backend is exposed through Nginx, block
`/metrics` at the proxy (see `docs/nexora-integration.md`).

## How the code works

- `metrics::install()` builds a Prometheus recorder with explicit histogram buckets
  (5 ms … 10 s) and installs it as the global `metrics` recorder. It stores the
  `PrometheusHandle` in a `OnceLock`.
- `metrics_handler()` renders the current registry in Prometheus text exposition format.
- `track_metrics()` is an Axum middleware that reads the matched route (via
  `MatchedPath`), times the request, and records the counter + histogram. Requests
  that do not match a route are labelled `route="unmatched"`.

## Compile validation performed in PART A

The instrumented tree was compiled with `cargo check` (Rust 1.99.1) and finished
successfully. The patch was verified to apply cleanly to a fresh copy of the backend
with `git apply --check`.