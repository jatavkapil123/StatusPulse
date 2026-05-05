#!/bin/bash
# health-monitor.sh — runs every 5 minutes via cron
# crontab: */5 * * * * /opt/statuspulse/scripts/health-monitor.sh

HEALTH_URL="${HEALTH_URL:-http://localhost:8000/health}"
ALERT_WEBHOOK_URL="${ALERT_WEBHOOK_URL:-}"
LOG_FILE="/var/log/statuspulse-monitor.log"
DISK_THRESHOLD=80
MEM_THRESHOLD=90
CERT_WARN_DAYS=14
DOMAIN="${DOMAIN:-localhost}"
EXPECTED_CONTAINERS=("statuspulse_api_1" "statuspulse_db_1" "statuspulse_redis_1")

log()   { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
alert() {
  local msg="$1"
  log "ALERT: $msg"
  if [ -n "$ALERT_WEBHOOK_URL" ]; then
    curl -sf -X POST "$ALERT_WEBHOOK_URL" \
      -H "Content-Type: application/json" \
      -d "{\"text\":\"[StatusPulse Monitor] $msg\"}" \
      --max-time 10 || log "WARNING: Failed to send webhook alert"
  fi
}

# ── /health endpoint ───────────────────────────────────────────────────────────
log "--- Health monitor run ---"
HTTP_CODE=$(curl -sf -o /tmp/sp_health.json -w "%{http_code}" --max-time 10 "$HEALTH_URL" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" != "200" ]; then
  alert "/health returned HTTP $HTTP_CODE (expected 200)"
else
  STATUS=$(python3 -c "import json; d=json.load(open('/tmp/sp_health.json')); print(d.get('status',''))" 2>/dev/null || echo "parse_error")
  if [ "$STATUS" != "healthy" ]; then
    alert "/health status=$STATUS"
  else
    log "OK: /health is healthy"
  fi
fi

# ── Disk usage ─────────────────────────────────────────────────────────────────
DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
if [ "$DISK_USAGE" -gt "$DISK_THRESHOLD" ]; then
  alert "Disk usage is ${DISK_USAGE}% (threshold: ${DISK_THRESHOLD}%)"
else
  log "OK: Disk usage ${DISK_USAGE}%"
fi

# ── Memory usage ───────────────────────────────────────────────────────────────
MEM_USAGE=$(free | awk '/^Mem:/ {printf "%.0f", $3/$2*100}')
if [ "$MEM_USAGE" -gt "$MEM_THRESHOLD" ]; then
  alert "Memory usage is ${MEM_USAGE}% (threshold: ${MEM_THRESHOLD}%)"
else
  log "OK: Memory usage ${MEM_USAGE}%"
fi

# ── Docker containers ──────────────────────────────────────────────────────────
if command -v docker &>/dev/null; then
  for container in "${EXPECTED_CONTAINERS[@]}"; do
    RUNNING=$(docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null || echo "false")
    if [ "$RUNNING" != "true" ]; then
      alert "Container $container is NOT running"
    else
      log "OK: Container $container is running"
    fi
  done
else
  log "WARNING: docker command not found, skipping container checks"
fi

# ── TLS certificate expiry ─────────────────────────────────────────────────────
if [ "$DOMAIN" != "localhost" ] && command -v openssl &>/dev/null; then
  EXPIRY=$(echo | timeout 5 openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" 2>/dev/null \
    | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2 || echo "")
  if [ -n "$EXPIRY" ]; then
    EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s 2>/dev/null || echo "0")
    NOW_EPOCH=$(date +%s)
    DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))
    if [ "$DAYS_LEFT" -lt "$CERT_WARN_DAYS" ]; then
      alert "TLS certificate for $DOMAIN expires in ${DAYS_LEFT} days"
    else
      log "OK: TLS certificate expires in ${DAYS_LEFT} days"
    fi
  else
    log "WARNING: Could not retrieve TLS certificate for $DOMAIN"
  fi
fi

log "--- Monitor run complete ---"
