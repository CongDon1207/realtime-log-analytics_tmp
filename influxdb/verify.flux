// verify.flux — báo cáo xác minh pipeline `http_requests`
// Thay 'logs' theo bucket đã cấu hình
bucketName = "logs"

// A) Tổng RPS 1 phút
rps_total_1m = from(bucket: bucketName)
  |> range(start: -30m)
  |> filter(fn: (r) => r._measurement == "http_requests" and r._field == "rps")
  |> aggregateWindow(every: 1m, fn: sum, createEmpty: false)
  |> group(columns: ["_time"])
  |> sum(column: "_value")
  |> set(key: "_field", value: "rps_total")
rps_total_1m |> yield(name: "rps_total_1m")

// B) Error rate = (4xx + 5xx) / total (theo phút)
totals_1m = from(bucket: bucketName)
  |> range(start: -30m)
  |> filter(fn: (r) => r._measurement == "http_requests" and r._field == "count")
  |> aggregateWindow(every: 1m, fn: sum, createEmpty: false)
  |> group(columns: ["_time"])
  |> sum(column: "_value")

errors_1m = from(bucket: bucketName)
  |> range(start: -30m)
  |> filter(fn: (r) => r._measurement == "http_requests" and r._field == "count" and (r.status_class == "4xx" or r.status_class == "5xx"))
  |> aggregateWindow(every: 1m, fn: sum, createEmpty: false)
  |> group(columns: ["_time"])
  |> sum(column: "_value")

join(tables: {t: totals_1m, e: errors_1m}, on: ["_time"])
  |> map(fn: (r) => ({ r with _value: if r._value_t == 0.0 then 0.0 else float(v: r._value_e) / float(v: r._value_t) }))
  |> set(key: "_field", value: "error_rate")
  |> yield(name: "error_rate_1m")

// C) p95/p99 latency 30 phút qua (dùng max_rt làm proxy) theo host
from(bucket: bucketName)
  |> range(start: -30m)
  |> filter(fn: (r) => r._measurement == "http_requests" and r._field == "max_rt")
  |> group(columns: ["hostname"])
  |> quantile(q: 0.95, method: "estimate_tdigest")
  |> yield(name: "p95_max_rt_by_host")

from(bucket: bucketName)
  |> range(start: -30m)
  |> filter(fn: (r) => r._measurement == "http_requests" and r._field == "max_rt")
  |> group(columns: ["hostname"])
  |> quantile(q: 0.99, method: "estimate_tdigest")
  |> yield(name: "p99_max_rt_by_host")

// D) Bảng tổng hợp 5 phút gần nhất: tổng RPS và error-rate
rps_5m = from(bucket: bucketName)
  |> range(start: -5m)
  |> filter(fn: (r) => r._measurement == "http_requests" and r._field == "rps")
  |> sum()

cnt_5m = from(bucket: bucketName)
  |> range(start: -5m)
  |> filter(fn: (r) => r._measurement == "http_requests" and r._field == "count")
  |> sum()

cnt5xx_5m = from(bucket: bucketName)
  |> range(start: -5m)
  |> filter(fn: (r) => r._measurement == "http_requests" and r._field == "count" and r.status_class == "5xx")
  |> sum()

// Đơn giản hóa - tổng hợp tất cả metrics cho 5 phút
rps_5m 
  |> group()
  |> sum()
  |> map(fn: (r) => ({ _time: r._stop, metric: "rps_total_5m", value: r._value }))
  |> yield(name: "rps_summary_5m")

cnt_5m
  |> group()
  |> sum()
  |> map(fn: (r) => ({ _time: r._stop, metric: "total_requests_5m", value: r._value }))
  |> yield(name: "count_summary_5m")

cnt5xx_5m
  |> group()
  |> sum()
  |> map(fn: (r) => ({ _time: r._stop, metric: "error_requests_5m", value: r._value }))
  |> yield(name: "error_summary_5m")
