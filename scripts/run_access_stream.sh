#!/usr/bin/env bash
set -euo pipefail

# Load .env if present
if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

: "${KAFKA_BOOTSTRAP_SERVERS:=kafka:9092}"
: "${KAFKA_TOPIC_ACCESS:=web-logs}"
: "${WINDOW_DURATION:=10 seconds}"
: "${WATERMARK:=2 minutes}"
: "${CHECKPOINT_DIR:=/tmp/checkpoints}"
: "${INFLUX_URL:=http://influxdb:8086}"
: "${INFLUX_ORG:=primary}"
: "${INFLUX_BUCKET:=logs}"
: "${ENV_TAG:=dev}"
: "${ERROR_RATE_THRESHOLD:=0.1}"
: "${IP_SPIKE_THRESHOLD:=50}"
: "${SCAN_DISTINCT_PATHS_THRESHOLD:=20}"

docker exec -e KAFKA_BOOTSTRAP_SERVERS -e KAFKA_TOPIC_ACCESS \
  -e WINDOW_DURATION -e WATERMARK -e CHECKPOINT_DIR \
  -e INFLUX_URL -e INFLUX_TOKEN -e INFLUX_ORG -e INFLUX_BUCKET \
  -e ENV_TAG -e ERROR_RATE_THRESHOLD -e IP_SPIKE_THRESHOLD -e SCAN_DISTINCT_PATHS_THRESHOLD \
  -it spark-master bash -lc '
    /opt/bitnami/spark/bin/spark-submit \
      --master spark://spark-master:7077 \
      /opt/spark/app/src/python/stream_access.py
  '

