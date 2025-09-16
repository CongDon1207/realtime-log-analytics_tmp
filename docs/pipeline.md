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
   ↓ (Consumed by)
Spark Structured Streaming (access → metrics / anomaly)
   ↓ (Writes metrics)
InfluxDB (bucket: logs — measurements: http_stats, top_urls, anomaly)
```

## Các bước khởi chạy logs đưa vào kafka

### 1. Khởi tạo toàn bộ container
```bash
# Khởi động toàn bộ container
docker compose up -d 

# Kiểm tra Kafka đã running
docker compose ps
```

### 2. Tạo Topics Kafka
```bash
# Tạo (hoặc recreate) các topic bằng script helper có sẵn trong container
# Script sẽ xóa (nếu có) rồi tạo lại `web-logs` và `web-errors` một cách an toàn.
bash kafka/create-topic2.sh

# Xem danh sách topics
docker exec -it kafka bash -c "/opt/bitnami/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --list"

# Xem thông tin chi tiết topic
docker exec -it kafka bash -c "/opt/bitnami/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --describe --topic web-logs"
```

### Lưu ý: chỗ này không cần làm cũng được, do error log đã tự tạo rồi
### 3. Generate Access Logs (Thủ công) 
```bash
# Tạo 10 requests loi đến /api endpoint  
for i in {1..10}; do curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8081/api; done
```

### 4. Generate Error Logs (Thủ công)
```bash
# Tạo 5 requests lỗi đến /oops endpoint
for i in {1..5}; do curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8081/oops; done
```

### 5. Kiểm tra Consumer

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
  "hostname": "web1",
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



## Spark Structured Streaming (access → metrics/anomaly → InfluxDB)

### Bước 1: Khởi động InfluxDB
```bash
# Khởi tạo org/bucket (chỉ chạy 1 lần) - script sẽ đọc cấu hình từ .env
bash influxdb/init/onboarding.sh
```

#### ⚠️ Lưu ý quan trọng cho lần đầu setup InfluxDB:

> **Chỉ thực hiện 1 lần duy nhất** khi khởi tạo InfluxDB lần đầu tiên.

**Các bước thực hiện:**

1. **Truy cập InfluxDB UI**: Mở trình duyệt và vào `http://localhost:8086`

2. **Đăng nhập hệ thống**:
   - Username: `admin`  
   - Password: `admin12345`

![image alt](https://github.com/hungfnguyen/realtime-log-analytics/blob/feat/influxdb-storage/docs/img/influxdb_login.jpg?raw=true)
3. **Tạo API Token mới**:
   - Sau khi đăng nhập, click vào **biểu tượng mũi tên ↗** (Load Data) ở sidebar trái
   - Chọn **API Tokens** từ menu
    ![image alt](https://github.com/hungfnguyen/realtime-log-analytics/blob/feat/influxdb-storage/docs/img/guide_influxdb.png?raw=true)

   - **Xóa token cũ** (nếu có) bằng cách click vào token và chọn Delete
    ![image alt](https://github.com/hungfnguyen/realtime-log-analytics/blob/feat/influxdb-storage/docs/img/delete_api_token.jpg?raw=true)
    
   - Click **Generate API Token** → **All Access API Token**
   - Đặt tên cho token (ví dụ: `spark-streaming-token`)
   - **Copy token** vừa được tạo

4. **Cập nhật file cấu hình**:
   - Mở file `.env` ở thư mục root của project
   - Thay thế giá trị `INFLUX_TOKEN` bằng token vừa copy

   ```bash
   # Ví dụ format trong file .env:
   INFLUX_TOKEN=DHxxYj3F83RYX4vZwj7Ftebb1jpKJnR0ylu96ZGH9BvvQT3hkmPs9V73r6c3uOKpS2fulZ76DlYnmFlL9rFLqQ==
   ```
   ![image alt](https://github.com/hungfnguyen/realtime-log-analytics/blob/feat/influxdb-storage/docs/img/config_env.jpg?raw=true)
    
5. **Kiểm tra kết nối**: 
   ```bash
   source .env && curl -I -H "Authorization: Token $INFLUX_TOKEN" http://localhost:8086/ping
   ```

> 💡 **Ghi chú**: Token này sẽ được sử dụng bởi Spark streaming job để ghi dữ liệu vào InfluxDB. Không chia sẻ token này với người khác.
### Bước 2: Kiểm tra cấu hình InfluxDB
```bash
# Kiểm tra InfluxDB API có sẵn sàng
curl -I http://localhost:8086/ping

# Kiểm tra cấu hình từ file .env
source .env && echo "ORG: $INFLUX_ORG, BUCKET: $INFLUX_BUCKET"

# Kiểm tra cấu hình InfluxDB từ .env
source .env && echo "INFLUX_TOKEN: ${INFLUX_TOKEN:0:20}..."
```

### Bước 3: Chạy Spark Streaming job (access log)
```bash
# Lệnh ngắn gọn (tự nạp .env, chạy 70–75s rồi dừng)
bash scripts/run_access_stream.sh

#Hoặc ép timeout:
set -a; . .env; set +a; docker exec -e INFLUX_URL -e INFLUX_TOKEN -e INFLUX_ORG -e INFLUX_BUCKET -e ENV_TAG -e WINDOW_DURATION -e WATERMARK -e CHECKPOINT_DIR spark-master bash -lc 'timeout 75s /opt/bitnami/spark/bin/spark-submit --master spark://spark-master-influx:7077 /opt/spark/app/src/python/stream_access.py'
```

### Bước 4: Chạy Spark Streaming job (error log)
```bash
# Lệnh ngắn gọn (tự nạp .env, chạy 70–75s rồi dừng)
bash scripts/run_error_stream.sh

#Hoặc ép timeout:
set -a; . .env; set +a; docker exec -e INFLUX_URL -e INFLUX_TOKEN -e INFLUX_ORG -e INFLUX_BUCKET -e ENV_TAG -e WINDOW_DURATION -e WATERMARK -e CHECKPOINT_DIR_ERROR spark-master bash -lc 'timeout 75s /opt/bitnami/spark/bin/spark-submit --master spark://spark-master:7077 /opt/spark/app/src/python/stream_error.py'
```


### Output và Measurements InfluxDB

Pipeline sẽ tạo ra 4 measurements chính trong InfluxDB để phân tích logs và monitoring:

#### 1. `http_stats` - Metrics hiệu năng HTTP theo cửa sổ thời gian
- **Mục đích**: Theo dõi hiệu năng và tình trạng của web servers
- **Tags**: `env` (môi trường), `hostname` (tên server), `method` (HTTP method)
- **Fields**: 
  - `count`: Tổng số requests trong window
  - `rps`: Requests per second
  - `avg_rt`: Response time trung bình (ms)
  - `max_rt`: Response time tối đa (ms)  
  - `err_rate`: Tỷ lệ lỗi (%)
- **Time**: `window_end` (kết thúc cửa sổ 10 giây)

#### 2. `top_urls` - Top URLs được truy cập nhiều nhất
- **Mục đích**: Phân tích traffic patterns và endpoints phổ biến
- **Tags**: `env`, `hostname`, `status` (HTTP status code), `path` (URL path)
- **Fields**: `count` (số lần truy cập)
- **Time**: `window_end`

#### 3. `anomaly` - Phát hiện bất thường trong traffic
- **Mục đích**: Cảnh báo các hành vi bất thường (DDoS, bot attacks, etc.)
- **Tags**: `env`, `hostname`, `kind` (loại bất thường: ip_spike, rate_limit, etc.)
- **Fields**: 
  - `ip`: IP address có hành vi bất thường
  - `count`: Số requests từ IP đó
  - `score`: Điểm bất thường (0-1, càng cao càng nghi ngờ)
- **Time**: `window_end`

#### 4. `error_events` - Thống kê lỗi hệ thống theo cửa sổ thời gian  
- **Mục đích**: Theo dõi và phân loại các lỗi hệ thống
- **Tags**: `env`, `hostname`, `level` (ERROR/WARN/CRIT), `message_class` (db/api/network/etc.)
- **Fields**: `count` (số lượng lỗi trong window)
- **Ghi chú**: `hostname` luôn là `web1`/`web2`/`web3`; nếu log gốc thiếu giá trị sẽ được thay bằng `unknown_host`
- **Time**: `window_end`

### Kiểm tra dữ liệu trong InfluxDB

#### Truy cập InfluxDB UI:
```bash
echo "InfluxDB UI: http://localhost:8086 (Org: primary, Bucket: logs)"
```

#### Query tổng quan tất cả measurements:
```bash
# Xem toàn bộ dữ liệu (giới hạn 10 records)
source .env && docker exec influxdb influx query 'from(bucket: "logs") |> range(start: -1h) |> limit(n: 10)' --org $INFLUX_ORG --token $INFLUX_TOKEN

# Đếm tổng số records trong tất cả measurements
source .env && docker exec influxdb influx query 'from(bucket: "logs") |> range(start: -1h) |> count()' --org $INFLUX_ORG --token $INFLUX_TOKEN
```

#### Query HTTP Performance Metrics (`http_stats`):
```bash
# Xem metrics hiệu năng HTTP với pivot để dễ đọc
source .env && docker exec influxdb influx query 'from(bucket: "logs") |> range(start: -1h) |> filter(fn: (r) => r._measurement == "http_stats") |> pivot(rowKey:["_time","hostname","method"], columnKey: ["_field"], valueColumn: "_value")' --org $INFLUX_ORG --token $INFLUX_TOKEN

# Chỉ xem response time metrics
source .env && docker exec influxdb influx query 'from(bucket: "logs") |> range(start: -1h) |> filter(fn: (r) => r._measurement == "http_stats" and (r._field == "avg_rt" or r._field == "max_rt")) |> pivot(rowKey:["_time","hostname","method"], columnKey: ["_field"], valueColumn: "_value")' --org $INFLUX_ORG --token $INFLUX_TOKEN
```

#### Check phân phối latency (rt) – chẩn đoán nhanh
```bash
source .env && docker exec influxdb influx query '
  a = from(bucket: "logs")
    |> range(start: -30m)
    |> filter(fn: (r) => r._measurement == "http_stats" and r._field == "avg_rt")
    |> quantile(q: 0.95, method: "exact_selector")

  b = from(bucket: "logs")
    |> range(start: -30m)
    |> filter(fn: (r) => r._measurement == "http_stats" and r._field == "max_rt")
    |> quantile(q: 0.95, method: "exact_selector")

  union(tables: {avg_rt_p95: a, max_rt_p95: b})
' --org $INFLUX_ORG --token $INFLUX_TOKEN
```

#### Query Top URLs (`top_urls`):
```bash
# Top URLs được truy cập nhiều nhất
source .env && docker exec influxdb influx query 'from(bucket: "logs") |> range(start: -1h) |> filter(fn: (r) => r._measurement == "top_urls" and r._field == "count") |> group(columns: ["hostname", "path", "status"]) |> sum(column: "_value") |> sort(columns: ["_value"], desc: true) |> limit(n:10)' --org $INFLUX_ORG --token $INFLUX_TOKEN

# URLs có status code lỗi (4xx, 5xx)
source .env && docker exec influxdb influx query 'from(bucket: "logs") |> range(start: -1h) |> filter(fn: (r) => r._measurement == "top_urls" and r._field == "count" and (r.status =~ /^[45]/)) |> group(columns: ["hostname", "path", "status"]) |> sum(column: "_value") |> sort(columns: ["_value"], desc: true) |> limit(n:10)' --org $INFLUX_ORG --token $INFLUX_TOKEN
```

#### Query Anomaly Detection (`anomaly`):
```bash
# Tất cả bất thường được phát hiện
source .env && docker exec influxdb influx query 'from(bucket: "logs") |> range(start: -1h) |> filter(fn: (r) => r._measurement == "anomaly") |> pivot(rowKey:["_time"], columnKey: ["_field"], valueColumn: "_value")' --org $INFLUX_ORG --token $INFLUX_TOKEN

# Chỉ các bất thường có score cao (> 0.7)
source .env && docker exec influxdb influx query 'from(bucket: "logs") |> range(start: -1h) |> filter(fn: (r) => r._measurement == "anomaly" and r._field == "score" and r._value > 0.7)' --org $INFLUX_ORG --token $INFLUX_TOKEN
```

#### Query Error Events (`error_events`):
```bash
# Tất cả lỗi hệ thống với pivot
source .env && docker exec influxdb influx query 'from(bucket: "logs") |> range(start: -1h) |> filter(fn: (r) => r._measurement == "error_events") |> pivot(rowKey:["_time","hostname","level"], columnKey: ["_field"], valueColumn: "_value")' --org $INFLUX_ORG --token $INFLUX_TOKEN

# Chỉ lỗi CRITICAL và ERROR level  
source .env && docker exec influxdb influx query 'from(bucket: "logs") |> range(start: -1h) |> filter(fn: (r) => r._measurement == "error_events" and r.level == "error") |> sort(columns: ["_time"], desc: true)' --org $INFLUX_ORG --token $INFLUX_TOKEN

# Thống kê lỗi theo hostname và level
source .env && docker exec influxdb influx query 'from(bucket: "logs") |> range(start: -1h) |> filter(fn: (r) => r._measurement == "error_events") |> group(columns: ["hostname", "level"]) |> sum()' --org $INFLUX_ORG --token $INFLUX_TOKEN
```

#### Xóa dữ liệu logs sau khi sử dụng xong
```bash
   # Xóa log files trên disk
   find data/logs -type f -not -name ".gitkeep" -delete
   # hoặc sạch luôn (cẩn thận):
   rm -rf data/logs/web{1,2,3}/*

   # Xóa dữ liệu trong Kafka topics (Git Bash trên Windows)
   # Cách 1 (khuyên dùng): dùng helper script trong repo — script sẽ chờ broker rồi recreate topics sạch
   bash kafka/create-topic.sh

   # Cách 2: Xóa từng topic rồi tạo lại (non-interactive, phù hợp với Git Bash)
   docker compose exec -T kafka bash -lc "/opt/bitnami/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --delete --topic web-logs"
   docker compose exec -T kafka bash -lc "/opt/bitnami/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --delete --topic web-errors"
   docker compose exec -T kafka bash -lc "/opt/bitnami/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --create --replication-factor 1 --partitions 1 --topic web-logs"
   docker compose exec -T kafka bash -lc "/opt/bitnami/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --create --replication-factor 1 --partitions 1 --topic web-errors"
```

### Troubleshooting

#### Lỗi kết nối Spark Worker:
```bash
# Restart lại Spark cluster
docker-compose -f docker-compose.spark.yml down
docker-compose -f docker-compose.spark.yml up -d

# Kiểm tra network và services
docker network ls | grep appnet
docker-compose -f docker-compose.spark.yml ps
```

#### Lỗi InfluxDB connection:
```bash
# Kiểm tra InfluxDB service
docker-compose -f docker-compose.don.yml ps influxdb

# Kiểm tra logs InfluxDB
docker logs influxdb | tail -20

# Test kết nối thủ công
curl -I http://localhost:8086/ping

# Kiểm tra token và org
source .env && echo "Token length: ${#INFLUX_TOKEN}, Org: $INFLUX_ORG"
```

#### Không có dữ liệu trong InfluxDB:
```bash
# Kiểm tra Kafka có messages
docker exec kafka kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic web-logs --max-messages 5 --timeout-ms 5000

# Kiểm tra Spark job có chạy và xử lý dữ liệu
docker logs spark-master 2>/dev/null | grep -E "(SUCCESS.*Wrote|stream_access.py|MicroBatchExecution)"

# Kiểm tra environment variables được truyền đúng
docker exec spark-master env | grep -E "(INFLUX|WINDOW|CHECKPOINT)"

# Test manual write vào InfluxDB
source .env && echo "test_measurement,tag1=value1 field1=123i $(date +%s)000000000" | docker exec -i influxdb influx write --bucket $INFLUX_BUCKET --org $INFLUX_ORG --token $INFLUX_TOKEN
```



### Example output khi pipeline hoạt động
```
# Từ Spark logs
SUCCESS: Wrote 6 lines to InfluxDB bucket 'logs'
SUCCESS: Wrote 5 lines to InfluxDB bucket 'logs' 
SUCCESS: Wrote 3 lines to InfluxDB bucket 'logs'

# Từ InfluxDB query
Table: keys: [_start, _stop, _field, _measurement, env, hostname, method]
http_stats | env=it-check | hostname=web1 | method=GET | avg_rt=0.133 | count=3 | rps=0.3

Table: keys: [_start, _stop, _field, _measurement, env, hostname, kind]  
anomaly | env=it-check | hostname=web1 | kind=ip_spike | ip=2.2.2.2 | count=3 | score=1.0
```

