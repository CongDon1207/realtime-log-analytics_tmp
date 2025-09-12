#!/bin/bash
set -euo pipefail

# This script runs on the HOST and manages topics via docker exec into the Kafka container.
# Requirements: Docker is running, container name defaults to "kafka" from compose.

KAFKA_CONTAINER="${KAFKA_CONTAINER:-kafka}"
# Address used INSIDE the container when calling kafka-topics.sh
IN_CONTAINER_BROKER="${IN_CONTAINER_BROKER:-kafka:9092}"

# Default topics to recreate; customize by exporting TOPICS env as space-separated list if needed
TOPICS_ENV=${TOPICS:-}
if [ -n "$TOPICS_ENV" ]; then
  # shellcheck disable=SC2206
  TOPICS=( ${TOPICS_ENV} )
else
  TOPICS=("web-logs" "web-errors")
fi

log() { echo "[Host Kafka Admin] $*"; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Error: '$1' is required." >&2; exit 1; }
}

need_cmd docker

# Ensure container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${KAFKA_CONTAINER}$"; then
  log "Kafka container '${KAFKA_CONTAINER}' is not running. Start your compose stack first."
  exit 1
fi

# Helper to exec commands in the kafka container
docker_kafka_exec() {
  docker exec -i "$KAFKA_CONTAINER" bash -lc "$*"
}

log "🚀 Waiting for Kafka container health..."
HEALTH="unknown"
if docker inspect "$KAFKA_CONTAINER" >/dev/null 2>&1; then
  for _ in {1..60}; do
    HEALTH=$(docker inspect -f '{{.State.Health.Status}}' "$KAFKA_CONTAINER" 2>/dev/null || echo "unknown")
    [ "$HEALTH" = "healthy" ] && break
    sleep 2
  done
fi

log "⏳ Waiting for broker port inside container (kafka:9092) to be ready..."
until docker_kafka_exec "nc -z kafka 9092" >/dev/null 2>&1; do
  sleep 1
done

for TOPIC in "${TOPICS[@]}"; do
  log "🔍 Checking if topic '$TOPIC' exists before delete…"
  if docker_kafka_exec \
       "/opt/bitnami/kafka/bin/kafka-topics.sh --bootstrap-server ${IN_CONTAINER_BROKER} --list" | grep -q "^$TOPIC$"; then
    log "🗑️ Deleting topic: $TOPIC"
    docker_kafka_exec \
      "/opt/bitnami/kafka/bin/kafka-topics.sh --bootstrap-server ${IN_CONTAINER_BROKER} --delete --topic '$TOPIC'"
  else
    log "⏭️ Topic '$TOPIC' not found, skipping delete"
  fi

  log "🆕 Creating topic: $TOPIC"
  docker_kafka_exec \
    "/opt/bitnami/kafka/bin/kafka-topics.sh --bootstrap-server ${IN_CONTAINER_BROKER} --create --replication-factor 1 --partitions 1 --topic '$TOPIC'"

  log "✅ Topic '$TOPIC' recreated clean."
done
