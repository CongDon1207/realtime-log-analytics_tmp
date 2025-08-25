// Điều chỉnh cửa sổ nhìn lại ở đây:
lookback = 1h

// =============================
// (A) RPS theo 1 phút (sum(count))
// =============================
from(bucket: "http-logs")
  |> range(start: -lookback)
  |> filter(fn: (r) => r._measurement == "http_requests")
  |> filter(fn: (r) => r._field == "count")
  |> aggregateWindow(every: 1m, fn: sum, createEmpty: false)
  |> yield(name: "rps_1m")

// =============================
// (B) %2xx / %4xx / %5xx theo 1 phút (không cần import)
// =============================
base =
  from(bucket: "http-logs")
    |> range(start: -lookback)
    |> filter(fn: (r) => r._measurement == "http_requests")
    |> filter(fn: (r) => r._field == "count")
    |> aggregateWindow(every: 1m, fn: sum, createEmpty: true)

cls2 =
  base
    |> filter(fn: (r) => r.status =~ /^2.*/)
    |> group(columns: ["_time"])
    |> sum(column: "_value")
    |> map(fn: (r) => ({ _time: r._time, _value: r._value, cls: "2xx" }))

cls4 =
  base
    |> filter(fn: (r) => r.status =~ /^4.*/)
    |> group(columns: ["_time"])
    |> sum(column: "_value")
    |> map(fn: (r) => ({ _time: r._time, _value: r._value, cls: "4xx" }))

cls5 =
  base
    |> filter(fn: (r) => r.status =~ /^5.*/)
    |> group(columns: ["_time"])
    |> sum(column: "_value")
    |> map(fn: (r) => ({ _time: r._time, _value: r._value, cls: "5xx" }))

pct =
  union(tables: [cls2, cls4, cls5])
    |> group(columns: ["_time", "cls"])
    |> sum(column: "_value")
    |> pivot(rowKey: ["_time"], columnKey: ["cls"], valueColumn: "_value")
    |> map(fn: (r) => ({
        r with
        xx2: if exists r["2xx"] then float(v: r["2xx"]) else 0.0,
        xx4: if exists r["4xx"] then float(v: r["4xx"]) else 0.0,
        xx5: if exists r["5xx"] then float(v: r["5xx"]) else 0.0
    }))
    |> map(fn: (r) => ({ r with total: r.xx2 + r.xx4 + r.xx5 }))
    |> map(fn: (r) => ({
        r with
        pct_2xx: if r.total > 0.0 then r.xx2 / r.total * 100.0 else 0.0,
        pct_4xx: if r.total > 0.0 then r.xx4 / r.total * 100.0 else 0.0,
        pct_5xx: if r.total > 0.0 then r.xx5 / r.total * 100.0 else 0.0
    }))
    |> keep(columns: ["_time", "pct_2xx", "pct_4xx", "pct_5xx"])

pct |> yield(name: "status_pct")

// =============================
// (C) p95 latency_ms (cửa sổ 1 phút)
// =============================
from(bucket: "http-logs")
  |> range(start: -lookback)
  |> filter(fn: (r) => r._measurement == "http_requests")
  |> filter(fn: (r) => r._field == "latency_ms")
  |> window(every: 1m)
  |> quantile(q: 0.95, method: "estimate_tdigest")
  |> duplicate(column: "_stop", as: "_time")
  |> window(every: inf)
  |> keep(columns: ["_time", "_value", "_field", "_measurement"])
  |> rename(columns: {_value: "p95_latency_ms"})
  |> yield(name: "latency_p95_1m")
