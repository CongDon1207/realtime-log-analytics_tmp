# Hướng dẫn chạy Load Test bằng k6 (Cách A – STDIN)

## 🎯 Mục tiêu
Sinh lưu lượng HTTP đều đặn vào 3 container Nginx (`web1`, `web2`, `web3`) để tạo access log JSON liên tục, phục vụ pipeline Flume → Kafka → Spark → InfluxDB.

---

## 📝 Yêu cầu tiên quyết
- Đã cài Docker & Docker Compose.
- Đã khởi động 3 web server Nginx:

  ```bash
  # Khởi động 3 container web1, web2, web3
  docker compose -f docker-compose.nginx.yml up -d

  # Kiểm tra trạng thái
  docker ps --filter "name=web" --format "table {{.Names}}\t{{.Status}}"
  ```

Kỳ vọng: web1, web2, web3 đang chạy (healthy).

---

## 📄 Script k6 mẫu
File: `loadgen/web-traffic.js`

```javascript
import http from 'k6/http';
import { sleep } from 'k6';

export const options = {
  vus: 50,           // số người dùng ảo đồng thời
  duration: '60s',   // thời lượng chạy
};

const targets = [
  'http://web1:8081/',
  'http://web2:8082/',
  'http://web3:8083/',
];

export default function () {
  const t = targets[Math.floor(Math.random() * targets.length)];
  http.get(t);
  sleep(0); // giữ QPS cao
}
```

---

## 🚀 Cách chạy k6 (qua STDIN, không cần mount volume)

Trên Linux / macOS / Git Bash (Windows):

```bash
docker run --rm -i \
  --network=realtime-log-analytics_default \
  grafana/k6 run - < loadgen/web-traffic.js
```

Trên PowerShell (Windows):

```powershell
Get-Content .\loadgen\web-traffic.js | docker run --rm -i `
  --network=realtime-log-analytics_default `
  grafana/k6 run -
```

Giải thích:
- `--network=realtime-log-analytics_default`: để k6 gọi được web1|web2|web3 qua DNS nội bộ Docker.
- `run - < scripts/loadgen/web-traffic.js`: nạp script từ STDIN, không cần volume.

---

## ✅ Kết quả mong đợi
k6 in thống kê sau 60s, ví dụ:

```text
running (1m0.0s), 50 VUs, 0 complete and 0 interrupted VUs
http_reqs................: ~9000  150.0/s
http_req_duration........: p(95)=3-10ms
checks...................: 100.00% ✓ 9000 ✗ 0
```

File log tăng đều (ví dụ kiểm tra):

```bash
tail -n 5 data/logs/web1/access.json.log
tail -n 5 data/logs/web2/access.json.log
tail -n 5 data/logs/web3/access.json.log
```

Ví dụ 1 dòng log:

```json
{ "time":"2025-08-25T06:48:49+00:00","remote":"172.20.0.5","host":"web1",
  "method":"GET","path":"/","status":200,"bytes":154,"ua":"Grafana k6/1.2.2","rt":0.000 }
```

---

## ⚙️ Tuỳ biến nhanh
Tăng tải:

```javascript
export const options = { vus: 100, duration: '120s' };
```

Đa dạng đường dẫn:

```javascript
const targets = [
  'http://web1:8081/',
  'http://web1:8081/api',
  'http://web2:8082/login',
  'http://web3:8083/search?q=test',
];
```

---

## 🔧 Sự cố thường gặp
- `lookup web1: no such host` → chưa gắn đúng network. Đảm bảo có `--network=realtime-log-analytics_default` và 3 container `web1|web2|web3` đang chạy.
- Không thấy log tăng → kiểm tra file cấu hình Nginx (đúng cổng 8081/8082/8083) và quyền ghi thư mục log.
- Windows Git Bash lỗi mount → dùng cách STDIN như hướng dẫn này.

---

## 🧹 Dọn dẹp

```bash
# dừng 3 web server
docker compose -f docker-compose.nginx.yml down

# (tuỳ chọn) xoá log
rm -rf data/logs/web1/* data/logs/web2/* data/logs/web3/*
```