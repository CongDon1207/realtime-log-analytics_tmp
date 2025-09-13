from pyspark.sql import DataFrame, functions as F
from pyspark.sql.types import StructType, StructField, StringType


# =========================
# Schema tối thiểu cho error log sau khi parse
# =========================
ERROR_RAW_SCHEMA = StructType([
    StructField("time", StringType(), True),      # "2025/08/25 12:35:01"
    StructField("hostname", StringType(), True),  # web1 / web2 ...
    StructField("level", StringType(), True),     # error / warn / notice
    StructField("message", StringType(), True),   # thông điệp lỗi gốc
])



# =========================
# Chuẩn hóa error log
# =========================
def normalize_error_df(df: DataFrame) -> DataFrame:
    """
    Chuẩn hóa DataFrame log lỗi:
      - event_time: timestamp (từ chuỗi 'time')
      - hostname, level, message giữ nguyên
    """
    return (
        df.withColumn("event_time", F.to_timestamp("time", "yyyy/MM/dd HH:mm:ss"))
          .select("hostname", "event_time", "level", "message")
    )


# =========================
# Phân loại message thành nhóm (message_class)
# =========================
def classify_message(df: DataFrame) -> DataFrame:
    """
    Gom message thành các class (nhóm lỗi phổ biến).
    - connect() failed -> connection_failed
    - timed out        -> timeout
    - not found        -> not_found
    - mặc định         -> other
    """
    return (
        df.withColumn(
            "message_class",
            F.when(F.col("message").rlike("connect\\(\\) failed"), "connection_failed")
             .when(F.col("message").rlike("timed out"), "timeout")
             .when(F.col("message").rlike("not found"), "not_found")
             .otherwise("other")
        )
    )


__all__ = ["ERROR_RAW_SCHEMA", "normalize_error_df", "classify_message"]
