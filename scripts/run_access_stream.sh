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
: "${CHECKPOINT_DIR:=file:///tmp/spark-checkpoints/access_$(date +%s)}"
: "${INFLUX_URL:=http://influxdb:8086}"
: "${INFLUX_ORG:=primary}"
: "${INFLUX_BUCKET:=logs}"
: "${ENV_TAG:=dev}"
: "${ERROR_RATE_THRESHOLD:=0.1}"
: "${IP_SPIKE_THRESHOLD:=50}"
: "${SCAN_DISTINCT_PATHS_THRESHOLD:=20}"
: "${SPARK_EXECUTOR_CORES:=1}"
: "${SPARK_CORES_MAX:=1}"
: "${SPARK_EXECUTOR_MEMORY:=512m}"
: "${SPARK_DRIVER_MEMORY:=512m}"
: "${SPARK_MEM_OVERHEAD:=128m}"

docker exec -e KAFKA_BOOTSTRAP_SERVERS -e KAFKA_TOPIC_ACCESS \
  -e WINDOW_DURATION -e WATERMARK -e CHECKPOINT_DIR \
  -e INFLUX_URL -e INFLUX_TOKEN -e INFLUX_ORG -e INFLUX_BUCKET \
  -e ENV_TAG -e ERROR_RATE_THRESHOLD -e IP_SPIKE_THRESHOLD -e SCAN_DISTINCT_PATHS_THRESHOLD \
  -e SPARK_EXECUTOR_CORES -e SPARK_CORES_MAX -e SPARK_EXECUTOR_MEMORY -e SPARK_DRIVER_MEMORY -e SPARK_MEM_OVERHEAD \
  -it spark-master bash -lc '
    /opt/bitnami/spark/bin/spark-submit \
      --master spark://spark-master:7077 \
      --conf spark.executor.cores=${SPARK_EXECUTOR_CORES} \
      --conf spark.cores.max=${SPARK_CORES_MAX} \
      --executor-memory ${SPARK_EXECUTOR_MEMORY} \
      --driver-memory ${SPARK_DRIVER_MEMORY} \
      --conf spark.executor.memoryOverhead=${SPARK_MEM_OVERHEAD} \
      /opt/spark/app/src/python/stream_access.py
  '

