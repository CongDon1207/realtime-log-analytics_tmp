# InfluxDB Workflow Guide

Hướng dẫn đầy đủ để vận hành InfluxDB trong dự án realtime-log-analytics.

## 📋 Tổng quan

InfluxDB được sử dụng làm storage backend cho hệ thống phân tích log real-time, lưu trữ metrics HTTP request được tạo bởi log generator và cung cấp API query cho việc phân tích dữ liệu.

## 🏗️ Kiến trúc

```
┌─────────────────┐    ┌──────────────┐    ┌─────────────────┐
│  Log Generator  │───▶│   InfluxDB   │◀───│  Query Tools    │
│  (Python)       │    │  Container   │    │  (Flux Queries) │
└─────────────────┘    └──────────────┘    └─────────────────┘
```

- **Log Generator**: Python script tạo synthetic HTTP request data
- **InfluxDB**: Time-series database lưu trữ metrics
- **Query Tools**: Flux queries để verify và debug dữ liệu

## 🚀 Workflow hoàn chỉnh

### Bước 1: Khởi động InfluxDB Container

**🎯 Mục đích:** Khởi tạo cơ sở dữ liệu chuỗi thời gian để làm backend lưu trữ cho hệ thống phân tích

**📝 Ý nghĩa:** Container InfluxDB cung cấp:
- Cơ sở dữ liệu chuỗi thời gian tối ưu cho dữ liệu chỉ số
- Các điểm cuối API để nhập và truy vấn dữ liệu  
- Lưu trữ bền vững cho phân tích dữ liệu lịch sử
- Nền tảng cho toàn bộ pipeline phân tích

```bash
cd d:/DockerData/realtime-log-analytics
docker-compose -f docker-compose.don.yml up -d
```

Kiểm tra container đã chạy:
```bash
docker ps | grep influxdb
# Kết quả: trạng thái container nên là "Up X seconds (healthy)"
```

**✅ Kết quả:** Dịch vụ cơ sở dữ liệu sẵn sàng nhận dữ liệu và phục vụ truy vấn

### Bước 2: Thiết lập ban đầu (Onboarding)

**🎯 Mục đích:** Cấu hình ban đầu cho InfluxDB để có thể nhận và lưu trữ dữ liệu

**📝 Ý nghĩa:** Script thiết lập thực hiện:
- Tạo tổ chức và người dùng quản trị trong InfluxDB
- Tạo token xác thực để truy cập API
- Thiết lập bucket `http-logs` để lưu chỉ số HTTP request
- Xác minh kết nối và quyền hoạt động chính xác
- Đảm bảo môi trường sẵn sàng cho việc nhập dữ liệu

```bash
cd influxdb/init
./onboarding.sh
```

Script này sẽ:
- Kiểm tra tình trạng sức khỏe của InfluxDB
- Thiết lập tổ chức, người dùng, token (có thể chạy lại nhiều lần)
- Tạo bucket `http-logs`
- Xác minh kết nối

**Kết quả mong đợi:**
```
[onboarding] Health check @ http://localhost:8086 ...
[setup] POST /api/v2/setup (idempotent)
[setup] Already initialized (OK)
[verify] Token → /api/v2/me
[verify] Org → demo-org
[verify] orgID=b861f11bbc0e3268
[verify] Bucket → http-logs
[verify] bucket OK: http-logs
[done] Influx ready: org=demo-org (id=b861f11bbc0e3268), bucket=http-logs
```

**✅ Kết quả:** Cơ sở dữ liệu đã có thông tin xác thực và schema để nhận dữ liệu chỉ số HTTP

### Bước 3: Chạy Log Generator

**🎯 Mục đích:** Tạo dữ liệu HTTP request giả lập để kiểm tra và trình diễn hệ thống phân tích

**📝 Ý nghĩa:** Log generator mô phỏng:
- Mẫu lưu lượng HTTP thực tế từ nhiều máy chủ web
- Các loại request đa dạng (GET/POST) và mã phản hồi (2xx/3xx/4xx/5xx)  
- Chỉ số chuỗi thời gian: số lượng, RPS, thời gian phản hồi, phần trăm độ trễ
- Kiểm tra tải cho hiệu năng cơ sở dữ liệu và tối ưu hóa truy vấn
- Nguồn dữ liệu cho trí tuệ kinh doanh và bảng điều khiển giám sát

```bash
cd influxdb/log-generator
source .env.gen

# Test ngắn (30 giây)
py -3.9 log_generator.py \
  --url "$INFLUX_URL" \
  --org "$ORG_NAME" \
  --bucket "$BUCKET_NAME" \
  --token "$ADMIN_TOKEN" \
  --duration 30 \
  --qps 50 \
  --hosts 3 \
  --window 10 \
  --envtag dev

# Chạy dài hơn (5 phút)
py -3.9 log_generator.py \
  --url "$INFLUX_URL" \
  --org "$ORG_NAME" \
  --bucket "$BUCKET_NAME" \
  --token "$ADMIN_TOKEN" \
  --duration 300 \
  --qps 80 \
  --hosts 3 \
  --window 10 \
  --envtag dev
```

**Kết quả mong đợi:**
```
[batch OK] lines=12 code=204
[batch OK] lines=12 code=204
...
[summary] batches=59 ok=59 err=0 ok%=100.0
```

**✅ Kết quả:** Cơ sở dữ liệu có bộ dữ liệu thực tế để kiểm tra truy vấn và trực quan hóa

### Bước 4: Xác minh dữ liệu bằng Query Tools

**🎯 Mục đích:** Xác thực chất lượng dữ liệu và kiểm tra hiệu năng truy vấn cho sẵn sàng sản xuất

**📝 Ý nghĩa:** Việc xác thực truy vấn đảm bảo:
- Việc nhập dữ liệu hoạt động chính xác không bị hỏng
- Cú pháp và logic truy vấn Flux đúng cho yêu cầu kinh doanh  
- Hiệu năng truy vấn chấp nhận được cho bảng điều khiển thời gian thực
- Lược đồ dữ liệu nhất quán và đầy đủ cho pipeline phân tích
- Khả năng phát hiện lỗi và khắc phục sự cố

#### 4.1 Chạy Verify Queries

**🔍 Mục đích:** Truy vấn xác thực cấp độ sản xuất cho giám sát và cảnh báo

```bash
cd influxdb
source .env.influx

# Test tất cả verify queries
cat verify.flux | docker exec -i influxdb influx query --org "$ORG_NAME"

# Kiểm tra tất cả kết quả có chạy
cat verify.flux | docker exec -i influxdb influx query --org "$ORG_NAME" --raw | grep "^#default"
```

**Kết quả mong đợi (7 truy vấn):**
- `count_summary_5m` - Tổng request trong 5 phút → **Giá trị kinh doanh:** Giám sát lượng lưu lượng
- `error_rate_1m` - Tỷ lệ lỗi theo phút → **Giá trị kinh doanh:** Cảnh báo tình trạng dịch vụ  
- `error_summary_5m` - Tổng lỗi trong 5 phút → **Giá trị kinh doanh:** Phát hiện sự cố
- `p95_max_rt_by_host` - Độ trễ P95 theo máy chủ → **Giá trị kinh doanh:** Giám sát SLA hiệu năng
- `p99_max_rt_by_host` - Độ trễ P99 theo máy chủ → **Giá trị kinh doanh:** Phát hiện ngoại lệ
- `rps_summary_5m` - Tóm tắt RPS 5 phút → **Giá trị kinh doanh:** Lập kế hoạch công suất
- `rps_total_1m` - Tổng RPS theo phút → **Giá trị kinh doanh:** Giám sát tải thời gian thực

#### 4.2 Chạy Debug Queries

**🔧 Mục đích:** Gỡ lỗi nhanh và khám phá dữ liệu cho quy trình phát triển

```bash
# Kiểm tra tất cả debug queries
cat debug.flux | docker exec -i influxdb influx query --org "$ORG_NAME"

# Kiểm tra tất cả kết quả có chạy
cat debug.flux | docker exec -i influxdb influx query --org "$ORG_NAME" --raw | grep "^#default"
```

**Kết quả mong đợi (5 truy vấn):**
- `latest_rows` - 10 hàng mới nhất → **Giá trị gỡ lỗi:** Kiểm tra dữ liệu gần đây
- `total_count_10s` - Tổng request theo cửa sổ 10s → **Giá trị gỡ lỗi:** Kiểm tra tính đầy đủ dữ liệu
- `rps_by_status_1m` - RPS theo mã trạng thái (1 phút) → **Giá trị gỡ lỗi:** Phân tích mẫu lưu lượng
- `top_hosts_by_rps` - Máy chủ hàng đầu theo RPS → **Giá trị gỡ lỗi:** Xác minh phân phối tải
- `latency_p95_by_host` - Độ trễ P95 theo máy chủ → **Giá trị gỡ lỗi:** So sánh hiệu năng

**✅ Kết quả:** Tin tưởng vào độ chính xác dữ liệu và độ tin cậy truy vấn cho triển khai sản xuất

## 📊 Lược đồ dữ liệu

**🎯 Mục đích:** Mô hình dữ liệu có cấu trúc tối ưu cho phân tích chuỗi thời gian và truy vấn nhanh

**📝 Ý nghĩa:** Cân nhắc thiết kế lược đồ:
- **Tags** (được lập chỉ mục): Lọc nhanh và các thao tác nhóm cho truy vấn thời gian thực
- **Fields** (không lập chỉ mục): Giá trị số cho tổng hợp và tính toán  
- **Timestamp**: Sắp xếp chuỗi thời gian cho phân tích thời gian
- **Measurement**: Nhóm logic cho các chỉ số liên quan

### Measurement: `http_requests`

**Tags (Được lập chỉ mục cho truy vấn nhanh):**
- `env`: Môi trường (dev, prod) → **Mục đích:** Phân tách dữ liệu đa môi trường
- `hostname`: Máy chủ web (web1, web2, web3) → **Mục đích:** Phân tích hiệu năng từng máy chủ
- `method`: Phương thức HTTP (GET, POST) → **Mục đích:** Phân tích hành vi loại request
- `status_class`: Lớp trạng thái (2xx, 3xx, 4xx, 5xx) → **Mục đích:** Tính toán tỷ lệ lỗi

**Fields (Giá trị có thể tổng hợp):**
- `count`: Số lượng requests → **Mục đích:** Chỉ số lượng lưu lượng
- `rps`: Requests per second → **Mục đích:** Giám sát tải thời gian thực
- `avg_rt`: Thời gian phản hồi trung bình → **Mục đích:** Theo dõi baseline hiệu năng
- `max_rt`: Thời gian phản hồi tối đa → **Mục đích:** Phát hiện đột biến độ trễ

**Ví dụ điểm dữ liệu:**
```
http_requests,env=dev,hostname=web1,method=GET,status_class=2xx count=180,rps=18,avg_rt=0.054,max_rt=0.151 1725235620000000000
```

**🏗️ Lợi ích mô hình dữ liệu:**
- **Truy vấn nhanh**: Tags được lập chỉ mục cho các mệnh đề WHERE
- **Tổng hợp linh hoạt**: Fields hỗ trợ các thao tác SUM, AVG, MAX  
- **Phân tích theo thời gian**: Timestamp tích hợp cho các thao tác chuỗi thời gian
- **Lược đồ có thể mở rộng**: Dễ dàng thêm tags/fields mới cho chỉ số mở rộng

## 🔧 Tệp cấu hình

### Tệp cấu hình cốt lõi

- `docker-compose.don.yml` - Định nghĩa container InfluxDB
- `influxdb/init/onboarding.sh` - Script thiết lập
- `influxdb/init/.env.influx` - Cấu hình kết nối InfluxDB
- `influxdb/log-generator/.env.gen` - Cấu hình log generator

### Tệp truy vấn

- `influxdb/verify.flux` - Truy vấn xác minh sản xuất
- `influxdb/debug.flux` - Truy vấn gỡ lỗi nhanh

## 🐛 Khắc phục sự cố

### Container không khởi động

```bash
# Kiểm tra nhật ký
docker logs influxdb

# Khởi động lại container
docker-compose -f docker-compose.don.yml down
docker-compose -f docker-compose.don.yml up -d
```

### Log generator lỗi xác thực

```bash
# Kiểm tra token trong .env.gen
cd influxdb/log-generator
cat .env.gen | grep ADMIN_TOKEN

# Chạy lại onboarding nếu cần
cd ../init
./onboarding.sh
```

### Truy vấn không trả về dữ liệu

```bash
# Kiểm tra có dữ liệu không
echo 'from(bucket: "http-logs") |> range(start: -1h) |> filter(fn: (r) => r._measurement == "http_requests") |> count()' | docker exec -i influxdb influx query --org "demo-org"

# Kiểm tra khoảng thời gian trong truy vấn (có thể cần tăng từ -5m lên -30m)
```

### Vấn đề hiệu năng

```bash
# Kiểm tra kích thước bucket
docker exec -it influxdb du -sh /var/lib/influxdb2/

# Nén cơ sở dữ liệu nếu cần
docker exec -it influxdb influx bucket update --id <bucket-id> --retention 24h0m0s
```

## 📈 Giám sát & Chỉ số

**🎯 Mục đích:** Giám sát tình trạng hệ thống chủ động và tối ưu hóa hiệu năng

**📝 Ý nghĩa:** Chiến lược giám sát đảm bảo:
- **Tình trạng pipeline dữ liệu**: Phát hiện sớm các vấn đề nhập dữ liệu
- **Hiệu năng truy vấn**: Tối ưu hóa thời gian phản hồi cho trải nghiệm người dùng  
- **Sử dụng tài nguyên**: Lập kế hoạch công suất và tối ưu hóa chi phí
- **Chỉ số kinh doanh**: Thông tin chi tiết thời gian thực cho quyết định vận hành

### Chỉ số hiệu năng chính

1. **Tỷ lệ nhập dữ liệu**: ~50-80 QPS từ log generator
   - **Mục đích**: Xác thực thông lượng pipeline dữ liệu
   - **Ngưỡng cảnh báo**: <90% tỷ lệ mong đợi

2. **Hiệu năng truy vấn**: <1s cho hầu hết truy vấn  
   - **Mục đích**: Đảm bảo bảng điều khiển phản hồi và phân tích thời gian thực
   - **Ngưỡng cảnh báo**: >2s thời gian phản hồi trung bình

3. **Sử dụng lưu trữ**: ~10MB mỗi giờ với 80 QPS
   - **Mục đích**: Quản lý chi phí và lập kế hoạch lưu giữ
   - **Ngưỡng cảnh báo**: >1GB tăng trưởng mỗi ngày

4. **Tỷ lệ lỗi**: 0% cho nhập dữ liệu
   - **Mục đích**: Đảm bảo tính toàn vẹn dữ liệu
   - **Ngưỡng cảnh báo**: >1% batch thất bại

### Lệnh kiểm tra tình trạng

**🔍 Giá trị kinh doanh**: Xác minh tự động các thành phần hệ thống

```bash
# Tình trạng container InfluxDB → Tính khả dụng dịch vụ
docker ps | grep influxdb

# Tình trạng nhập dữ liệu → Tính toàn vẹn pipeline  
cd influxdb/log-generator && source .env.gen && py -3.9 log_generator.py --url "$INFLUX_URL" --org "$ORG_NAME" --bucket "$BUCKET_NAME" --token "$ADMIN_TOKEN" --duration 10 --qps 10 --hosts 1 --window 10 --envtag test

# Tình trạng truy vấn → Sẵn sàng phân tích
cd influxdb && source .env.influx && echo 'from(bucket: "http-logs") |> range(start: -5m) |> limit(n: 1)' | docker exec -i influxdb influx query --org "$ORG_NAME"
```

## 🔄 Các nhiệm vụ bảo trì

**🎯 Mục đích:** Bảo trì hệ thống chủ động để đảm bảo độ tin cậy và hiệu năng lâu dài

### Hàng ngày
- Kiểm tra trạng thái container → **Mục đích**: Đảm bảo tính khả dụng dịch vụ
- Xác minh tỷ lệ nhập dữ liệu → **Mục đích**: Giám sát tình trạng pipeline

### Hàng tuần  
- Xem xét việc sử dụng lưu trữ → **Mục đích**: Tối ưu hóa chi phí và lập kế hoạch công suất
- Kiểm tra quy trình sao lưu/khôi phục → **Mục đích**: Sẵn sàng khôi phục thảm họa

### Hàng tháng
- Tối ưu hóa chính sách lưu giữ → **Mục đích**: Quản lý chi phí lưu trữ
- Xem xét hiệu năng truy vấn → **Mục đích**: Tối ưu hóa trải nghiệm người dùng

**📝 Ý nghĩa:** Bảo trì thường xuyên ngăn ngừa:
- **Sự cố dịch vụ** thông qua giám sát chủ động
- **Mất dữ liệu** thông qua quy trình sao lưu đã kiểm tra  
- **Suy giảm hiệu năng** thông qua tối ưu hóa
- **Chi phí vượt quá** thông qua quản lý lưu trữ

## 🚨 Quy trình khẩn cấp

### Đặt lại hoàn toàn

```bash
# Dừng và xóa hoàn toàn
docker-compose -f docker-compose.don.yml down -v

# Khởi động lại từ đầu
docker-compose -f docker-compose.don.yml up -d
sleep 10
cd influxdb/init && ./onboarding.sh
```

### Khôi phục dữ liệu

```bash
# Sao lưu dữ liệu
docker exec influxdb influx backup /tmp/backup

# Khôi phục dữ liệu
docker exec influxdb influx restore /tmp/backup
```

---

**Lưu ý**: Tệp này được tạo dựa trên kiểm tra thực tế quy trình InfluxDB. Tất cả lệnh đã được xác minh hoạt động chính xác trong môi trường hiện tại.
