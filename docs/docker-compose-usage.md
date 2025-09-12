# Hướng dẫn sử dụng docker-compose.yml tổng hợp

## Giới thiệu
File `docker-compose.yml` này gom tất cả services từ 5 file compose riêng biệt:
- `docker-compose.don.yml` - InfluxDB
- `docker-compose.nginx.yml` - Nginx Web Servers  
- `docker-compose.hao.yml` - Kafka
- `docker-compose.flume.yml` - Flume Services
- `docker-compose.spark.yml` - Spark Master/Worker

## Thay đổi chính
- **Sử dụng 1 network duy nhất**: `appnet` (tên thực: `realtime-analytics-net`)
- **Giữ nguyên tất cả config**: Không thay đổi cấu hình bên trong containers
- **Bổ sung depends_on**: Đảm bảo thứ tự khởi động đúng

## Cách sử dụng

### Khởi động toàn bộ stack:
```bash
docker compose up -d
```

### Khởi động từng nhóm services:
```bash
# Chỉ InfluxDB
docker compose up -d influxdb

# Chỉ Nginx servers
docker compose up -d nginx-web1 nginx-web2 nginx-web3

# Chỉ Kafka
docker compose up -d kafka

# Chỉ Flume services
docker compose up -d flume-collector flume-agent-web1 flume-agent-web2 flume-agent-web3

# Chỉ Spark cluster
docker compose up -d spark-master spark-worker
```

### Xem logs:
```bash
# Toàn bộ
docker compose logs -f

# Theo service
docker compose logs -f influxdb
docker compose logs -f kafka
docker compose logs -f spark-master
```

### Dừng services:
```bash
# Dừng toàn bộ
docker compose down

# Dừng + xóa volumes
docker compose down -v
```

## Ports được expose:
- **InfluxDB**: 8086
- **Nginx Web1**: 8081  
- **Nginx Web2**: 8082
- **Nginx Web3**: 8083
- **Kafka**: 9092, 9093
- **Flume Collector**: 41414
- **Spark Master**: 7077
- **Spark UI**: 8084

## Network
Tất cả services chạy trên network `realtime-analytics-net` để đảm bảo connectivity.

## Lưu ý
- Các file compose riêng biệt vẫn được giữ nguyên
- Có thể tiếp tục sử dụng Makefile với các file compose riêng
- File này phù hợp để chạy toàn bộ stack cùng lúc hoặc testing
