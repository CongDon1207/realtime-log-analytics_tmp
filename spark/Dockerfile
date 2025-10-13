FROM bitnamilegacy/spark:3.5.0

# Cài libsnappy-dev để fix lỗi Snappy compression
USER root
RUN apt-get update && apt-get install -y libsnappy-dev && apt-get clean && rm -rf /var/lib/apt/lists/*
USER 1001

# Set HOME tuyệt đối cho Ivy để tránh lỗi
ENV HOME=/tmp
ENV IVY_HOME=$HOME/.ivy2
RUN mkdir -p $IVY_HOME

# ================================
# Cài Python packages
# ================================
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# ================================
# Copy Kafka connector jars + deps
# Spark 3.5.0 + Scala 2.12 => cần 4 file jar
# ================================
ADD https://repo1.maven.org/maven2/org/apache/spark/spark-sql-kafka-0-10_2.12/3.5.0/spark-sql-kafka-0-10_2.12-3.5.0.jar /opt/bitnami/spark/jars/
ADD https://repo1.maven.org/maven2/org/apache/spark/spark-token-provider-kafka-0-10_2.12/3.5.0/spark-token-provider-kafka-0-10_2.12-3.5.0.jar /opt/bitnami/spark/jars/
ADD https://repo1.maven.org/maven2/org/apache/kafka/kafka-clients/3.5.1/kafka-clients-3.5.1.jar /opt/bitnami/spark/jars/
ADD https://repo1.maven.org/maven2/org/apache/commons/commons-pool2/2.11.1/commons-pool2-2.11.1.jar /opt/bitnami/spark/jars/

# ================================
# Copy source code & config
# ================================
COPY src/ /opt/spark/app/src/
COPY conf/app.yaml /opt/spark/app/conf/app.yaml
COPY conf/spark-defaults.conf /opt/bitnami/spark/conf/spark-defaults.conf

# Prefetch Kafka connector packages để tránh tải lâu khi spark-submit
ENV SPARK_PACKAGES=org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.0
RUN bash -lc "echo 'print(1)' > /tmp/warmup.py && /opt/bitnami/spark/bin/spark-submit --master local --conf spark.jars.ivy=/tmp/.ivy2 --packages ${SPARK_PACKAGES} /tmp/warmup.py || true && rm -f /tmp/warmup.py"

# ================================
# Workdir
# ================================
WORKDIR /opt/spark/app

# Đặt Spark master URL mặc định để test pyspark
ENV SPARK_MASTER_URL=spark://spark-master:7077
