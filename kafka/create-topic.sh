#!/bin/bash
set -e

echo "[bitnamilegacy  Kafka] 🚀 Waiting for broker to be ready..."
while ! nc -z kafka 9092; do
  sleep 1
done

TOPICS=("web-logs" "web-errors")

for TOPIC in "${TOPICS[@]}"; do
  echo "[bitnamilegacy  Kafka] 🔍 Checking if topic '$TOPIC' exists before delete…"
  if /opt/bitnamilegacy /kafka/bin/kafka-topics.sh \
       --bootstrap-server kafka:9092 \
       --list | grep -q "^$TOPIC$"; then
    echo "[bitnamilegacy  Kafka] 🗑️ Deleting topic: $TOPIC"
    /opt/bitnamilegacy /kafka/bin/kafka-topics.sh \
      --bootstrap-server kafka:9092 \
      --delete \
      --topic "$TOPIC"
  else
    echo "[bitnamilegacy  Kafka] ⏭️ Topic '$TOPIC' not found, skipping delete"
  fi

  echo "[bitnamilegacy  Kafka] 🆕 Creating topic: $TOPIC"
  /opt/bitnamilegacy /kafka/bin/kafka-topics.sh \
    --bootstrap-server kafka:9092 \
    --create \
    --replication-factor 1 \
    --partitions 1 \
    --topic "$TOPIC"

  echo "[bitnamilegacy  Kafka] ✅ Topic '$TOPIC' recreated clean."
done
