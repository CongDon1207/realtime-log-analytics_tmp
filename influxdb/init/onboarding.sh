#!/usr/bin/env bash
# onboarding.sh — Init/verify InfluxDB: org & bucket (idempotent)
set -euo pipefail

# --- Locate & load env ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env.influx"
[[ -f "$ENV_FILE" ]] || { echo "[err] Missing $ENV_FILE"; exit 1; }
# shellcheck disable=SC1091
source "$ENV_FILE"

# --- Derive URL if missing ---
INFLUX_HOST="${INFLUX_HOST:-localhost}"
HOST_HTTP_PORT="${HOST_HTTP_PORT:-8086}"
INFLUX_URL="${INFLUX_URL:-http://${INFLUX_HOST}:${HOST_HTTP_PORT}}"

# --- Require variables ---
: "${INFLUX_URL:?missing INFLUX_URL}"
: "${ORG_NAME:?missing ORG_NAME}"
: "${BUCKET_NAME:?missing BUCKET_NAME}"
: "${RETENTION_HOURS:?missing RETENTION_HOURS}"
: "${ADMIN_USER:?missing ADMIN_USER}"
: "${ADMIN_PASSWORD:?missing ADMIN_PASSWORD}"
: "${ADMIN_TOKEN:?missing ADMIN_TOKEN}"

RETENTION_SECONDS=$(( RETENTION_HOURS * 3600 ))

say() { printf '%s\n' "$*"; }
die() { printf '%s\n' "$*" >&2; exit 1; }

# --- Health check ---
say "[onboarding] Health check @ ${INFLUX_URL} ..."
curl -fsS "${INFLUX_URL}/health" | grep -q '"status":"pass"' || die "[err] InfluxDB not ready"

# --- Initial setup (safe, idempotent) ---
say "[setup] POST /api/v2/setup (idempotent)"
SETUP_CODE="$(curl -s -o /tmp/setup.out -w '%{http_code}' \
  -X POST "${INFLUX_URL}/api/v2/setup" \
  -H "Content-Type: application/json" \
  -d "{\"org\":\"${ORG_NAME}\",\"bucket\":\"${BUCKET_NAME}\",\"retentionPeriodSeconds\":${RETENTION_SECONDS},\"username\":\"${ADMIN_USER}\",\"password\":\"${ADMIN_PASSWORD}\",\"token\":\"${ADMIN_TOKEN}\"}")" || true

case "$SETUP_CODE" in
  200|201) say "[setup] OK (initialized)";;
  422)     say "[setup] Already initialized (OK)";;
  *)       cat /tmp/setup.out; die "[err] setup HTTP $SETUP_CODE";;
esac
rm -f /tmp/setup.out || true

# --- Verify token ---
say "[verify] Token → /api/v2/me"
curl -fsS "${INFLUX_URL}/api/v2/me" -H "Authorization: Token ${ADMIN_TOKEN}" >/dev/null \
  || die "[err] Token unauthorized. Use the token from UI → API Tokens."

# --- Verify org & get orgID ---
say "[verify] Org → ${ORG_NAME}"
ORG_JSON="$(curl -fsS "${INFLUX_URL}/api/v2/orgs?org=${ORG_NAME}" -H "Authorization: Token ${ADMIN_TOKEN}")"
echo "$ORG_JSON" | grep -q "\"name\":\"${ORG_NAME}\"" || die "[err] Org not found: ${ORG_NAME}"

if command -v jq >/dev/null 2>&1; then
  ORG_ID="$(echo "$ORG_JSON" | jq -r '.orgs[0].id // empty')"
else
  # Fallback không cần jq: lấy id đầu tiên trong trả về
  ORG_ID="$(echo "$ORG_JSON" | tr -d '\n' | grep -o '"id":"[^"]*"' | head -n1 | cut -d':' -f2 | tr -d '"')"
fi
[[ -n "${ORG_ID:-}" ]] || die "[err] Cannot extract orgID"

say "[verify] orgID=${ORG_ID}"

# --- Verify bucket; create if missing ---
say "[verify] Bucket → ${BUCKET_NAME}"
if curl -fsS -H "Authorization: Token ${ADMIN_TOKEN}" \
   "${INFLUX_URL}/api/v2/buckets?name=${BUCKET_NAME}&org=${ORG_NAME}" \
   | grep -q "\"name\":\"${BUCKET_NAME}\""; then
  say "[verify] bucket OK: ${BUCKET_NAME}"
else
  say "[create] Creating bucket: ${BUCKET_NAME} (retention ${RETENTION_SECONDS}s)"
  CREATE_CODE="$(curl -s -o /tmp/bucket.out -w '%{http_code}' \
    -X POST "${INFLUX_URL}/api/v2/buckets" \
    -H "Authorization: Token ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
          \"orgID\":\"${ORG_ID}\",
          \"name\":\"${BUCKET_NAME}\",
          \"retentionRules\":[{\"type\":\"expire\",\"everySeconds\":${RETENTION_SECONDS}}]
        }")" || true
  case "$CREATE_CODE" in
    200|201) say "[create] bucket created: ${BUCKET_NAME}";;
    *)       cat /tmp/bucket.out; die "[err] create bucket HTTP $CREATE_CODE";;
  esac
  rm -f /tmp/bucket.out || true
fi

say "[done] Influx ready: org=${ORG_NAME} (id=${ORG_ID}), bucket=${BUCKET_NAME}"
