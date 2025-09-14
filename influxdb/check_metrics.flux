// check_metrics.flux - Kiểm tra metrics đã được ghi vào InfluxDB
// Sử dụng bucket "logs" theo cấu hình .env

bucketName = "logs"

// 1) Kiểm tra measurements có sẵn
import "influxdata/influxdb/schema"
schema.measurements(bucket: bucketName)
  |> yield(name: "available_measurements")

// 2) Dữ liệu mới nhất (10 dòng cuối)
from(bucket: bucketName)
  |> range(start: -1h)
  |> sort(columns: ["_time"], desc: true)
  |> limit(n: 10)
  |> yield(name: "latest_data")

// 3) Kiểm tra http_stats (nếu có)
from(bucket: bucketName)
  |> range(start: -30m)
  |> filter(fn: (r) => r._measurement == "http_stats")
  |> limit(n: 5)
  |> yield(name: "http_stats_sample")

// 4) Kiểm tra top_urls (nếu có)
from(bucket: bucketName)
  |> range(start: -30m)
  |> filter(fn: (r) => r._measurement == "top_urls")
  |> limit(n: 5)
  |> yield(name: "top_urls_sample")

// 5) Kiểm tra anomaly (nếu có)
from(bucket: bucketName)
  |> range(start: -30m)
  |> filter(fn: (r) => r._measurement == "anomaly")
  |> limit(n: 5)
  |> yield(name: "anomaly_sample")

// 6) Tổng số records theo measurement
from(bucket: bucketName)
  |> range(start: -1h)
  |> group(columns: ["_measurement"])
  |> count()
  |> group()
  |> yield(name: "record_counts")
