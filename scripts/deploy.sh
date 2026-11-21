#!/usr/bin/env bash
# =============================================================================
# Deploy the Nexora monitoring stack on the deployment host (e.g. the AWS web
# tier). This script is safe to re-run: it is idempotent and only recreates
# containers whose configuration changed.
#
# It expects the repository to already be present on the host (GitHub Actions
# pulls it before calling this script) and a dotenv file with real values.
#
# Usage (on the host):
#     ENV_FILE=.env.deploy ./scripts/deploy.sh
#
# Environment:
#     ENV_FILE   Path to the deploy env file (default: .env.deploy)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

ENV_FILE="${ENV_FILE:-.env.deploy}"
COMPOSE=(docker compose --env-file "$ENV_FILE" -f docker-compose.yml)
if [[ -f "$ROOT/docker-compose.m6.yml" ]]; then
    COMPOSE+=(-f docker-compose.m6.yml)
fi

if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: env file '$ENV_FILE' not found in $ROOT" >&2
    echo "Create it from .env.example and fill in real values (never commit it)." >&2
    exit 1
fi

echo "==> Rendering configuration from ${ENV_FILE}"
RENDER_ENV_FILE="$ENV_FILE" python3 "$ROOT/scripts/render_config.py"

echo "==> Pulling images"
"${COMPOSE[@]}" pull --quiet

echo "==> Applying stack (up -d, remove orphans)"
"${COMPOSE[@]}" up -d --remove-orphans

echo "==> Reloading Prometheus and Alertmanager to pick up rendered config"
"${COMPOSE[@]}" restart prometheus alertmanager

echo "==> Waiting for services to become healthy"
"$ROOT/scripts/health-check.sh" || {
    echo "ERROR: health check failed after deploy" >&2
    "${COMPOSE[@]}" ps
    exit 1
}

echo "==> Deployment complete"
"${COMPOSE[@]}" ps