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
- ✓ Nginx tạo access/error logs
- ✓ Flume agents đọc logs từ files
- ✓ Flume collector nhận data từ agents  
- ✓ Data được gửi vào Kafka topics
- ✓ Consumer có thể đọc real-time data từ Kafka

---

## Spark Structured Streaming (access → metrics/anomaly → InfluxDB)

### Bước 1: Khởi động InfluxDB
```bash
# Khởi động InfluxDB service
docker-compose -f docker-compose.don.yml up -d

# Kiểm tra InfluxDB đã chạy
docker-compose -f docker-compose.don.yml ps influxdb

# Khởi tạo org/bucket (chỉ chạy 1 lần) - script sẽ đọc cấu hình từ .env
bash influxdb/init/onboarding.sh
```

### Bước 2: Kiểm tra cấu hình InfluxDB
```bash
# Kiểm tra InfluxDB API có sẵn sàng
curl -I http://localhost:8086/ping

# Kiểm tra cấu hình từ file .env
source .env && echo "ORG: $INFLUX_ORG, BUCKET: $INFLUX_BUCKET"

# Kiểm tra cấu hình InfluxDB từ .env
source .env && echo "INFLUX_TOKEN: ${INFLUX_TOKEN:0:20}..."
```

### Bước 3: Khởi chạy Spark cluster
```bash
# Khởi động Spark cluster (master + worker)
make up-spark

# Kiểm tra Spark cluster
docker-compose -f docker-compose.spark.yml ps
docker logs spark-master | tail -10
```

### Bước 4: Chạy Spark Streaming job
```bash
# Chạy streaming job để xử lý logs từ Kafka → InfluxDB (không cần --packages nhờ spark-defaults.conf)
source .env && docker exec -e INFLUX_URL="$INFLUX_URL" -e INFLUX_TOKEN="$INFLUX_TOKEN" -e INFLUX_ORG="$INFLUX_ORG" -e INFLUX_BUCKET="$INFLUX_BUCKET" spark-master bash -c "cd /opt/spark/app && /opt/bitnami/spark/bin/spark-submit --master spark://spark-master:7077 src/python/stream_access.py" &

# Hoặc chạy trong background với timeout (để test)
# source .env && timeout 30s docker exec -e INFLUX_URL="$INFLUX_URL" -e INFLUX_TOKEN="$INFLUX_TOKEN" -e INFLUX_ORG="$INFLUX_ORG" -e INFLUX_BUCKET="$INFLUX_BUCKET" spark-master bash -c "cd /opt/spark/app && /opt/bitnami/spark/bin/spark-submit --master spark://spark-master:7077 src/python/stream_access.py"
```

### Bước 5: Test pipeline với dữ liệu mẫu
```bash
# Tạo dữ liệu test logs bằng manual input vào Kafka
echo '{"event_time": 1725876100, "hostname": "web1", "method": "GET", "path": "/api/users", "status": 200, "remote": "192.168.1.100", "rt": 0.045, "user_agent": "Mozilla/5.0"}
{"event_time": 1725876101, "hostname": "web2", "method": "POST", "path": "/api/login", "status": 201, "remote": "10.0.0.5", "rt": 0.120, "user_agent": "curl"}
{"event_time": 1725876102, "hostname": "web1", "method": "GET", "path": "/api/data", "status": 500, "remote": "192.168.1.200", "rt": 2.500, "user_agent": "Python"}' | docker exec -i kafka kafka-console-producer.sh --broker-list localhost:9092 --topic web-logs

# Hoặc sử dụng real Nginx logs từ pipeline phần đầu
# for i in {1..10}; do curl -s -o /dev/null http://localhost:8081/api; done
```

### Output và measurements InfluxDB

Pipeline sẽ tạo ra 3 measurements trong InfluxDB:

#### 1. `http_stats` - Thống kê HTTP theo cửa sổ thời gian
- **Tags**: `env`, `hostname`, `method` 
- **Fields**: `count` (tổng requests), `rps` (requests/second), `avg_rt` (response time trung bình), `max_rt` (response time tối đa), `err_rate` (tỷ lệ lỗi %)
- **Time**: `window_end` (kết thúc cửa sổ 10 giây)

#### 2. `top_urls` - Top URLs được truy cập nhiều nhất
- **Tags**: `env`, `hostname`, `status`, `path`
- **Fields**: `count` (số lần truy cập)
- **Time**: `window_end`

#### 3. `anomaly` - Phát hiện bất thường
- **Tags**: `env`, `hostname`, `kind` (loại bất thường)
- **Fields**: `ip` (IP address), `count` (số requests), `score` (điểm bất thường)
- **Time**: `window_end`

### Kiểm tra kết quả

#### Kiểm tra Spark Streaming hoạt động:
```bash
# Xem logs Spark job (filter cho các thông tin quan trọng)
docker logs spark-master 2>/dev/null | grep -E "(SUCCESS|Wrote.*lines|InfluxDB|Exception|ERROR)" | tail -10

# Kiểm tra Spark UI (chỉ khi streaming đang chạy)
echo "Spark UI: http://localhost:4040"

# Kiểm tra streaming job status
docker logs spark-master --tail 20 | grep -E "(MicroBatchExecution|Stream started)"
```

#### Kiểm tra dữ liệu trong InfluxDB:
```bash
# Truy cập InfluxDB UI
echo "InfluxDB UI: http://localhost:8086 (Org: primary, Bucket: logs)"

# Query dữ liệu từ command line
source .env && docker exec influxdb influx query 'from(bucket: "logs") |> range(start: -1h) |> limit(n: 10)' --org $INFLUX_ORG --token $INFLUX_TOKEN

# Query http_stats với pivot để xem metrics
source .env && docker exec influxdb influx query 'from(bucket: "logs") |> range(start: -1h) |> filter(fn: (r) => r._measurement == "http_stats") |> pivot(rowKey:["_time"], columnKey: ["_field"], valueColumn: "_value")' --org $INFLUX_ORG --token $INFLUX_TOKEN

# Count tổng số records
source .env && docker exec influxdb influx query 'from(bucket: "logs") |> range(start: -1h) |> count()' --org $INFLUX_ORG --token $INFLUX_TOKEN
```

#### Query measurements cụ thể:
```bash
# Query anomaly detection results
source .env && docker exec influxdb influx query 'from(bucket: "logs") |> range(start: -1h) |> filter(fn: (r) => r._measurement == "anomaly") |> pivot(rowKey:["_time"], columnKey: ["_field"], valueColumn: "_value")' --org $INFLUX_ORG --token $INFLUX_TOKEN

# Query top URLs
source .env && docker exec influxdb influx query 'from(bucket: "logs") |> range(start: -1h) |> filter(fn: (r) => r._measurement == "top_urls") |> sort(columns: ["count"], desc: true) |> limit(n: 10)' --org $INFLUX_ORG --token $INFLUX_TOKEN
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

### Ghi chú performance
- **Package pre-configured**: `spark.jars.packages org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.0` trong `spark/conf/spark-defaults.conf` giúp không cần `--packages` flag
- **Native libraries**: Đã cài `libsnappy-dev` trong Spark Docker image để tránh lỗi compression
- **InfluxDB client**: `influxdb-client==1.35.0` được install sẵn trong runtime environment
- Checkpoint được lưu tại `/tmp/checkpoints/{stats,top_urls,anomaly}` để đảm bảo fault tolerance

### Ghi chú thiết kế
- **Window & Watermark**: 10 giây với watermark 2 phút để xử lý late events
- **Metrics calculation**: 
  - `err_rate` tính trên tổng requests theo (hostname, method) mỗi window
  - `rps` = count / window_duration_seconds
  - `anomaly` detection với thresholds: IP spike ≥50, scan ≥20 paths, error rate ≥10%
- **Data format**: InfluxDB line protocol với proper tag/field separation và nanosecond timestamps
- **Scalability**: Top URLs tính sẵn theo (hostname, status, path), filtering Top-N ở visualization layer

### Performance metrics từ test
- **Processing latency**: ~2-3 giây cho mỗi micro-batch 10s window
- **Throughput**: Xử lý được ~5 events/second với 3 parallel streaming queries
- **Memory usage**: Spark driver ~434MB, worker tùy thuộc workload
- **InfluxDB write**: Batch size 500 records, flush interval 1s

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
