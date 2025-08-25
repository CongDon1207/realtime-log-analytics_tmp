#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../.env.influx"

INFLUX_URL="http://localhost:8086"   # xem ghi chú port bên Compose

echo "[onboarding] Health check InfluxDB..."
curl -fsS "${INFLUX_URL}/health" | grep -q '"status":"pass"' || {
  echo "[onboarding] InfluxDB chưa sẵn sàng"; exit 1;
}

echo "[onboarding] POST /api/v2/setup (idempotent; không log token)"
code="$(curl -s -o /tmp/setup.out -w '%{http_code}' -X POST "${INFLUX_URL}/api/v2/setup" \
  -H "Content-Type: application/json" \
  -d "{\"org\":\"${ORG_NAME}\",\"bucket\":\"${BUCKET_NAME}\",\"retentionPeriodHours\":${RETENTION_HOURS},\"username\":\"${ADMIN_USER}\",\"password\":\"${ADMIN_PASSWORD}\",\"token\":\"${ADMIN_TOKEN}\"}")" || true

if [[ "$code" == "201" || "$code" == "200" ]]; then
  echo "[onboarding] setup OK [Chưa xác minh]"
elif [[ "$code" == "422" ]]; then
  echo "[onboarding] already set up (idempotent) [Chưa xác minh]"
else
  echo "[onboarding] setup HTTP $code [Chưa xác minh]"
fi
