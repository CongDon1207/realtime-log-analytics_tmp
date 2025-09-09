# Tài liệu Dòng Dữ liệu (Data Contract & Transform)

**Hệ thống Giám sát & Phân tích Log Server Tập trung**
**Công nghệ:** Flume, Kafka, Spark Structured Streaming, InfluxDB, Grafana

## 0) Phạm vi & Mục tiêu

* Chuẩn hoá **đầu vào** từ Nginx (access JSON, error text).
* Định nghĩa **schema** sau parse (Spark) và **schema InfluxDB** sau tổng hợp.
* Mô tả **biến đổi** dữ liệu qua từng bước, đảm bảo:

  * Đếm **4xx/5xx**, RPS, latency.
  * Phát hiện **ip\_spike / error\_surge / scan**.
  * Trực quan hoá trên **Grafana** (không nổ cardinality).

---

## 1) Nguồn dữ liệu từ Nginx

### 1.1 Access log (JSON một dòng) — **Data Contract**

**Cấu hình Nginx (đề xuất):**

```nginx
log_format json escape=json
  '{ "time":"$time_iso8601","ts":$msec,'
  '"remote":"$remote_addr","host":"$host","hostname":"$hostname",'
  '"method":"$request_method","path":"$uri","status":$status,'
  '"bytes":$body_bytes_sent,"rt":$request_time,'
  '"ua":"$http_user_agent","referer":"$http_referer" }';

access_log /var/log/nginx/access.json.log json;
```

**Ý nghĩa các trường (JSON):**

* `time` (string ISO8601) & `ts` (epoch giây, số thực): thời điểm request.
* `remote` (string): IP client.
* `host` (string): Host header.
* `hostname` (string): tên máy/container — **định danh server nguồn**.
* `method` (string): GET/POST/…
* `path` (string): URI path (không query).
* `status` (int): 200/404/500…
* `bytes` (int): số bytes body trả về.
* `rt` (float giây): request\_time (latency end-to-end).
* `ua`, `referer` (string): user-agent, referer (phụ trợ phân tích).

**Ví dụ 1 dòng access JSON:**

```json
{"time":"2025-08-25T12:34:56+07:00","ts":1692946496.123,
 "remote":"10.0.2.15","host":"web1.local","hostname":"web1",
 "method":"GET","path":"/login","status":404,
 "bytes":0,"rt":0.003,"ua":"curl/8.0.1","referer":"-"}
```

> Ghi chú: Nếu có LB/proxy, bật `real_ip_header` + `set_real_ip_from` để `remote` là IP thật.

---

### 1.2 Error log (TEXT thô) — **Data Contract**

* Nginx OSS **không** hỗ trợ format JSON cho error log. Ta giữ **text** và **parse ở Spark**.
* Ví dụ 1 dòng:

```
2025/08/25 12:35:01 [error] 24#24: *127 connect() failed (111: Connection refused) while connecting to upstream, client: 192.168.1.10, server: _, request: "GET /api HTTP/1.1", upstream: "http://10.0.0.5:8080/api", host: "web1"
```

**JSON mục tiêu sau khi Spark parse (chuẩn hoá):**

```json
{
  "time":"2025/08/25 12:35:01",
  "level":"error",
  "cid":127,
  "message":"connect() failed (111: Connection refused) while connecting to upstream",
  "client":"192.168.1.10",
  "server":"_",
  "request":"GET /api HTTP/1.1",
  "upstream":"http://10.0.0.5:8080/api",
  "host":"web1"
}
```

**Regex gợi ý (Spark dùng `regexp_extract` nhiều cột):**

```
^(?<time>\d{4}\/\d{2}\/\d{2} \d{2}:\d{2}:\d{2}) \[(?<level>\w+)\] \d+#\d+: \*(?<cid>\d+)
 (?<message>.*?)(?:, client: (?<client>[^,]+))?(?:, server: (?<server>[^,]+))?
 (?:, request: "(?<request>[^"]+)")?(?:, upstream: "(?<upstream>[^"]+)")?
 (?:, host: "(?<host>[^"]+)")?(?:, referrer: "(?<referer>[^"]+)")?
```

---

## 2) Luồng dữ liệu qua các service

### 2.1 Nginx

* Ghi **access** dạng **JSON 1 dòng** vào `/var/log/nginx/access.json.log`.
* Ghi **error** dạng **text** vào `/var/log/nginx/error.log`.
* Mỗi “server” (web1/web2/web3) sinh log riêng và có `hostname` riêng trong JSON.

### 2.2 Flume Agent (mỗi server)

* **Source:** `TAILDIR` theo dõi **2 nhóm file**:

  * `f_access = /var/log/nginx/access*.json.log`  → header `type=access`
  * `f_error  = /var/log/nginx/error.log`        → header `type=error`
* **Channel:** `file channel` (bền vững khi restart/logrotate).
* **Sink:** `KafkaSink` → topic mặc định `web-logs`.
  *(Tuỳ chọn: dùng **Multiplexing Channel Selector** để route `type=error` sang `web-errors`.)*
* **Header thêm:** `host=web01|web02|web03` (dù `hostname` có trong access JSON, header giúp route/partition nếu cần).

> Lưu ý: KafkaSink của Flume **thường chỉ gửi body**; **đừng phụ thuộc** vào việc giữ nguyên header trên Kafka — hãy **đảm bảo `hostname` có trong body JSON**.

### 2.3 Kafka

* **Topic gợi ý:**

  * `web-logs`: access JSON (và có thể cả error text nếu chưa tách).
  * `web-errors`: error text (nếu muốn tách luồng).
* **Key gợi ý:** `hostname` (partition theo server nguồn).

### 2.4 Spark Structured Streaming

* **Stream A (access)**:

  1. Đọc `web-logs` → cast `value` → `from_json` theo **schema access**.
  2. Chuẩn hoá: tạo `status_class` (2xx/3xx/4xx/5xx).
  3. **Window 10s + watermark 2m** theo `event_time` (từ `ts`/`time`).
  4. Tính **metrics**:

     * `count` (số request), `rps`, `avg_rt`, `max_rt`, `err_rate`.
     * **Top-N URL** theo `status` (vd: top 404).
  5. Phát hiện **anomaly**:

     * `ip_spike`: IP có `count` vượt ngưỡng trong cửa sổ.
     * `error_surge`: `5xx` rate > ngưỡng.
     * `scan`: `distinct(path)`/IP cao trong cửa sổ.
  6. Ghi InfluxDB bằng `foreachBatch`.

* **Stream B (error)**:

  1. Đọc `web-errors` **hoặc** `web-logs` (lọc header/type=error).
  2. Dùng `regexp_extract` parse text → JSON chuẩn hoá (các cột: time, level, client, upstream, request…).
  3. **Window 10s + watermark 2m** theo thời gian parsed.
  4. Tổng hợp: `count` theo `hostname`, `level`, `upstream`.
  5. (Tuỳ chọn) rút gọn `message_class` để thống kê loại lỗi.
  6. Ghi InfluxDB (measurement `error_events` + ít `error_samples` nếu cần).

### 2.5 InfluxDB (time-series)

* **Không ghi raw access từng dòng** → chỉ ghi **metrics/summary/anomaly** để tránh nổ cardinality.

### 2.6 Grafana

* Panels:

  * **RPS** / server, **%4xx/5xx**, **Latency (avg/max/p95)**.
  * **Top URL 404/5xx**, **Top IP (scan/4xx)**.
  * **Error by level** theo thời gian, **Top upstream lỗi**.
  * **Bảng anomaly** (ip\_spike/error\_surge/scan).
* Alert rules: `ip_spike`, `error_surge` (5xx rate > ngưỡng), etc.

---

## 3) Schema chi tiết cho InfluxDB

### 3.1 `http_stats` (metrics tổng hợp access)

* **Tags (ít biến động):** `env`, `hostname`, `method`, `status_class`
* **Fields:**

  * `count` (int), `rps` (float)
  * `avg_rt` (float), `max_rt` (float)
  * `err_rate` (float) — tỷ lệ 4xx/5xx trong cửa sổ
* **Timestamp:** thời điểm cuối cửa sổ (hoặc `window_start`).

### 3.2 `top_urls` (Top-N URL trong mỗi cửa sổ)

* **Tags:** `env`, `hostname`, `status`, `path` *(chỉ Top-N để không nổ series)*
* **Fields:** `count` (int)
* **Timestamp:** thời điểm cửa sổ.

### 3.3 `anomaly`

* **Tags:** `env`, `hostname`, `kind` (`ip_spike|error_surge|scan`)
* **Fields:** `ip` (string), `count` (int), `score` (float), `window_s` (int)
* **Timestamp:** thời điểm phát hiện.

### 3.4 `error_events` (tổng hợp error log)

* **Tags:** `env`, `hostname`, `level`, `upstream`
* **Fields:** `count` (int) *(+ `message_class` nếu set nhỏ, hoặc ghi riêng)*
* **Timestamp:** thời điểm cửa sổ.

> (Tuỳ chọn) `error_samples`: lưu rất ít mẫu (để soi nhanh), **tránh ghi nhiều**.

---

## 4) Ví dụ end-to-end (1 access + 1 error)

### 4.1 Access

**Nginx → access.json.log:**

```json
{"time":"2025-08-25T12:34:56+07:00","ts":1692946496.123,
 "remote":"10.0.2.15","host":"web1.local","hostname":"web1",
 "method":"GET","path":"/login","status":404,"bytes":0,"rt":0.003,
 "ua":"curl/8.0.1","referer":"-"}
```

**Flume → Kafka:** body = JSON trên.
**Spark (sau parse):** cột `event_time=2025-08-25T05:34:56Z`, `hostname=web1`, `status_class=4xx`, …
**Spark aggregate (10s window):** ví dụ `count=15`, `rps=1.5`, `avg_rt=0.012`, `err_rate=0.60`.
**Influx line protocol (`http_stats`):**

```
http_stats,env=dev,hostname=web1,method=GET,status_class=4xx count=15i,rps=1.5,avg_rt=0.012,max_rt=0.085,err_rate=0.60 1692946500000000000
```

**Influx line protocol (`top_urls` ví dụ /login):**

```
top_urls,env=dev,hostname=web1,status=404,path=/login count=15i 1692946500000000000
```

### 4.2 Error

**Nginx → error.log (text):**

```
2025/08/25 12:35:01 [error] 24#24: *127 connect() failed (111: Connection refused) while connecting to upstream, client: 192.168.1.10, server: _, request: "GET /api HTTP/1.1", upstream: "http://10.0.0.5:8080/api", host: "web1"
```

**Flume → Kafka:** body = text trên.
**Spark parse → JSON chuẩn hoá:** như ví dụ ở mục 1.2.
**Aggregate (10s window):** `hostname=web1, level=error, upstream=http://10.0.0.5:8080/api, count=1`.
**Influx line protocol (`error_events`):**

```
error_events,env=dev,hostname=web1,level=error,upstream=http://10.0.0.5:8080/api count=1i 1692946500000000000
```

---

## 5) Chất lượng dữ liệu & Vận hành

* **Time & timezone:** chuẩn hoá `event_time` về UTC trong Spark (dùng `ts` càng tốt).
* **Late data:** watermark 2 phút; sự kiện trễ hơn bị bỏ. Điều chỉnh nếu cần.
* **Log rotate:** Flume TAILDIR + `positionFile` trên volume bền → không mất log.
* **Backpressure:** chỉnh `KafkaSink` (`linger.ms`, batch size) và Spark trigger.
* **Cardinality:**

  * Không dùng `path` làm tag ở `http_stats`.
  * `top_urls` chỉ ghi Top-N.
  * Cân nhắc `ip` là field ở `anomaly` nếu số IP lớn.
* **Exactly-once:** pipeline ở mức **at-least-once**; aggregate cửa sổ giúp giảm ảnh hưởng trùng lặp nhỏ.

---

## 6) Phác thảo cấu hình Flume (đọc cả access & error)

```properties
a1.sources = r1
a1.channels = c1
a1.sinks   = k1

a1.sources.r1.type = TAILDIR
a1.sources.r1.positionFile = /var/log/flume/taildir_pos.json
a1.sources.r1.filegroups = f_access f_error
a1.sources.r1.filegroups.f_access = /var/log/nginx/access*.json.log
a1.sources.r1.headers.f_access.type = access
a1.sources.r1.filegroups.f_error  = /var/log/nginx/error.log
a1.sources.r1.headers.f_error.type = error
a1.sources.r1.headers.host = web01

a1.channels.c1.type = file
a1.channels.c1.checkpointDir = /var/lib/flume/checkpoint
a1.channels.c1.dataDirs = /var/lib/flume/data

a1.sinks.k1.type = org.apache.flume.sink.kafka.KafkaSink
a1.sinks.k1.kafka.bootstrap.servers = kafka:9092
a1.sinks.k1.kafka.topic = web-logs     # hoặc route sang web-errors với selector
a1.sinks.k1.kafka.flumeBatchSize = 200
a1.sinks.k1.kafka.producer.acks = 1

a1.sources.r1.channels = c1
a1.sinks.k1.channel = c1
```

*(Tuỳ chọn route 2 topic: dùng `selector.type = multiplexing` theo header `type`.)*

---

## 7) Spark — ý tưởng triển khai

* **Access stream**:

  * `from_json` schema → `withWatermark("event_time","2 minutes")` → window 10s
  * `groupBy(window, hostname, method, status_class)` → metrics
  * Tính Top-N URL: window + `groupBy(hostname, status, path)` rồi `orderBy(count)` + `limit` theo batch
  * Ghi Influx: dùng Influx client/HTTP trong `foreachBatch`

* **Error stream**:

  * `regexp_extract` nhiều cột → cast `event_time`
  * window 10s + watermark 2m → `groupBy(hostname, level, upstream)`
  * Ghi `error_events`; (rất hạn chế) ghi `error_samples` nếu cần

---

### Kết luận

* **Access log**: JSON 1 dòng (tại Nginx) → parse nhẹ, aggregate nhanh, gửi metrics/anomaly vào Influx.
* **Error log**: text thô → Spark parse/chuẩn hoá JSON → aggregate theo `level/upstream` → Influx.
* **Grafana**: vẽ đủ RPS, % lỗi, latency, Top URL, Error by level/upstream, anomaly.