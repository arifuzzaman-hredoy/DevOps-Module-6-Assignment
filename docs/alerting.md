# Alerting

## 1. Alert rules

All rules live in `prometheus/rules/alerts.yml` and are validated with
`promtool check rules`. There are 12 rules in 4 groups.

### 1.1 Availability (`nexora-availability`)

| Alert | Condition | For | Severity | Tier |
|---|---|---|---|---|
| `NexoraBackendDown` | `up{job="nexora-backend"} == 0` | 2m | critical | backend |
| `NexoraFrontendDown` | `probe_success{job="blackbox-frontend"} == 0` | 2m | critical | frontend |
| `NexoraDatabaseDown` | `pg_up{job="postgres"} == 0` | 2m | critical | database |
| `NexoraNodeExporterDown` | `up{job="node"} == 0` | 3m | warning | server |
| `NexoraBackendHealthProbeFailing` | `probe_success{job="blackbox-backend"} == 0` | 3m | warning | backend |

This covers all three application tiers (frontend, backend, database) plus the host.

### 1.2 Backend API performance (`nexora-api-performance`)

| Alert | Condition | For | Severity |
|---|---|---|---|
| `NexoraBackendHighErrorRate` | 5xx ratio > 5% | 10m | warning |
| `NexoraBackendCriticalErrorRate` | 5xx ratio > 10% | 5m | critical |
| `NexoraBackendHighLatency` | p95 latency > 1s | 10m | warning |

The error-rate expression uses a 5-minute rate and `clamp_min` to avoid division by
zero; the `for` durations prevent flapping on isolated errors.

### 1.3 Database saturation (`nexora-database`)

| Alert | Condition | For | Severity |
|---|---|---|---|
| `NexoraDatabaseConnectionsHigh` | connection usage > 80% | 10m | warning |

### 1.4 Server resources (`nexora-resources`)

| Alert | Condition | For | Severity |
|---|---|---|---|
| `NexoraHighCpuUsage` | CPU > 85% | 10m | warning |
| `NexoraHighMemoryUsage` | memory > 90% | 10m | warning |
| `NexoraLowDiskSpace` | root free < 15% | 10m | warning |

## 2. Alertmanager

Template: `alertmanager/alertmanager.yml.template` → rendered to
`alertmanager/alertmanager.yml`.

### 2.1 Routing

- Default receiver: `telegram`.
- `group_by: [alertname, tier, service]` — related alerts are grouped.
- `group_wait: 30s`, `group_interval: 5m`, `repeat_interval: 4h`.
- A child route matches `severity="critical"` with faster timing
  (`group_wait: 10s`, `repeat_interval: 1h`).

### 2.2 Inhibition

- `NexoraNodeExporterDown` inhibits all warning/critical alerts on the same
  `instance` (the host is down, so per-service alerts are redundant).
- `NexoraDatabaseDown` inhibits `NexoraDatabaseConnectionsHigh` on the same
  `instance` (the DB being down explains connection problems).

### 2.3 Receivers

| Receiver | Channel | Notes |
|---|---|---|
| `telegram` | Telegram bot | `send_resolved: true`, used by all routes |
| `email` | SMTP | Defined but not routed by default; add a route to enable |

### 2.4 Resolved notifications

`send_resolved: true` is set on both receivers, so Telegram receives a follow-up
message when an alert resolves.

## 3. Security

Secrets are **never** stored in git. The rendered Alertmanager config reads them from
the environment (`.env` on the server, GitHub Secrets in CI):

| Variable | Used for |
|---|---|
| `TELEGRAM_BOT_TOKEN` | Telegram bot token from @BotFather |
| `TELEGRAM_CHAT_ID` | Numeric chat/group id |
| `SMTP_SMARTHOST`, `SMTP_FROM`, `SMTP_TO` | Email (optional) |
| `SMTP_AUTH_USERNAME`, `SMTP_AUTH_PASSWORD` | Email auth (optional) |

`.env` is git-ignored; `.env.example` contains only placeholders.

## 4. Manual Telegram setup (PART B)

1. Create a bot with **@BotFather** → `/newbot` → copy the **bot token**.
2. Add the bot to the target group/channel (or message it directly).
3. Get the **numeric chat id**:
   - Message the bot, then open
     `https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates` and read
     `message.chat.id`, or
   - Add **@getidsbot** to the group and read the id.
4. Put the values in the server's `.env`:

   ```dotenv
   TELEGRAM_BOT_TOKEN=1234567890:AAEXAMPLE_NOT_A_REAL_TOKEN
   TELEGRAM_CHAT_ID=-1001234567890
   ```

5. Re-render and restart Alertmanager:

   ```bash
   RENDER_ENV_FILE=.env ./scripts/render-config.sh
   docker compose restart alertmanager
   ```

6. **Test** by sending a test notification (Alertmanager UI → *Status* → or trigger a
   rule). Do not claim notifications work until you have received a real message.

## 5. Testing alerts without breaking production

- **Synthetic probe failure:** temporarily point `NEXORA_FRONTEND_PROBE_TARGET` at an
  unreachable URL in a staging `.env`, reload Prometheus, and confirm
  `NexoraFrontendDown` fires.
- **Manual alert:** POST a test alert to Alertmanager or use `amtool`:

  ```bash
  amtool alert add --alertmanager.url=http://127.0.0.1:9093 \
    alertname=TestAlert severity=warning tier=test --annotation.summary="test"
  ```

  Then resolve it and confirm the resolved notification.

## 6. Notification delivery verification

Because Telegram credentials are user-only, `scripts/test-notification.sh` sends a
synthetic `severity="test"` alert to a local webhook receiver
(`scripts/webhook_listener.py`) and captures the firing and resolved payloads. The
actual run received **2 firing + 2 resolved** webhook payloads (see
[`evidence.md`](evidence.md) §6), proving Alertmanager routing, grouping, and
`send_resolved` work end to end. Telegram delivery remains pending the user's bot
token and chat id.

## 7. Alert rule test

`scripts/test-alerting.sh` deliberately stops PostgreSQL, generates 503 traffic, and
captures the result. Actual result: `NexoraDatabaseDown` fired (critical), the backend
5xx error ratio reached ≈ 33.8%, and the alert resolved after PostgreSQL was restored
(see [`evidence.md`](evidence.md) §5).