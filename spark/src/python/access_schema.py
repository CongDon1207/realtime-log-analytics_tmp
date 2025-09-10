from pyspark.sql import functions as F
from pyspark.sql.types import (
    StructType,
    StructField,
    StringType,
    IntegerType,
    LongType,
    DoubleType,
)


# Schema ACCESS thô (tối thiểu) theo docs/data-flow.md
# - Chỉ giữ các trường cần cho metrics và phát hiện bất thường về sau
# - Các trường đều optional (nullable) để chịu được dữ liệu thiếu
ACCESS_RAW_SCHEMA = StructType(
    [
        StructField("time", StringType(), True),       # ISO8601 có offset, ví dụ 2025-08-25T12:34:56+07:00
        StructField("ts", DoubleType(), True),         # epoch seconds (float)
        StructField("remote", StringType(), True),     # IP client
        StructField("hostname", StringType(), True),   # tên máy nguồn log (web1/web2/...)
        StructField("method", StringType(), True),     # GET/POST/...
        StructField("path", StringType(), True),       # URI path (không gồm query)
        StructField("status", IntegerType(), True),    # 200/404/500
        StructField("bytes", LongType(), True),        # body_bytes_sent
        StructField("rt", DoubleType(), True),         # request_time (giây)
    ]
)


def normalize_access_df(df):
    """Chuẩn hóa access logs về schema tối thiểu phục vụ metrics.

    Đầu vào:
        df: DataFrame đã đọc từ JSON (file/Kafka) với các cột theo ACCESS_RAW_SCHEMA.

    Đầu ra: DataFrame với các cột đã chuẩn hóa và ép kiểu:
        - event_time: timestamp (ưu tiên `time`, fallback `ts`)
        - hostname: string
        - method: string
        - path: string
        - status: int
        - status_class: string (2xx|3xx|4xx|5xx|other)
        - remote: string
        - bytes: long
        - rt: double
    """

    # Ép kiểu tối thiểu (idempotent nếu đã đúng kiểu)
    base = (
        df.select(
            F.col("time").cast("string").alias("time"),
            F.col("ts").cast("double").alias("ts"),
            F.col("remote").cast("string").alias("remote"),
            F.col("hostname").cast("string").alias("hostname"),
            F.col("method").cast("string").alias("method"),
            F.col("path").cast("string").alias("path"),
            F.col("status").cast("int").alias("status"),
            F.col("bytes").cast("long").alias("bytes"),
            F.col("rt").cast("double").alias("rt"),
        )
    )

    # event_time: ưu tiên parse ISO8601 trong `time`, fallback từ epoch `ts`
    event_time = F.coalesce(
        F.to_timestamp(F.col("time")),
        F.to_timestamp(F.from_unixtime(F.col("ts"))),
    )

    status_class = (
        F.when((F.col("status") >= 200) & (F.col("status") <= 299), F.lit("2xx"))
        .when((F.col("status") >= 300) & (F.col("status") <= 399), F.lit("3xx"))
        .when((F.col("status") >= 400) & (F.col("status") <= 499), F.lit("4xx"))
        .when((F.col("status") >= 500) & (F.col("status") <= 599), F.lit("5xx"))
        .otherwise(F.lit("other"))
    )

    normalized = (
        base.withColumn("event_time", event_time)
        .withColumn("status_class", status_class)
        .select(
            "event_time",
            "hostname",
            "method",
            "path",
            "status",
            "status_class",
            "remote",
            "bytes",
            "rt",
        )
    )

    return normalized


__all__ = ["ACCESS_RAW_SCHEMA", "normalize_access_df"]

