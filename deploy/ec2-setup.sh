#!/usr/bin/env bash
# =============================================================================
# One-shot setup for the single-EC2 Module 6 deployment.
#
# Run from the cloned monitoring repo on the EC2:
#     bash deploy/ec2-setup.sh
#
# It is idempotent and safe to re-run. It:
#   1. adds swap (helps the Rust build fit in RAM),
#   2. clones the Module 4 Nexora source and the Module 6 monitoring repo,
#   3. applies the backend Prometheus instrumentation patch,
#   4. generates/loads secrets and least-privilege DB credentials,
#   5. builds and starts the Nexora app on a shared Docker network,
#   6. creates the nexora_monitoring PostgreSQL role,
#   7. renders and starts the monitoring stack,
#   8. leaves Prometheus/Alertmanager on loopback and Grafana on 0.0.0.0:3000.
# =============================================================================
set -euo pipefail

M6_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="/opt/nexora/app"
MON_DIR="/opt/nexora/monitoring"
SECRETS_FILE="/opt/nexora/secrets.env"
M4_REPO="https://github.com/arifuzzaman-hredoy/DevOps-Module-4-Assignment.git"
M6_REPO="https://github.com/arifuzzaman-hredoy/DevOps-Module-6-Assignment.git"

log() { echo "==> $*"; }

# --- 1. Swap ----------------------------------------------------------------
if ! swapon --show | grep -q '/swapfile'; then
    log "Creating 2 GiB swapfile"
    sudo fallocate -l 2G /swapfile || sudo dd if=/dev/zero of=/swapfile bs=1M count=2048
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
fi

# --- 2. Directories and source ---------------------------------------------
sudo mkdir -p /opt/nexora
sudo chown -R "$USER":"$USER" /opt/nexora

if [ ! -d "$APP_DIR/.git" ]; then
    log "Cloning Module 4 Nexora source"
    git clone --depth 1 "$M4_REPO" "$APP_DIR"
else
    log "Module 4 source already present"
fi

if [ ! -d "$MON_DIR/.git" ]; then
    log "Cloning Module 6 monitoring repo"
    git clone --depth 1 "$M6_REPO" "$MON_DIR"
else
    log "Module 6 repo already present"
fi

# --- 3. Apply the backend instrumentation patch -----------------------------
if git -C "$APP_DIR/backend" apply --check "$M6_ROOT/integration/backend/nexora-prometheus.patch" 2>/dev/null; then
    log "Applying backend Prometheus instrumentation patch"
    git -C "$APP_DIR/backend" apply "$M6_ROOT/integration/backend/nexora-prometheus.patch"
else
    log "Backend patch already applied (or not applicable); continuing"
fi

# --- 4. Secrets -------------------------------------------------------------
if [ ! -f "$SECRETS_FILE" ]; then
    log "Generating secrets"
    DB_PASSWORD="$(openssl rand -hex 24)"
    MONITORING_DB_PASSWORD="$(openssl rand -hex 24)"
    GRAFANA_ADMIN_PASSWORD="$(openssl rand -hex 16)"
    umask 077
    cat > "$SECRETS_FILE" <<EOF
DB_PASSWORD=$DB_PASSWORD
MONITORING_DB_PASSWORD=$MONITORING_DB_PASSWORD
GRAFANA_ADMIN_PASSWORD=$GRAFANA_ADMIN_PASSWORD
EOF
    chmod 600 "$SECRETS_FILE"
else
    log "Secrets already exist"
fi
# shellcheck disable=SC1090
source "$SECRETS_FILE"

# --- 5. App environment + override -----------------------------------------
cat > "$APP_DIR/.env.compose.local" <<EOF
DB_PASSWORD=$DB_PASSWORD
EOF
chmod 600 "$APP_DIR/.env.compose.local"
cp "$M6_ROOT/deploy/app/docker-compose.m6.yml" "$APP_DIR/docker-compose.m6.yml"

# --- 6. Shared network ------------------------------------------------------
docker network inspect nexora-net >/dev/null 2>&1 || docker network create nexora-net

# --- 7. Build and start the app --------------------------------------------
log "Building and starting Nexora app (this can take several minutes)"
cd "$APP_DIR"
docker compose --env-file .env.compose.local -f docker-compose.yml -f docker-compose.m6.yml up -d --build

log "Waiting for backend readiness"
ready=0
for _ in $(seq 1 90); do
    if curl -fsS http://127.0.0.1/ready >/dev/null 2>&1; then
        ready=1
        break
    fi
    sleep 5
done
if [ "$ready" -ne 1 ]; then
    log "ERROR: backend did not become ready"
    docker compose --env-file .env.compose.local -f docker-compose.yml -f docker-compose.m6.yml ps
    exit 1
fi
log "Backend is ready"

# --- 8. Least-privilege monitoring role ------------------------------------
log "Ensuring nexora_monitoring role"
docker compose --env-file .env.compose.local -f docker-compose.yml -f docker-compose.m6.yml exec -T postgres \
    psql -v ON_ERROR_STOP=1 -U nexora_app -d nexora -c "DO \$\$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='nexora_monitoring') THEN CREATE ROLE nexora_monitoring LOGIN PASSWORD '$MONITORING_DB_PASSWORD'; ELSE ALTER ROLE nexora_monitoring LOGIN PASSWORD '$MONITORING_DB_PASSWORD'; END IF; END \$\$; GRANT CONNECT ON DATABASE nexora TO nexora_monitoring; GRANT pg_monitor TO nexora_monitoring;"

# --- 9. Monitoring environment ---------------------------------------------
if [ ! -f "$MON_DIR/.env.deploy" ]; then
    log "Creating monitoring .env.deploy"
    cat > "$MON_DIR/.env.deploy" <<EOF
MONITORING_ENV=production
GRAFANA_BIND_ADDRESS=0.0.0.0
PROMETHEUS_BIND_ADDRESS=127.0.0.1
ALERTMANAGER_BIND_ADDRESS=127.0.0.1
PROMETHEUS_PORT=9090
GRAFANA_PORT=3000
ALERTMANAGER_PORT=9093
PROMETHEUS_RETENTION_TIME=15d
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=$GRAFANA_ADMIN_PASSWORD
NODE_EXPORTER_TARGET=node-exporter:9100
NEXORA_APP_METRICS_TARGET=backend:3000
NEXORA_DB_EXPORTER_TARGET=postgres-exporter:9187
NEXORA_FRONTEND_PROBE_TARGET=http://frontend:80/healthz
NEXORA_BACKEND_PROBE_TARGET=http://backend:3000/ready
NEXORA_DB_EXPORTER_DSN=postgresql://nexora_monitoring:$MONITORING_DB_PASSWORD@postgres:5432/nexora?sslmode=disable
TELEGRAM_BOT_TOKEN=CHANGE_ME_TELEGRAM_BOT_TOKEN
TELEGRAM_CHAT_ID=123456789
SMTP_SMARTHOST=smtp.example.com:587
SMTP_FROM=alertmanager@example.com
SMTP_TO=oncall@example.com
SMTP_AUTH_USERNAME=CHANGE_ME
SMTP_AUTH_PASSWORD=CHANGE_ME
SMTP_REQUIRE_TLS=true
ALERTMANAGER_RESOLVE_TIMEOUT=5m
EOF
    chmod 600 "$MON_DIR/.env.deploy"
else
    log "Monitoring .env.deploy already exists (leaving unchanged)"
fi

cp "$M6_ROOT/deploy/monitoring/docker-compose.m6.yml" "$MON_DIR/docker-compose.m6.yml"

# --- 10. Render and start monitoring ---------------------------------------
cd "$MON_DIR"
RENDER_ENV_FILE=.env.deploy python3 scripts/render_config.py
docker compose --env-file .env.deploy -f docker-compose.yml -f docker-compose.m6.yml up -d

log "Setup complete"
log "Prometheus:   http://127.0.0.1:9090  (SSH tunnel)"
log "Alertmanager: http://127.0.0.1:9093  (SSH tunnel)"
log "Grafana:      http://<this-host>:3000"