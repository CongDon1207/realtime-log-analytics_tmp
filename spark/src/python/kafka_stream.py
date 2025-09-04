from pyspark.sql import SparkSession
from pyspark.sql.functions import col, from_json, regexp_extract
from pyspark.sql.types import StructType, StringType, IntegerType, DoubleType

if __name__ == "__main__":
    spark = (
        SparkSession.builder
        .appName("KafkaSparkStreaming")
        .master("spark://spark-master:7077")
        .config("spark.jars", "/opt/bitnami/spark/jars/spark-sql-kafka-0-10_2.12-3.5.0.jar,/opt/bitnami/spark/jars/kafka-clients-3.5.1.jar,/opt/bitnami/spark/jars/spark-token-provider-kafka-0-10_2.12-3.5.0.jar")
        .getOrCreate()
    )
    spark.sparkContext.setLogLevel("WARN")

    # Schema cho web-logs JSON
    logs_schema = StructType() \
        .add("time", StringType()) \
        .add("remote", StringType()) \
        .add("path", StringType()) \
        .add("status", IntegerType()) \
        .add("rt", DoubleType())

    # Đọc từ Kafka
    df = (
        spark.readStream
        .format("kafka")
        .option("kafka.bootstrap.servers", "kafka:9092")
        .option("subscribe", "web-logs,web-errors")
        .option("startingOffsets", "earliest")
        .load()
    )

    base = df.select(
        col("topic"),
        col("value").cast("string").alias("raw")
    )

    # -------------------
    # 1. Xử lý web-logs (JSON)
    # -------------------
    web_logs = (
        base.filter(col("topic") == "web-logs")
        .select(from_json(col("raw"), logs_schema).alias("data"))
        .select("data.*")
    )

    # -------------------
    # 2. Xử lý web-errors (Text -> JSON)
    # Regex ví dụ cho log Nginx error:
    # 2025/08/25 12:35:01 [error] 24#24: *127 connect() failed ... client: 192.168.1.10, ...
    # -------------------
    web_errors = base.filter(col("topic") == "web-errors")

    errors_parsed = web_errors.select(
        regexp_extract("raw", r"^(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2})", 1).alias("time"),
        regexp_extract("raw", r"\[(error|warn|info)\]", 1).alias("level"),
        regexp_extract("raw", r"client:\s([\d\.]+)", 1).alias("client_ip"),
        regexp_extract("raw", r"request:\s\"(.*?)\"", 1).alias("request"),
        regexp_extract("raw", r"upstream:\s\"(.*?)\"", 1).alias("upstream")
    )

    # -------------------
    # 3. In ra console
    # -------------------
    query_logs = (
        web_logs.writeStream
        .outputMode("append")
        .format("console")
        .option("truncate", "false")
        .queryName("WebLogs")
        .start()
    )

    query_errors = (
        errors_parsed.writeStream
        .outputMode("append")
        .format("console")
        .option("truncate", "false")
        .queryName("WebErrors")
        .start()
    )

    spark.streams.awaitAnyTermination()
