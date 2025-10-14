FROM bitnamilegacy/kafka:3.5.1

USER root

# Cài thêm tool nếu cần
RUN install_packages curl jq netcat-openbsd

# Copy script tạo topic
COPY create-topic.sh /opt/bitnami/kafka/create-topic.sh
RUN sed -i 's/\r$//' /opt/bitnami/kafka/create-topic.sh

# Chown và chmod tại build-time
RUN chown 1001:1001 /opt/bitnami/kafka/create-topic.sh \
    && chmod +x /opt/bitnami/kafka/create-topic.sh

# Thêm user kafkauser
RUN echo "kafkauser:x:1001:0:Kafka User:/opt/bitnami/kafka:/bin/bash" >> /etc/passwd

# Chuyển sang kafkauser
USER 1001
WORKDIR /opt/bitnami/kafka
