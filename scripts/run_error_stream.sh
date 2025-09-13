#!/usr/bin/env bash
set -euo pipefail

RESET_CHECKPOINT=false

# Parse args
for arg in "$@"; do
  case $arg in
    --reset-checkpoint)
      RESET_CHECKPOINT=true
      shift
      ;;
    *)
      ;;
  esac
done

# Load .env if present
if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

# Các biến môi trường mặc định (override nếu có .env)
: "${KAFKA_BOOTSTRAP_SERVERS:=kafka:9092}"
: "${KAFKA_TOPIC_ERROR:=web-errors}"     # topic chứa error log
: "${WINDOW_DURATION:=10 seconds}"
: "${WATERMARK:=2 minutes}"
: "${CHECKPOINT_DIR_ERROR:=/tmp/spark-checkpoints-error}"
: "${INFLUX_URL:=http://influxdb:8086}"
: "${INFLUX_ORG:=primary}"
: "${INFLUX_BUCKET:=logs}"
: "${ENV_TAG:=dev}"

# Tùy chọn: số mẫu error log ghi vào Influx (để soi nhanh)
: "${ERROR_SAMPLE_LIMIT:=5}"

if [ "$RESET_CHECKPOINT" = true ]; then
  echo "🧹 Clearing old Spark checkpoints..."
  docker exec spark-master rm -rf /tmp/spark-checkpoints-error || true
  docker exec spark-worker rm -rf /tmp/spark-checkpoints-error || true
fi

docker exec \
  -e KAFKA_BOOTSTRAP_SERVERS \
  -e KAFKA_TOPIC_ERROR \
  -e WINDOW_DURATION \
  -e WATERMARK \
  -e CHECKPOINT_DIR_ERROR \
  -e INFLUX_URL \
  -e INFLUX_TOKEN \
  -e INFLUX_ORG \
  -e INFLUX_BUCKET \
  -e ENV_TAG \
  -e ERROR_SAMPLE_LIMIT \
  -it spark-master bash -lc '
    /opt/bitnami/spark/bin/spark-submit \
      --master spark://spark-master:7077 \
      /opt/spark/app/src/python/stream_error.py
  '
