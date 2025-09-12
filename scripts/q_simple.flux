from(bucket: "logs")
  |> range(start: -30m)
  |> sort(columns: ["_time"], desc: true)
  |> limit(n: 10)
