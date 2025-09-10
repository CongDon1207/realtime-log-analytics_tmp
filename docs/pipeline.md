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

## Các bước khởi chạy Pipeline
### 0. Tạo network trước
```bash
docker network create appnet
```

### 1. Khởi động Kafka
```bash
# Khởi động Kafka service
docker-compose -f docker-compose.hao.yml up -d

# Kiểm tra Kafka đã running
docker-compose -f docker-compose.hao.yml ps
```

### 2. Tạo Topics Kafka
```bash
# Tạo (hoặc recreate) các topic bằng script helper có sẵn trong container
# Script sẽ xóa (nếu có) rồi tạo lại `web-logs` và `web-errors` một cách an toàn.
bash kafka/create-topic2.sh

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
# Tạo 10 requests loi đến /api endpoint
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

### Bước 3: Khởi chạy Spark cluster
```bash
# Khởi động Spark cluster (master + worker)
docker-compose -f docker-compose.spark.yml up -d

# Kiểm tra Spark cluster
docker-compose -f docker-compose.spark.yml ps
docker logs spark-master | tail -10
```

### Bước 4: Chạy Spark Streaming job
```bash
# Lệnh ngắn gọn (tự nạp .env, chạy 70–75s rồi dừng)
bash scripts/run_access_stream.sh

#Hoặc ép timeout:
set -a; . .env; set +a; docker exec -e INFLUX_URL -e INFLUX_TOKEN -e INFLUX_ORG -e INFLUX_BUCKET -e ENV_TAG -e WINDOW_DURATION -e WATERMARK -e CHECKPOINT_DIR spark-master bash -lc 'timeout 75s /opt/bitnami/spark/bin/spark-submit --master spark://spark-master-influx:7077 /opt/spark/app/src/python/stream_access.py'
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




#### Kiểm tra dữ liệu trong InfluxDB (sang terminal khác):
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
