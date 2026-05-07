#!/bin/bash
# backup.sh — PostgreSQL backup with rotation and optional Azure Blob / S3 upload
# Cron: 0 2 * * * /opt/statuspulse/scripts/backup.sh
set -euo pipefail

# ── Config ─────────────────────────────────────────────────────────────────────
DEPLOY_DIR="${DEPLOY_DIR:-/opt/statuspulse}"
BACKUP_DIR="${BACKUP_DIR:-${DEPLOY_DIR}/backups}"
KEEP_LAST="${KEEP_LAST:-7}"
COMPOSE_FILE="${DEPLOY_DIR}/docker-compose.yml"
TIMESTAMP=$(date '+%Y-%m-%d_%H%M%S')
FILENAME="statuspulse_db_${TIMESTAMP}.sql.gz"

# Azure Blob Storage (optional)
AZURE_STORAGE_ACCOUNT="${AZURE_STORAGE_ACCOUNT:-}"
AZURE_CONTAINER="${AZURE_CONTAINER:-statuspulse-backups}"

# AWS S3 (optional fallback)
S3_BUCKET="${S3_BUCKET:-}"

# DB credentials (read from .env if not already in environment)
if [ -f "${DEPLOY_DIR}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "${DEPLOY_DIR}/.env"
  set +a
fi
DB_USER="${DB_USER:-statuspulse}"
DB_NAME="${DB_NAME:-statuspulse}"

# ── Logging ────────────────────────────────────────────────────────────────────
mkdir -p "$BACKUP_DIR"
LOG_FILE="${BACKUP_DIR}/backup.log"
touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/tmp/statuspulse-backup.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

log "================================================================"
log "=== Backup started: $FILENAME ==="
log "================================================================"

# ── Verify compose stack is running ───────────────────────────────────────────
if ! docker compose -f "$COMPOSE_FILE" ps --services --filter "status=running" 2>/dev/null | grep -q "^db$"; then
  log "ERROR: 'db' container is not running. Aborting backup."
  exit 1
fi

# ── Dump PostgreSQL ────────────────────────────────────────────────────────────
log "Dumping database '${DB_NAME}' as user '${DB_USER}'..."
docker compose -f "$COMPOSE_FILE" exec -T db \
  pg_dump -U "$DB_USER" "$DB_NAME" \
  | gzip > "${BACKUP_DIR}/${FILENAME}"

if [ ! -s "${BACKUP_DIR}/${FILENAME}" ]; then
  log "ERROR: Backup file is empty. pg_dump may have failed."
  rm -f "${BACKUP_DIR}/${FILENAME}"
  exit 1
fi

SIZE=$(du -sh "${BACKUP_DIR}/${FILENAME}" | cut -f1)
log "Backup saved: ${BACKUP_DIR}/${FILENAME} (${SIZE})"

# ── Upload to Azure Blob Storage ───────────────────────────────────────────────
if [ -n "$AZURE_STORAGE_ACCOUNT" ]; then
  if command -v az &>/dev/null; then
    log "Uploading to Azure Blob: ${AZURE_STORAGE_ACCOUNT}/${AZURE_CONTAINER}/${FILENAME}..."
    az storage blob upload \
      --account-name "$AZURE_STORAGE_ACCOUNT" \
      --container-name "$AZURE_CONTAINER" \
      --name "$FILENAME" \
      --file "${BACKUP_DIR}/${FILENAME}" \
      --auth-mode login \
      --output none
    log "Azure upload complete: ${AZURE_CONTAINER}/${FILENAME}"
  else
    log "WARNING: AZURE_STORAGE_ACCOUNT is set but 'az' CLI not found. Skipping Azure upload."
  fi
fi

# ── Upload to S3 (optional fallback) ──────────────────────────────────────────
if [ -n "$S3_BUCKET" ]; then
  if command -v aws &>/dev/null; then
    log "Uploading to S3: s3://${S3_BUCKET}/statuspulse/${FILENAME}..."
    aws s3 cp "${BACKUP_DIR}/${FILENAME}" "s3://${S3_BUCKET}/statuspulse/${FILENAME}"
    log "S3 upload complete: s3://${S3_BUCKET}/statuspulse/${FILENAME}"
  else
    log "WARNING: S3_BUCKET is set but 'aws' CLI not found. Skipping S3 upload."
  fi
fi

# ── Rotate — keep only last N backups ─────────────────────────────────────────
log "Rotating old backups (keeping last ${KEEP_LAST})..."
BACKUP_COUNT=$(ls -1 "${BACKUP_DIR}"/statuspulse_db_*.sql.gz 2>/dev/null | wc -l)
log "Current backup count: ${BACKUP_COUNT}"

ls -1t "${BACKUP_DIR}"/statuspulse_db_*.sql.gz 2>/dev/null \
  | tail -n "+$((KEEP_LAST + 1))" \
  | while read -r old_backup; do
      rm -f "$old_backup"
      log "Deleted old backup: $old_backup"
    done

REMAINING=$(ls -1 "${BACKUP_DIR}"/statuspulse_db_*.sql.gz 2>/dev/null | wc -l)
log "Backups remaining after rotation: ${REMAINING}"

log "=== Backup complete ==="
