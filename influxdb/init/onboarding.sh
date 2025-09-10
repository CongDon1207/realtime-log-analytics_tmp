#!/usr/bin/env bash
# onboarding.sh — Khởi tạo/kiểm tra InfluxDB: org & bucket (idempotent)
# Chạy tốt trên Git Bash/WSL/Linux.
# Tác vụ chính:
#   1) Health-check InfluxDB
#   2) /api/v2/setup (an toàn, nếu đã init sẽ trả 422)
#   3) Verify token (/api/v2/me)
#   4) Lấy ORG_ID theo ORG_NAME (jq → python → sed fallback)
#   5) Verify bucket theo org; nếu thiếu → tạo bucket với retention

set -euo pipefail

############################################
# 0) Định vị & nạp file .env (ưu tiên root .env, fallback .env.influx)
############################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_ENV="${SCRIPT_DIR}/../../.env"
LOCAL_ENV="${SCRIPT_DIR}/../.env.influx"

if [[ -f "$ROOT_ENV" ]]; then
  echo "[info] Using root .env file: $ROOT_ENV"
  # shellcheck disable=SC1091
  source "$ROOT_ENV"
  # Map root .env variables to expected names
  ADMIN_TOKEN="${INFLUX_TOKEN:-}"
  ORG_NAME="${INFLUX_ORG:-primary}"
  BUCKET_NAME="${INFLUX_BUCKET:-logs}"
elif [[ -f "$LOCAL_ENV" ]]; then
  echo "[info] Using local .env.influx file: $LOCAL_ENV"
  # shellcheck disable=SC1091
  source "$LOCAL_ENV"
else
  echo "[err] Thiếu cả 2 file env: $ROOT_ENV hoặc $LOCAL_ENV"
  exit 1
fi

############################################
# 1) Hàm tiện ích & làm sạch biến môi trường
############################################

# In thông báo thường
say() { printf '%s\n' "$*"; }
# In lỗi và thoát
die() { printf '%s\n' "$*" >&2; exit 1; }

# Loại bỏ CR (Windows \r) và khoảng trắng ở cuối — tránh lỗi khi build URL/query
clean() { printf '%s' "$1" | tr -d '\r' | sed 's/[[:space:]]\+$//'; }

# Làm sạch và gán mặc định nếu trống
# Kiểm tra xem có chạy từ trong container không
if [[ -f "/.dockerenv" ]]; then
  # Chạy từ trong container → dùng service name
  INFLUX_HOST="$(clean "${INFLUX_HOST:-influxdb}")"
else
  # Chạy từ host machine → dùng localhost
  INFLUX_HOST="$(clean "${INFLUX_HOST:-localhost}")"
fi
HOST_HTTP_PORT="$(clean "${HOST_HTTP_PORT:-8086}")"
# Override INFLUX_URL nếu detect chạy từ host hoặc trong container
if [[ -f "/.dockerenv" ]]; then
  # Chạy từ trong container → có thể dùng INFLUX_URL từ .env
  INFLUX_URL="$(clean "${INFLUX_URL:-http://${INFLUX_HOST}:${HOST_HTTP_PORT}}")"
else
  # Chạy từ host machine → force dùng localhost
  INFLUX_URL="http://localhost:${HOST_HTTP_PORT}"
fi

ORG_NAME="$(clean "${ORG_NAME:-}")"
BUCKET_NAME="$(clean "${BUCKET_NAME:-}")"
RETENTION_HOURS="$(clean "${RETENTION_HOURS:-}")"
ADMIN_USER="$(clean "${ADMIN_USER:-}")"
ADMIN_PASSWORD="$(clean "${ADMIN_PASSWORD:-}")"
ADMIN_TOKEN="$(clean "${ADMIN_TOKEN:-}")"

# Kiểm tra biến bắt buộc
: "${INFLUX_URL:?missing INFLUX_URL}"
: "${ORG_NAME:?missing ORG_NAME}"
: "${BUCKET_NAME:?missing BUCKET_NAME}"
: "${RETENTION_HOURS:?missing RETENTION_HOURS}"
: "${ADMIN_USER:?missing ADMIN_USER}"
: "${ADMIN_PASSWORD:?missing ADMIN_PASSWORD}"
: "${ADMIN_TOKEN:?missing ADMIN_TOKEN}"

RETENTION_SECONDS=$(( RETENTION_HOURS * 3600 ))

############################################
# 2) Health check InfluxDB
############################################
say "[onboarding] Health check @ ${INFLUX_URL} ..."
curl -fsS "${INFLUX_URL}/health" | grep -q '"status":"pass"' || die "[err] InfluxDB chưa sẵn sàng"

############################################
# 3) Gọi /api/v2/setup (idempotent)
#    - Lần đầu: tạo org, bucket, user, và đặt admin token
#    - Đã setup: trả 422 → coi như OK
############################################
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

############################################
# 4) Verify token có hiệu lực
############################################
say "[verify] Token → /api/v2/me"
curl -fsS "${INFLUX_URL}/api/v2/me" -H "Authorization: Token ${ADMIN_TOKEN}" >/dev/null \
  || die "[err] Token không hợp lệ. Vào UI → Load Data → API Tokens để copy token đúng."

############################################
# 5) Lấy ORG_ID theo ORG_NAME (thuần shell, không cần jq/python)
############################################
say "[verify] Org → ${ORG_NAME}"

# Gọi API lọc theo tên org để giảm ồn (KHÔNG dùng -f để tránh im lặng)
ORG_JSON="$(curl -sS "${INFLUX_URL}/api/v2/orgs?org=${ORG_NAME}" \
  -H "Authorization: Token ${ADMIN_TOKEN}")" || die "[err] curl /orgs lỗi"

# Phòng hờ: nếu rỗng thì báo lỗi rõ ràng
[ -n "$ORG_JSON" ] || die "[err] /api/v2/orgs trả rỗng. Kiểm tra lại ADMIN_TOKEN/INFLUX_URL."

# Trích ORG_ID bằng sed (chấp nhận khoảng trắng)
# Influx thường trả [{"id":"...","name":"demo-org",...}]
ORG_ID="$(printf '%s' "$ORG_JSON" \
  | tr -d '\n' \
  | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"

# Nếu vì layout khác không bắt được, thử fallback: gọi /orgs (không filter) rồi match name→id
if [ -z "$ORG_ID" ]; then
  ORG_ALL="$(curl -sS "${INFLUX_URL}/api/v2/orgs" -H "Authorization: Token ${ADMIN_TOKEN}")" \
    || die "[err] curl /orgs (all) lỗi"
  ORG_ID="$(printf '%s' "$ORG_ALL" \
    | tr -d '\n' \
    | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*"name"[[:space:]]*:[[:space:]]*"'$ORG_NAME'".*/\1/p')"
fi

[ -n "$ORG_ID" ] || { echo "[err] Không trích được ORG_ID cho ${ORG_NAME}"; echo "$ORG_JSON"; exit 1; }
say "[verify] orgID=${ORG_ID}"


############################################
# 6) Verify bucket theo org; nếu thiếu → tạo
############################################
say "[verify] Bucket → ${BUCKET_NAME}"
if curl -fsS -H "Authorization: Token ${ADMIN_TOKEN}" \
   "${INFLUX_URL}/api/v2/buckets?name=${BUCKET_NAME}&org=${ORG_NAME}" \
   | grep -q '"name"[[:space:]]*:[[:space:]]*"'${BUCKET_NAME}'"'; then
  say "[verify] bucket OK: ${BUCKET_NAME}"
else
  say "[create] Tạo bucket: ${BUCKET_NAME} (retention ${RETENTION_SECONDS}s)"
  # Dùng heredoc để tránh lỗi quote trên Git Bash
  cat > /tmp/bucket.payload.json <<JSON
{
  "orgID": "${ORG_ID}",
  "name": "${BUCKET_NAME}",
  "retentionRules": [
    { "type": "expire", "everySeconds": ${RETENTION_SECONDS} }
  ]
}
JSON

  CREATE_CODE="$(curl -s -o /tmp/bucket.out -w '%{http_code}' \
    -X POST "${INFLUX_URL}/api/v2/buckets" \
    -H "Authorization: Token ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d @/tmp/bucket.payload.json)" || true

  case "$CREATE_CODE" in
    200|201) say "[create] Bucket created: ${BUCKET_NAME}";;
    409)     say "[create] Bucket đã tồn tại (409) — có thể tên trùng, khác org";;
    401|403) cat /tmp/bucket.out 1>&2 || true; rm -f /tmp/bucket.out /tmp/bucket.payload.json || true; die "[err] Token không đủ quyền tạo bucket trong org ${ORG_NAME}.";;
    *)       cat /tmp/bucket.out 1>&2 || true; rm -f /tmp/bucket.out /tmp/bucket.payload.json || true; die "[err] Tạo bucket lỗi HTTP $CREATE_CODE";;
  esac

  rm -f /tmp/bucket.out /tmp/bucket.payload.json || true
fi

############################################
# 7) Hoàn tất
############################################
say "[done] Influx ready: org=${ORG_NAME} (id=${ORG_ID}), bucket=${BUCKET_NAME}"
