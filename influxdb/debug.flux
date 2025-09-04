// debug.flux — dò nhanh dữ liệu measurement `http_requests`
// Thay 'http-logs' nếu bucket của bạn khác
import "influxdata/influxdb/schema"

bucketName = "http-logs"

// 0) 20 dòng mới nhất (30 phút gần đây)
from(bucket: bucketName)
  |> range(start: -30m)
  |> filter(fn: (r) => r._measurement == "http_requests")
  |> sort(columns: ["_time"], desc: true)
  |> limit(n: 10)
  |> yield(name: "latest_rows")

// 1) Tổng request mỗi 10s đúng theo cửa sổ Spark (để sanity check)
from(bucket: bucketName)
  |> range(start: -30m)
  |> filter(fn: (r) => r._measurement == "http_requests" and r._field == "count")
  |> aggregateWindow(every: 10s, fn: sum, createEmpty: false)
  |> group(columns: ["_time"])
  |> sum(column: "_value")
  |> set(key: "_field", value: "total_count_10s")
  |> yield(name: "total_count_10s")

// 2) RPS theo status_class (gộp 1 phút)
from(bucket: bucketName)
  |> range(start: -30m)
  |> filter(fn: (r) => r._measurement == "http_requests" and r._field == "rps")
  |> group(columns: ["status_class"])
  |> aggregateWindow(every: 1m, fn: sum, createEmpty: false)
  |> yield(name: "rps_by_status_1m")

// 3) Top host theo tổng RPS (30 phút)
from(bucket: bucketName)
  |> range(start: -30m)
  |> filter(fn: (r) => r._measurement == "http_requests" and r._field == "rps")
  |> group(columns: ["hostname"])
  |> sum()
  |> sort(columns: ["_value"], desc: true)
  |> limit(n: 10)
  |> yield(name: "top_hosts_by_rps")

// 4) p95 latency (dùng max_rt làm proxy) theo host (30 phút)
from(bucket: bucketName)
  |> range(start: -30m)
  |> filter(fn: (r) => r._measurement == "http_requests" and r._field == "max_rt")
  |> group(columns: ["hostname"])
  |> quantile(q: 0.95, method: "estimate_tdigest")
  |> yield(name: "latency_p95_by_host")
