#!/bin/bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8000}"
PASS=0
FAIL=0
mkdir -p tests/results

log() { echo "[$(date '+%H:%M:%S')] $*"; }
pass() { log "PASS: $1"; PASS=$((PASS+1)); }
fail() { log "FAIL: $1 — $2"; FAIL=$((FAIL+1)); }

check_status() {
  local label="$1" url="$2" expected="$3"
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" "$url")
  if [ "$code" = "$expected" ]; then
    pass "$label (HTTP $code)"
  else
    fail "$label" "expected HTTP $expected, got $code"
  fi
}

check_json_field() {
  local label="$1" url="$2" method="$3" body="$4" field="$5" expected="$6"
  local response
  if [ "$method" = "POST" ]; then
    response=$(curl -s -X POST "$url" -H "Content-Type: application/json" -d "$body")
  else
    response=$(curl -s "$url")
  fi
  local value
  value=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('$field','MISSING'))" 2>/dev/null || echo "PARSE_ERROR")
  if [ "$value" = "$expected" ]; then
    pass "$label (field '$field'='$expected')"
  else
    fail "$label" "expected '$field'='$expected', got '$value' | response: $response"
  fi
}

log "=== StatusPulse Integration Tests ==="
log "Target: $BASE_URL"

# ── GET /health ────────────────────────────────────────────────────────────────
check_status "GET /health returns 200" "$BASE_URL/health" "200"
check_json_field "GET /health status=healthy" "$BASE_URL/health" "GET" "" "status" "healthy"

# ── GET / ──────────────────────────────────────────────────────────────────────
check_status "GET / returns 200" "$BASE_URL/" "200"
check_json_field "GET / service=StatusPulse" "$BASE_URL/" "GET" "" "service" "StatusPulse"

# ── POST /services ─────────────────────────────────────────────────────────────
SERVICE_BODY='{"name":"test-service","url":"https://example.com"}'
check_status "POST /services returns 200" "$BASE_URL/services" "200"

# Create service
RESPONSE=$(curl -s -X POST "$BASE_URL/services" \
  -H "Content-Type: application/json" \
  -d "$SERVICE_BODY")
SVC_NAME=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('name',''))" 2>/dev/null || echo "")
if [ "$SVC_NAME" = "test-service" ]; then
  pass "POST /services creates service"
else
  fail "POST /services creates service" "got: $RESPONSE"
fi

# Duplicate → 409
DUP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/services" \
  -H "Content-Type: application/json" -d "$SERVICE_BODY")
if [ "$DUP_CODE" = "409" ]; then
  pass "POST /services duplicate returns 409"
else
  fail "POST /services duplicate returns 409" "got HTTP $DUP_CODE"
fi

# ── GET /services ──────────────────────────────────────────────────────────────
check_status "GET /services returns 200" "$BASE_URL/services" "200"
SVC_LIST=$(curl -s "$BASE_URL/services")
SVC_COUNT=$(echo "$SVC_LIST" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
if [ "$SVC_COUNT" -ge "1" ]; then
  pass "GET /services returns at least 1 service"
else
  fail "GET /services returns at least 1 service" "got $SVC_COUNT"
fi

# ── POST /incidents ────────────────────────────────────────────────────────────
INC_BODY='{"service_name":"test-service","title":"Test Incident","description":"Integration test","severity":"minor"}'
INC_RESPONSE=$(curl -s -X POST "$BASE_URL/incidents" \
  -H "Content-Type: application/json" -d "$INC_BODY")
INC_STATUS=$(echo "$INC_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))" 2>/dev/null || echo "")
if [ "$INC_STATUS" = "investigating" ]; then
  pass "POST /incidents creates incident"
else
  fail "POST /incidents creates incident" "got: $INC_RESPONSE"
fi

INC_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/incidents" \
  -H "Content-Type: application/json" -d "$INC_BODY")
if [ "$INC_CODE" = "200" ]; then
  pass "POST /incidents returns 200"
else
  fail "POST /incidents returns 200" "got HTTP $INC_CODE"
fi

# ── GET /incidents ─────────────────────────────────────────────────────────────
check_status "GET /incidents returns 200" "$BASE_URL/incidents" "200"
INC_LIST=$(curl -s "$BASE_URL/incidents")
INC_COUNT=$(echo "$INC_LIST" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
if [ "$INC_COUNT" -ge "1" ]; then
  pass "GET /incidents returns at least 1 incident"
else
  fail "GET /incidents returns at least 1 incident" "got $INC_COUNT"
fi

# ── Summary ────────────────────────────────────────────────────────────────────
echo ""
log "=== Results: $PASS passed, $FAIL failed ==="
echo "passed=$PASS" > tests/results/summary.txt
echo "failed=$FAIL" >> tests/results/summary.txt

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
