# Hướng dẫn Pipeline: Nginx → Flume → Kafka

## Tổng quan
Pipeline này thu thập logs từ các web servers Nginx, sử dụng Apache Flume để stream dữ liệu, và đưa vào Apache Kafka để lưu trữ và xử lý.

## Luồng dữ liệu
```
Nginx Servers (web1, web2, web3) 
    ↓ (Log files: access.json.log, error.log)
Flume Agents (taildir source) 
    ↓ (Avro sink → port 41414)
Flume Collector (multiplexing selector)
    ↓ (Kafka producer)
Kafka Topics (web-logs, web-errors)
```

## Các bước khởi chạy Pipeline

### 1. Khởi động Kafka
```bash
# Khởi động Kafka service
docker-compose -f docker-compose.hao.yml up -d

# Kiểm tra Kafka đã running
docker-compose -f docker-compose.hao.yml ps
```

### 2. Tạo Topics Kafka
```bash
# Tạo topic cho access logs
docker exec -it kafka bash -c "/opt/bitnami/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --create --topic web-logs --partitions 3 --replication-factor 1"

# Tạo topic cho error logs  
docker exec -it kafka bash -c "/opt/bitnami/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --create --topic web-errors --partitions 3 --replication-factor 1"

# Xem danh sách topics
docker exec -it kafka bash -c "/opt/bitnami/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --list"
```

### 3. Khởi động Nginx Servers
```bash
# Khởi động 3 web servers (web1, web2, web3)
docker-compose -f docker-compose.nginx.yml up -d

# Kiểm tra services
docker-compose -f docker-compose.nginx.yml ps
```

### 4. Khởi động Flume Services
```bash
# Khởi động Flume collector và agents
docker-compose -f docker-compose.flume.yml up -d

# Kiểm tra Flume services
docker-compose -f docker-compose.flume.yml ps
```

## Test Pipeline

### 1. Generate Access Logs
```bash
# Tạo 10 requests thành công đến /api endpoint
for i in {1..10}; do curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8081/api; done
```

### 2. Generate Error Logs  
```bash
# Tạo 5 requests lỗi đến /oops endpoint
for i in {1..5}; do curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8081/oops; done
```

### 3. Kiểm tra Consumer

#### Consumer cho Access Logs (web-logs topic):
```bash
docker exec -it kafka bash -c "/opt/bitnami/kafka/bin/kafka-console-consumer.sh --bootstrap-server kafka:9092 --topic web-logs --from-beginning"
```

#### Consumer cho Error Logs (web-errors topic):
```bash
docker exec -it kafka bash -c "/opt/bitnami/kafka/bin/kafka-console-consumer.sh --bootstrap-server kafka:9092 --topic web-errors --from-beginning"
```

## Cấu trúc dữ liệu

### Access Logs (JSON format):
```json
{
  "time": "2025-09-09T02:43:12+00:00",
  "ts": 1757385792.958,
  "remote": "172.22.0.1", 
  "hostname": "5062a08432a6",
  "method": "GET",
  "path": "/api",
  "status": 502,
  "bytes": 157,
  "rt": 0.001
}
```

### Error Logs (Plain text format):
```
2025/09/09 02:43:12 [error] 33#33: *276 connect() failed (111: Connection refused) while connecting to upstream, client: 172.22.0.1, server: , request: "GET /api HTTP/1.1", upstream: "http://127.0.0.1:65535/api", host: "localhost:8081"
```

## Kiểm tra trạng thái

### Kiểm tra Flume Collector đang lắng nghe:
```bash
docker exec -it flume-collector sh -c "netstat -tuln | grep 41414"
```

### Kiểm tra logs Flume:
```bash
# Logs của collector
docker logs flume-collector

# Logs của agents
docker logs flume-agent-web1
docker logs flume-agent-web2  
docker logs flume-agent-web3
```

### Kiểm tra Kafka topics:
```bash
# Liệt kê topics
docker exec -it kafka bash -c "/opt/bitnami/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --list"

# Xem thông tin chi tiết topic
docker exec -it kafka bash -c "/opt/bitnami/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --describe --topic web-logs"
```

## Troubleshooting

### Lỗi thường gặp:

1. **Network không tồn tại**: 
   ```bash
   docker network create appnet
   ```

2. **Topic đã tồn tại**:
   - Lỗi này không ảnh hưởng, topic vẫn sử dụng được bình thường

3. **Consumer không nhận được data**:
   - Kiểm tra Flume services đang chạy: `docker-compose -f docker-compose.flume.yml ps`
   - Kiểm tra Kafka service: `docker-compose -f docker-compose.hao.yml ps`  
   - Generate thêm test data bằng curl

4. **502 Bad Gateway khi test**:
   - Đây là lỗi mong muốn để test error logs
   - Nginx proxy đến backend không tồn tại (port 65535)

## Kết luận
Pipeline hoạt động thành công với luồng:
- ✅ Nginx tạo access/error logs
- ✅ Flume agents đọc logs từ files
- ✅ Flume collector nhận data từ agents  
- ✅ Data được gửi vào Kafka topics
- ✅ Consumer có thể đọc real-time data từ Kafka
