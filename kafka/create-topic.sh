#!/bin/bash
set -e

BOOTSTRAP="localhost:9092"


# Danh sách topic muốn tạo: topic_name:partitions:replication_factor
TOPICS=(
  "web-logs:3:1"
  "web-errors:3:1"
  # Thêm topic khác ở đây
)

# Hàm tạo topic
create_topic() {
    local TOPIC_NAME=$1
    local PARTITIONS=$2
    local REPLICATION=$3

    # Kiểm tra topic đã tồn tại chưa
    if docker exec kafka /opt/bitnami/kafka/bin/kafka-topics.sh \
         --bootstrap-server $BOOTSTRAP --list | grep -q "^$TOPIC_NAME$"; then
        echo "[Kafka] ⚠️ Topic '$TOPIC_NAME' đã tồn tại, bỏ qua"
        return
    fi

    echo "[Kafka] 🛠 Creating topic '$TOPIC_NAME' (partitions=$PARTITIONS, replication=$REPLICATION)"
    docker exec kafka /opt/bitnami/kafka/bin/kafka-topics.sh \
        --bootstrap-server $BOOTSTRAP \
        --create \
        --topic "$TOPIC_NAME" \
        --partitions "$PARTITIONS" \
        --replication-factor "$REPLICATION"

    echo "[Kafka] 🎉 Topic '$TOPIC_NAME' created successfully"
}

# Tạo tất cả topic
for t in "${TOPICS[@]}"; do
    IFS=":" read -r name partitions replication <<< "$t"
    create_topic "$name" "$partitions" "$replication"
done
