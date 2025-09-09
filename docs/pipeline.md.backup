# H����>ng d���n Pipeline: Nginx �+' Flume �+' Kafka

## T��ng quan
Pipeline nA�y thu th��-p logs t��� cA�c web servers ### Kiểm tra logs Flume:
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
# Liệt kê topics��ng Apache Flume �`��� stream d��_ li���u, vA� �`��a vA�o Apache Kafka �`��� l��u tr��_ vA� x��- lA�.

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

## CA�c b����>c kh��Yi ch���y Pipeline

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
# Lệnh netstat không khả dụng trong container hiện tại
# Thay vào đó kiểm tra logs để xác nhận
docker logs flume-collector | grep -i "started\|listening\|bind"
```

### Kiểm tra các Nginx container có thể tạo logs:
```bash
docker exec web1 sh -c "tail -5 /var/log/nginx/access.json.log"
docker exec web2 sh -c "tail -5 /var/log/nginx/access.json.log"  
docker exec web3 sh -c "tail -5 /var/log/nginx/access.json.log"

# Kiểm tra error logs
docker exec web1 sh -c "tail -5 /var/log/nginx/error.log"
docker exec web2 sh -c "tail -5 /var/log/nginx/error.log"
docker exec web3 sh -c "tail -5 /var/log/nginx/error.log"
```

### Ki���m tra logs Flume:
```bash
# Logs c��a collector
docker logs flume-collector

# Logs c��a agents
docker logs flume-agent-web1
docker logs flume-agent-web2  
docker logs flume-agent-web3
```

### Ki���m tra Kafka topics:
```bash
# Li���t kA� topics
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
- ✓ Nginx tạo access/error logs
- ✓ Flume agents đọc logs từ files
- ✓ Flume collector nhận data từ agents  
- ✓ Data được gửi vào Kafka topics
- ✓ Consumer có thể đọc real-time data từ Kafka

---

## Spark Structured Streaming (access → metrics/anomaly → InfluxDB)

### Khởi chạy Spark cluster
```bash
make up-spark
```

### Chạy job Streaming (đọc Kafka → chuẩn hóa → cửa sổ 10s/2m → ghi InfluxDB)
```bash
# 1) Tạo file .env từ mẫu và điền INFLUX_TOKEN (nếu dùng auth)
cp -n .env.sample .env || true

# 2) Chạy job
make run-stream-access
```

### Output và measurements InfluxDB
- `http_stats` (tags: `env, hostname, method`; fields: `count, rps, avg_rt, max_rt, err_rate`; time = `window_end`).
- `top_urls` (tags: `env, hostname, status, path`; field: `count`; time = `window_end`).
- `anomaly` (tags: `env, hostname, kind`; fields: `ip, count, score`; time = `window_end`).

Gợi ý truy vấn Top-N (lọc ở Grafana/Flux): sắp xếp `count` giảm dần, `limit N` theo mỗi `window_end`.

### Kiểm tra nhanh
- Kiểm tra logs Spark: `docker logs -f spark-master`
- Kiểm tra Influx write: truy cập InfluxDB UI hoặc dùng Flux script `influxdb/verify.flux` (nếu có).

### Ghi chú performance
- Ảnh Spark đã được “prefetch” gói Kafka (`spark-sql-kafka-0-10`) trong lúc build để giảm thời gian `spark-submit` lần đầu.
- `spark.jars.packages` được khai báo trong `spark/conf/spark-defaults.conf`, nên không cần truyền `--packages` khi chạy.

### Ghi chú thiết kế
- `err_rate` được tính trên tổng request mỗi (hostname, method) theo từng cửa sổ để tránh join phức tạp giữa các lớp status.
- Top-N URL được tính sẵn theo (hostname, status, path); phần chọn Top-N thực hiện ở lớp hiển thị để tối giản xử lý stateful.
