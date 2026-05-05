#!/bin/bash
# deploy.sh — zero-downtime deploy with automatic rollback
set -euo pipefail

DEPLOY_DIR="${DEPLOY_DIR:-/opt/statuspulse}"
GHCR_IMAGE="${GHCR_IMAGE:-ghcr.io/your-org/statuspulse}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
HEALTH_URL="${HEALTH_URL:-http://localhost:8000/health}"
LOG_FILE="/var/log/statuspulse-deploy.log"
ROLLBACK="${1:-}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

health_check() {
  local retries=10
  for i in $(seq 1 $retries); do
    STATUS=$(curl -sf "$HEALTH_URL" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))" 2>/dev/null || echo "failed")
    if [ "$STATUS" = "healthy" ]; then
      log "Health check passed."
      return 0
    fi
    log "Health check attempt $i/$retries failed (status=$STATUS), retrying..."
    sleep 5
  done
  return 1
}

cd "$DEPLOY_DIR"

# ── Rollback mode ──────────────────────────────────────────────────────────────
if [ "$ROLLBACK" = "rollback" ]; then
  log "=== ROLLBACK triggered ==="
  if [ -f .previous_tag ]; then
    PREV_TAG=$(cat .previous_tag)
    log "Rolling back to $GHCR_IMAGE:$PREV_TAG"
    IMAGE_TAG="$PREV_TAG"
    sed -i "s|image:.*|image: $GHCR_IMAGE:$IMAGE_TAG|g" docker-compose.yml
    docker-compose up -d api
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
CURRENT_TAG=$(grep -oP '(?<=:)[^"]+$' docker-compose.yml 2>/dev/null | head -1 || echo "latest")
echo "$CURRENT_TAG" > .previous_tag
log "Previous tag saved: $CURRENT_TAG"

# Pull new image
log "Pulling $GHCR_IMAGE:$IMAGE_TAG ..."
docker pull "$GHCR_IMAGE:$IMAGE_TAG"

# Update compose to use new tag
sed -i "s|image:.*statuspulse.*|image: $GHCR_IMAGE:$IMAGE_TAG|g" docker-compose.yml

# Start new container (zero-downtime: compose replaces one at a time)
log "Starting new container..."
docker-compose up -d --no-deps api

# Health check
if health_check; then
  log "Deploy successful: $IMAGE_TAG"
else
  log "Health check failed — initiating rollback to $CURRENT_TAG"
  IMAGE_TAG="$CURRENT_TAG"
  sed -i "s|image:.*statuspulse.*|image: $GHCR_IMAGE:$IMAGE_TAG|g" docker-compose.yml
  docker-compose up -d --no-deps api
  if health_check; then
    log "Rollback to $CURRENT_TAG succeeded."
  else
    log "CRITICAL: Rollback also failed. Manual intervention required."
  fi
  exit 1
fi
