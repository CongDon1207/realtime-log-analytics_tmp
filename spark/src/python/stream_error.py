import os
import sys
from typing import List

from pyspark.sql import SparkSession, functions as F
from pyspark.sql.types import StructType, StructField, StringType, TimestampType

# =========================
# Local schema & utils
# =========================
CURR_DIR = os.path.dirname(os.path.abspath(__file__))
if CURR_DIR not in sys.path:
    sys.path.append(CURR_DIR)

from error_schema import ERROR_RAW_SCHEMA, normalize_error_df, classify_message  # noqa: E402

# =========================
# InfluxDB setup
# =========================
try:
    from influxdb_client import InfluxDBClient, WriteOptions
    try:
        from influxdb_client.client.write_api import SYNCHRONOUS
    except Exception:
        SYNCHRONOUS = None
except Exception:
    InfluxDBClient = None
    WriteOptions = None


def build_spark(app_name: str = "ErrorStream") -> SparkSession:
    return (
        SparkSession.builder.appName(app_name)
        .config("spark.io.compression.codec", "lz4")
        .config("spark.shuffle.mapStatus.compression.codec", "lz4")
        .getOrCreate()
    )


def _escape_tag(v: str) -> str:
    return v.replace(",", "\\,").replace(" ", "\\ ").replace("=", "\\=")


def _write_influx(df, batch_id: int, measurement: str, tags: List[str], fields: List[str], ts_col: str):
    try:
        if df.rdd.isEmpty():
            return
    except Exception as e:
        print(f"Warning: Cannot check DataFrame.isEmpty(): {e}")

    url = os.getenv("INFLUX_URL", "http://influxdb:8086")
    token = os.getenv("INFLUX_TOKEN", "")
    org = os.getenv("INFLUX_ORG", "primary")
    bucket = os.getenv("INFLUX_BUCKET", "logs")
    env_tag = os.getenv("ENV_TAG", "dev")

    df2 = (
        df.withColumn("ts_ns", (F.current_timestamp().cast("long") * F.lit(1_000_000_000)))
          .withColumn("env", F.lit(env_tag))
    )

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
            sval = str(val).strip()
            if not sval:
                continue
            tag_part.append(f"{t}={_escape_tag(sval)}")

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
        print(f"DEBUG: InfluxDB client not available, would write {len(lines)} lines")
        return

    with InfluxDBClient(url=url, token=token, org=org) as client:
        if 'SYNCHRONOUS' in globals() and SYNCHRONOUS is not None:
            write_api = client.write_api(write_options=SYNCHRONOUS)
        elif WriteOptions is not None:
            write_api = client.write_api(write_options=WriteOptions(batch_size=500, flush_interval=1000))
        else:
            write_api = client.write_api()
        write_api.write(bucket=bucket, org=org, record=lines)
        print(f"SUCCESS: Wrote {len(lines)} lines to InfluxDB measurement '{measurement}'")


def main():
    kafka_bootstrap = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka:9092")
    topic = os.getenv("KAFKA_TOPIC_ERROR", "web-errors")
    starting = os.getenv("KAFKA_STARTING_OFFSETS", "earliest")

    win_str = os.getenv("WINDOW_DURATION", "10 seconds")
    watermark_str = os.getenv("WATERMARK", "2 minutes")
    ckpt_root = os.getenv("CHECKPOINT_DIR_ERROR", "/tmp/checkpoints_error")

    spark = build_spark()

    # 1) Đọc Kafka (raw text)
    raw = (
        spark.readStream.format("kafka")
        .option("kafka.bootstrap.servers", kafka_bootstrap)
        .option("subscribe", topic)
        .option("startingOffsets", starting)
        .option("failOnDataLoss", "false")
        .load()
    )
    lines = raw.selectExpr("CAST(value AS STRING) as line")

    # 2) Regex parse log text
    df_regex = (
        lines.withColumn("time", F.regexp_extract("line", r"^(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2})", 1))
        .withColumn("level", F.regexp_extract("line", r"\[(\w+)\]", 1))
        .withColumn("hostname", F.regexp_extract("line", r'host: "([^"]+)"', 1))
        .withColumn("message", F.regexp_extract("line", r"\d+#\d+: \*\d+ (.+?), host: .*", 1))
        .withColumn("event_time", F.to_timestamp("time", "yyyy/MM/dd HH:mm:ss"))   # <--- thêm dòng này
    )

    # 3) to_json → from_json (áp schema ERROR_RAW_SCHEMA)
    df_json = df_regex.select(F.to_json(F.struct("*")).alias("json_str"))
    parsed = df_json.select(F.from_json("json_str", ERROR_RAW_SCHEMA).alias("j")).select("j.*")

    # 4) Chuẩn hóa + classify
    error_df = normalize_error_df(parsed)
    error_df = classify_message(error_df)

    # 5) error_events (group by window)
    error_events = (
        error_df.withWatermark("event_time", watermark_str)
        .groupBy(
            F.window("event_time", win_str).alias("w"),
            "hostname", "level", "message_class"
        )
        .agg(F.count(F.lit(1)).alias("count"))
        .withColumn("window_end", F.col("w").getField("end"))
        .drop("w")
    )

    # 6) Xuất ra console (JSON log chi tiết)
    q_console = (
        error_df.select(F.to_json(F.struct("hostname", "event_time", "level", "message", "message_class")).alias("json"))
        .writeStream
        .format("console")
        .option("truncate", False)
        .outputMode("append")
        .start()
    )

    # 7) Write InfluxDB (error_events)
    q_err = (
        error_events.writeStream
        .foreachBatch(lambda df, eid: _write_influx(
            df, eid,
            measurement="error_events",
            tags=["env", "hostname", "level", "message_class"],
            fields=["count"],
            ts_col="window_end",
        ))
        .option("checkpointLocation", f"{ckpt_root}/error_events")
        .outputMode("update")
        .start()
    )

    spark.streams.awaitAnyTermination()


if __name__ == "__main__":
    main()
