#!/bin/bash
# backup.sh — PostgreSQL backup with rotation and optional S3 upload
# Cron: 0 2 * * * /opt/statuspulse/scripts/backup.sh

set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/opt/statuspulse/backups}"
KEEP_DAYS=7
S3_BUCKET="${S3_BUCKET:-}"
LOG_FILE="/var/log/statuspulse-backup.log"
TIMESTAMP=$(date '+%Y-%m-%d_%H%M%S')
FILENAME="statuspulse_db_${TIMESTAMP}.sql.gz"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

mkdir -p "$BACKUP_DIR"
log "=== Backup started: $FILENAME ==="

# Dump and compress
docker-compose -f /opt/statuspulse/docker-compose.yml exec -T db \
  pg_dump -U "${DB_USER:-statuspulse}" "${DB_NAME:-statuspulse}" \
  | gzip > "$BACKUP_DIR/$FILENAME"

SIZE=$(du -sh "$BACKUP_DIR/$FILENAME" | cut -f1)
log "Backup saved: $BACKUP_DIR/$FILENAME ($SIZE)"

# Optional S3 upload
if [ -n "$S3_BUCKET" ]; then
  if command -v aws &>/dev/null; then
    aws s3 cp "$BACKUP_DIR/$FILENAME" "s3://$S3_BUCKET/statuspulse/$FILENAME"
    log "Uploaded to s3://$S3_BUCKET/statuspulse/$FILENAME"
  else
    log "WARNING: S3_BUCKET set but 'aws' CLI not found, skipping upload"
  fi
fi

# Rotate — keep only last 7 backups
log "Rotating old backups (keeping last $KEEP_DAYS)..."
ls -1t "$BACKUP_DIR"/statuspulse_db_*.sql.gz 2>/dev/null | tail -n +$((KEEP_DAYS+1)) | while read -r old; do
  rm -f "$old"
  log "Deleted old backup: $old"
done

log "=== Backup complete ==="
