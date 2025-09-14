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
: "${CHECKPOINT_DIR_ERROR:=file:///tmp/spark-checkpoints-error}"
: "${INFLUX_URL:=http://influxdb:8086}"
: "${INFLUX_ORG:=primary}"
: "${INFLUX_BUCKET:=logs}"
: "${ENV_TAG:=dev}"

# Tùy chọn: số mẫu error log ghi vào Influx (để soi nhanh)
: "${ERROR_SAMPLE_LIMIT:=5}"

# Spark Resource Configuration
: "${SPARK_EXECUTOR_CORES:=1}"
: "${SPARK_CORES_MAX:=1}"
: "${SPARK_EXECUTOR_MEMORY:=512m}"
: "${SPARK_DRIVER_MEMORY:=512m}"
: "${SPARK_MEM_OVERHEAD:=128m}"

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
  -e SPARK_EXECUTOR_CORES -e SPARK_CORES_MAX -e SPARK_EXECUTOR_MEMORY -e SPARK_DRIVER_MEMORY -e SPARK_MEM_OVERHEAD \
  -it spark-master bash -lc '
    /opt/bitnami/spark/bin/spark-submit \
      --master spark://spark-master:7077 \
      --conf spark.executor.cores=${SPARK_EXECUTOR_CORES} \
      --conf spark.cores.max=${SPARK_CORES_MAX} \
      --executor-memory ${SPARK_EXECUTOR_MEMORY} \
      --driver-memory ${SPARK_DRIVER_MEMORY} \
      --conf spark.executor.memoryOverhead=${SPARK_MEM_OVERHEAD} \
      /opt/spark/app/src/python/stream_error.py
  '
