import os
import sys
from typing import List

from pyspark.sql import SparkSession, functions as F


# Bảo đảm có thể import module cục bộ
CURR_DIR = os.path.dirname(os.path.abspath(__file__))
if CURR_DIR not in sys.path:
    sys.path.append(CURR_DIR)

from access_schema import ACCESS_RAW_SCHEMA, normalize_access_df  # noqa: E402

try:
    from influxdb_client import InfluxDBClient, WriteOptions
except Exception:  # client không có sẵn (chạy thử console)
    InfluxDBClient = None  # type: ignore
    WriteOptions = None  # type: ignore


def build_spark(app_name: str = "AccessStream") -> SparkSession:
    return SparkSession.builder.appName(app_name).getOrCreate()


def _parse_seconds(text: str) -> int:
    s = text.strip().lower()
    if s.endswith("seconds") or s.endswith("second"):
        return int(s.split()[0])
    if s.endswith("s") and s[:-1].isdigit():
        return int(s[:-1])
    if s.endswith("minutes") or s.endswith("minute"):
        return int(s.split()[0]) * 60
    if s.endswith("m") and s[:-1].isdigit():
        return int(s[:-1]) * 60
    try:
        return int(s)
    except Exception:
        return 10


def _escape_tag(v: str) -> str:
    return v.replace(",", "\\,").replace(" ", "\\ ").replace("=", "\\=")


def _write_influx(df, batch_id: int, measurement: str, tags: List[str], fields: List[str], ts_col: str):
    if df.rdd.isEmpty():
        return

    url = os.getenv("INFLUX_URL", "http://influxdb:8086")
    token = os.getenv("INFLUX_TOKEN", "")
    org = os.getenv("INFLUX_ORG", "primary")
    bucket = os.getenv("INFLUX_BUCKET", "logs")
    env_tag = os.getenv("ENV_TAG", "dev")

    df2 = df.withColumn("ts_ns", (F.col(ts_col).cast("long") * F.lit(1_000_000_000))) \
            .withColumn("env", F.lit(env_tag))

    cols = [*tags, *fields, "ts_ns"]
    selected = df2.select(*cols)

    lines: List[str] = []
    for r in selected.toLocalIterator():
        tag_part = [f"env={_escape_tag(r['env'])}"]
        for t in tags:
            if t == "env":
                continue
            val = r[t]
            if val is None:
                continue
            tag_part.append(f"{t}={_escape_tag(str(val))}")

        field_part = []
        for f in fields:
            val = r[f]
            if val is None:
                continue
            if isinstance(val, bool):
                field_part.append(f"{f}={(1 if val else 0)}i")
            elif isinstance(val, int):
                field_part.append(f"{f}={val}i")
            elif isinstance(val, float):
                field_part.append(f"{f}={val}")
            else:
                sv = str(val).replace("\\", "\\\\").replace("\"", "\\\"")
                field_part.append(f"{f}=\"{sv}\"")

        ts = int(r["ts_ns"]) if r["ts_ns"] is not None else None
        if not field_part or ts is None:
            continue
        lines.append(f"{measurement},{','.join(tag_part)} {','.join(field_part)} {ts}")

    if not lines:
        return

    if InfluxDBClient is None:
        print("\n".join(lines))
        return

    with InfluxDBClient(url=url, token=token, org=org) as client:
        write_api = client.write_api(write_options=WriteOptions(batch_size=500, flush_interval=1000))
        write_api.write(bucket=bucket, org=org, record=lines)


def main():
    # Kafka
    kafka_bootstrap = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka:9092")
    topic = os.getenv("KAFKA_TOPIC_ACCESS", "web-logs")
    starting = os.getenv("KAFKA_STARTING_OFFSETS", "latest")

    # Window & watermark
    win_str = os.getenv("WINDOW_DURATION", "10 seconds")
    watermark_str = os.getenv("WATERMARK", "2 minutes")
    win_s = _parse_seconds(win_str)

    # Checkpoints
    ckpt_root = os.getenv("CHECKPOINT_DIR", "/tmp/checkpoints")

    spark = build_spark()

    # 1) Đọc Kafka -> value (string)
    raw = (
        spark.readStream.format("kafka")
        .option("kafka.bootstrap.servers", kafka_bootstrap)
        .option("subscribe", topic)
        .option("startingOffsets", starting)
        .load()
    )

    # 2) Parse JSON theo schema tối thiểu
    parsed = raw.select(F.from_json(F.col("value").cast("string"), ACCESS_RAW_SCHEMA).alias("j")).select("j.*")

    # 3) Chuẩn hóa access
    access_df = normalize_access_df(parsed)

    # 4) Metrics — http_stats (hostname, method, window)
    stats = (
        access_df
        .withWatermark("event_time", watermark_str)
        .groupBy(F.window("event_time", win_str).alias("w"), F.col("hostname"), F.col("method"))
        .agg(
            F.count(F.lit(1)).alias("count"),
            F.avg("rt").alias("avg_rt"),
            F.max("rt").alias("max_rt"),
            F.sum(F.when((F.col("status") >= 400) & (F.col("status") <= 599), 1).otherwise(0)).alias("err_count"),
        )
        .withColumn("rps", F.col("count") / F.lit(win_s))
        .withColumn("err_rate", F.when(F.col("count") > 0, F.col("err_count") / F.col("count")).otherwise(F.lit(0.0)))
        .withColumn("window_end", F.col("w").getField("end"))
        .drop("w")
    )

    # 5) Top URLs (ghi hết; chọn Top-N ở Grafana)
    top_urls = (
        access_df
        .withWatermark("event_time", watermark_str)
        .groupBy(F.window("event_time", win_str).alias("w"), F.col("hostname"), F.col("status"), F.col("path"))
        .agg(F.count(F.lit(1)).alias("count"))
        .withColumn("window_end", F.col("w").getField("end"))
        .drop("w")
    )

    # 6) Anomalies
    ip_threshold = int(os.getenv("IP_SPIKE_THRESHOLD", "50"))
    scan_threshold = int(os.getenv("SCAN_DISTINCT_PATHS_THRESHOLD", "20"))
    err_rate_threshold = float(os.getenv("ERROR_RATE_THRESHOLD", os.getenv("THRESHOLD_ERROR_RATE", "0.1")))

    ip_spike = (
        access_df
        .withWatermark("event_time", watermark_str)
        .groupBy(F.window("event_time", win_str).alias("w"), F.col("hostname"), F.col("remote").alias("ip"))
        .agg(F.count(F.lit(1)).alias("count"))
        .where(F.col("count") >= F.lit(ip_threshold))
        .withColumn("kind", F.lit("ip_spike"))
        .withColumn("score", F.col("count") / F.lit(ip_threshold))
        .withColumn("window_end", F.col("w").getField("end"))
        .drop("w")
    )

    err_surge = (
        access_df
        .withWatermark("event_time", watermark_str)
        .groupBy(F.window("event_time", win_str).alias("w"), F.col("hostname"))
        .agg(
            F.count(F.lit(1)).alias("count"),
            F.sum(F.when((F.col("status") >= 500) & (F.col("status") <= 599), 1).otherwise(0)).alias("err5xx"),
        )
        .withColumn("err_rate", F.when(F.col("count") > 0, F.col("err5xx") / F.col("count")).otherwise(F.lit(0.0)))
        .where(F.col("err_rate") >= F.lit(err_rate_threshold))
        .withColumn("ip", F.lit(""))
        .withColumn("kind", F.lit("error_surge"))
        .withColumn("score", F.col("err_rate"))
        .withColumn("window_end", F.col("w").getField("end"))
        .select("hostname", "ip", "kind", "count", "score", "window_end")
    )

    scan = (
        access_df
        .withWatermark("event_time", watermark_str)
        .groupBy(F.window("event_time", win_str).alias("w"), F.col("hostname"), F.col("remote").alias("ip"))
        .agg(F.approx_count_distinct("path").alias("distinct_paths"))
        .where(F.col("distinct_paths") >= F.lit(scan_threshold))
        .withColumn("kind", F.lit("scan"))
        .withColumn("count", F.col("distinct_paths"))
        .withColumn("score", F.col("distinct_paths") / F.lit(scan_threshold))
        .withColumn("window_end", F.col("w").getField("end"))
        .select("hostname", "ip", "kind", "count", "score", "window_end")
    )

    anomalies = ip_spike.unionByName(err_surge).unionByName(scan)

    # 7) Ghi InfluxDB
    q_stats = (
        stats.writeStream
        .foreachBatch(lambda df, eid: _write_influx(
            df, eid,
            measurement="http_stats",
            tags=["env", "hostname", "method"],
            fields=["count", "rps", "avg_rt", "max_rt", "err_rate"],
            ts_col="window_end",
        ))
        .option("checkpointLocation", f"{ckpt_root}/stats")
        .outputMode("update")
        .start()
    )

    q_top = (
        top_urls.writeStream
        .foreachBatch(lambda df, eid: _write_influx(
            df, eid,
            measurement="top_urls",
            tags=["env", "hostname", "status", "path"],
            fields=["count"],
            ts_col="window_end",
        ))
        .option("checkpointLocation", f"{ckpt_root}/top_urls")
        .outputMode("update")
        .start()
    )

    q_anom = (
        anomalies.writeStream
        .foreachBatch(lambda df, eid: _write_influx(
            df, eid,
            measurement="anomaly",
            tags=["env", "hostname", "kind"],
            fields=["ip", "count", "score"],
            ts_col="window_end",
        ))
        .option("checkpointLocation", f"{ckpt_root}/anomaly")
        .outputMode("update")
        .start()
    )

    # Chờ query chính (các query khác chạy song song)
    q_stats.awaitTermination()


if __name__ == "__main__":
    main()

