FROM bitnami/spark:3.5.0

# Cài libsnappy-dev để fix lỗi Snappy compression
USER root
RUN apt-get update && apt-get install -y libsnappy-dev && apt-get clean && rm -rf /var/lib/apt/lists/*
USER 1001

# Set HOME tuyệt đối cho Ivy để tránh lỗi
ENV HOME=/tmp
ENV IVY_HOME=$HOME/.ivy2
RUN mkdir -p $IVY_HOME

# Cài Python packages
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# Copy source code & config
COPY src/ /opt/spark/app/src/
COPY conf/app.yaml /opt/spark/app/conf/app.yaml
COPY conf/spark-defaults.conf /opt/bitnami/spark/conf/spark-defaults.conf

# Prefetch Kafka connector packages để tránh tải lâu khi spark-submit
ENV SPARK_PACKAGES=org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.0
RUN bash -lc "echo 'print(1)' > /tmp/warmup.py && /opt/bitnami/spark/bin/spark-submit --master local --conf spark.jars.ivy=/tmp/.ivy2 --packages ${SPARK_PACKAGES} /tmp/warmup.py || true && rm -f /tmp/warmup.py"

# Set workdir
WORKDIR /opt/spark/app

# Đặt Spark master URL mặc định để test pyspark
ENV SPARK_MASTER_URL=spark://spark-master:7077
