# Deployment Evidence

This file records **real** command output captured during the deployment and
verification on the dedicated EC2 (`3.25.110.229`). It is a snapshot from 2026-11-21
(UTC); live values change over time. Genuine browser screenshots are in
[`../screenshots/`](../screenshots/).

## 1. Infrastructure

| Resource | Value |
|---|---|
| Region | `ap-southeast-2` |
| VPC | `vpc-08e9ccae535666c79` (`Nexora-M6-VPC`, `10.30.0.0/16`) |
| Subnet | `subnet-082ee92a6eb81b6e0` (`10.30.1.0/24`, public) |
| Internet gateway | `igw-0ded8c19eff0d21d5` |
| Security group | `sg-0fa47392dcb3ecab2` (`nexora-m6-sg`) |
| EC2 instance | `i-0bf4f95e480474d6a` (`c7i-flex.large`, 2 vCPU / 4 GiB) |
| Public IP | `3.25.110.229` |
| Private IP | `10.30.1.117` |
| EBS | 20 GiB gp3 |

> `t3.medium` was requested but the account is on the AWS **Free plan**, which only
> allows Free-Tier-eligible instance types. `c7i-flex.large` (same 2 vCPU / 4 GiB) is
> Free-Tier eligible and was used instead. No existing resources were modified.

## 2. Application health

```text
GET /health  -> {"status":"healthy","service":"nexora-api"}
GET /ready   -> {"status":"ready","service":"nexora-api"}
GET /healthz -> healthy
```

Backend metrics (direct from the backend container):

```text
http_requests_total{method="GET",route="/metrics",status="200"} 11
http_requests_total{method="GET",route="/ready",status="200"} 25
http_requests_total{method="GET",route="/health",status="200"} 16
nexora_up 1
nexora_build_info{version="0.1.0"} 1
```

## 3. Prometheus targets (6/6 UP)

```text
blackbox-backend     up       http://blackbox-exporter:9115/probe?...target=http://backend:3000/ready
blackbox-frontend    up       http://blackbox-exporter:9115/probe?...target=http://frontend:80/healthz
nexora-backend       up       http://backend:3000/metrics
node                 up       http://node-exporter:9100/metrics
postgres             up       http://postgres-exporter:9187/metrics
prometheus           up       http://localhost:9090/metrics
```

## 4. PromQL results (snapshot)

**Query 1 — HTTP request rate per route**

```text
{route="/health"}   0.046
{route="/metrics"}  0.032
{route="/ready"}    0.075
```

**Query 2 — Backend 5xx error ratio**

During normal operation there are no 5xx responses, so the ratio series is empty
(effectively 0%). During the deliberate database outage it reached:

```text
0.33764193724611025   (≈ 33.8%)
```

**Query 3 — Database connection utilisation**

```text
0.030927835051546393   (≈ 3.1% of usable connections)
```

## 5. Alert test (deliberate database outage)

```text
--- Stopping postgres (deliberate database outage)
--- Generating 503 traffic for 30s (backend /ready)
GET /ready -> 503   (×15)

--- Prometheus firing alerts
NexoraDatabaseDown  firing  critical  tier=database  instance=postgres-exporter:9187

--- Alertmanager alerts
NexoraDatabaseDown | active | critical

--- Restoring postgres
--- Prometheus firing alerts after restore
[]   (empty — resolved)

--- App health after restore
GET /ready -> {"status":"ready","service":"nexora-api"}
```

This was re-verified against the **actual** `NexoraDatabaseDown` alert: during a
controlled outage the Alertmanager UI/API showed the alert firing, and after recovery
the Alertmanager API returned **0 alerts** while `/ready` returned
`{"status":"ready"}`. See `screenshots/alerting/05-database-alert-firing.png` and
`06-database-alert-resolved.png`.

## 6. Notification test (webhook)

Alertmanager routed a synthetic `severity="test"` alert to a local webhook receiver.
Both the firing and the resolved payloads were received:

```text
==> Webhook log after firing:   {"receiver":"webhook-test","status":"firing", ...}
==> Webhook log after resolved: {"receiver":"webhook-test","status":"resolved", ...}
==> Notification status counts:
      2 "status":"firing"
      2 "status":"resolved"
```

> **Telegram:** the bot token is valid (bot `@granfana_alert_manager_bot`) and the
> credentials are configured, but Telegram returns `chat not found (400)` because the
> user has not started the bot. The Alertmanager log of the actual
`NexoraDatabaseDown` Telegram attempts (firing + resolved) is captured in
`screenshots/alerting/database-alert-log.txt` and `07-telegram-delivery-attempts.png`.
> Telegram is **not** claimed to work until a real message is received.

## 7. Grafana

```text
GET /api/health -> {"database":"ok","version":"11.4.0", ...}

--- Datasources
Prometheus | prometheus | http://prometheus:9090

--- Datasource health
{"message":"Successfully queried the Prometheus API.","status":"OK"}

--- Dashboards
Node Exporter Full | uid: rYdddlPWk
Three-Tier App - Production | uid: nexora-three-tier-prod
```

## 8. CI/CD

| Run | Event | Result |
|---|---|---|
| [44905336129](https://github.com/arifuzzaman-hredoy/DevOps-Module-6-Assignment/actions/runs/44905336129) | push to `main` | **success** — Validate ✓, Deploy ✓ |
| [44905993282](https://github.com/arifuzzaman-hredoy/DevOps-Module-6-Assignment/actions/runs/44905993282) | push to `main` (final) | **success** — Validate ✓, Deploy ✓ |
| [44905470131](https://github.com/arifuzzaman-hredoy/DevOps-Module-6-Assignment/actions/runs/44905470131) | PR from throwaway branch | **failure** — `promtool` rejected the intentionally invalid rule |

The failed run was produced on branch `ci/failure-demo` (PR #1), then the PR was
closed and the branch deleted. `main` remains valid.

## 9. Screenshots captured

Genuine browser screenshots were captured with headless Chrome against the live
deployment (and the public GitHub Actions pages):

- `screenshots/prometheus/` — targets (6/6 UP) and the three PromQL queries.
- `screenshots/grafana/` — datasource + health, Node Exporter Full (1860), Three-Tier App - Production.
- `screenshots/alerting/` — Alertmanager UI; actual `NexoraDatabaseDown` firing (`05-database-alert-firing.png`) and resolved (`06-database-alert-resolved.png`); Telegram delivery-attempt log (`07-telegram-delivery-attempts.png`, `database-alert-log.txt`); webhook firing/resolved payloads.
- `screenshots/github-actions/` — successful runs 44905993282 / 44909256927 and failed run 44905470131.

The missing screenshots are the **Telegram chat** views
(`03-telegram-firing.png`, `04-telegram-resolved.png`), which require the user to
start `@granfana_alert_manager_bot` and then re-run the delivery test.