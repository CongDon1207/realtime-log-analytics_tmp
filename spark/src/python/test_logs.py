from pyspark.sql import SparkSession
from pyspark.sql.types import StructType, StructField, StringType

spark = SparkSession.builder.appName("TestLogs").getOrCreate()

# Schema cho access log (JSON)
schema = StructType([
    StructField("ip", StringType(), True),
    StructField("message", StringType(), True)
])

# --- Đọc access.log (JSON) ---
df_access = spark.read.json("/opt/spark/app/src/logs/access.log", schema=schema)
print("=== Access Logs ===")
df_access.show(truncate=False)

# --- Đọc error.log (plain text) ---
df_error = spark.read.text("/opt/spark/app/src/logs/error.log")
print("=== Error Logs ===")
df_error.show(truncate=False)

spark.stop()
