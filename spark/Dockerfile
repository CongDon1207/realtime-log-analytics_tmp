FROM bitnami/spark:3.5.0

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

# Set workdir
WORKDIR /opt/spark/app

# Đặt Spark master URL mặc định để test pyspark
ENV SPARK_MASTER_URL=spark://spark-master:7077