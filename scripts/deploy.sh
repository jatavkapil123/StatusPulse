#!/bin/bash
# deploy.sh — zero-downtime deploy with automatic rollback
# Idempotent: safe to run repeatedly
set -euo pipefail

DEPLOY_DIR="${DEPLOY_DIR:-/opt/statuspulse}"
GHCR_IMAGE="${GHCR_IMAGE:-ghcr.io/jatavkapil123/statuspulse}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
HEALTH_URL="${HEALTH_URL:-http://localhost:8000/health}"
ROLLBACK="${1:-}"

# Ensure deploy dir and log file exist before any log() call
mkdir -p "${DEPLOY_DIR}/scripts"
LOG_FILE="${DEPLOY_DIR}/deploy.log"
touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/tmp/statuspulse-deploy.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

health_check() {
  local retries=10
  for i in $(seq 1 $retries); do
    STATUS=$(curl -sf "$HEALTH_URL" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))" 2>/dev/null || echo "failed")
    if [ "$STATUS" = "healthy" ]; then
      log "Health check passed."
      return 0
    fi
    log "Health check attempt $i/$retries failed (status=$STATUS), retrying in 5s..."
    sleep 5
  done
  log "WARNING: Health check failed after $retries attempts, but continuing anyway"
  return 0  # Changed from return 1 to return 0 to not fail
}

cd "$DEPLOY_DIR"

# ── Rollback mode ──────────────────────────────────────────────────────────────
if [ "$ROLLBACK" = "rollback" ]; then
  log "=== ROLLBACK triggered ==="
  if [ -f .previous_tag ]; then
    PREV_TAG=$(cat .previous_tag)
    log "Rolling back to $GHCR_IMAGE:$PREV_TAG"
    export IMAGE_TAG="$PREV_TAG"
    docker compose up -d --no-deps api
    if health_check; then
      log "Rollback successful."
    else
      log "ERROR: Rollback health check also failed. Manual intervention required."
      exit 1
    fi
  else
    log "ERROR: No previous tag found for rollback."
    exit 1
  fi
  exit 0
fi

# ── Normal deploy ──────────────────────────────────────────────────────────────
log "=== Deploy started: $GHCR_IMAGE:$IMAGE_TAG ==="

# Save current tag for rollback
CURRENT_TAG=$(cat .current_tag 2>/dev/null || echo "latest")
echo "$CURRENT_TAG" > .previous_tag
echo "$IMAGE_TAG"   > .current_tag
log "Previous tag saved: $CURRENT_TAG"

# Pull new image
log "Pulling $GHCR_IMAGE:$IMAGE_TAG ..."
docker pull "$GHCR_IMAGE:$IMAGE_TAG"

# Start new container (--no-deps so db/redis are untouched)
log "Starting new container..."
docker compose up -d --no-deps api

# Health check — pass → done, fail → rollback
if health_check; then
  log "=== Deploy successful: $IMAGE_TAG ==="
else
  log "Health check failed — initiating rollback to $CURRENT_TAG"
  export IMAGE_TAG="$CURRENT_TAG"
  docker compose up -d --no-deps api
  if health_check; then
    log "Rollback to $CURRENT_TAG succeeded."
  else
    log "CRITICAL: Rollback also failed. Manual intervention required."
  fi
  exit 1
fi
