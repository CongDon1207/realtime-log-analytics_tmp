FROM eclipse-temurin:8-jre-jammy

ARG FLUME_VER=1.11.0
ARG FLUME_TGZ=https://downloads.apache.org/flume/${FLUME_VER}/apache-flume-${FLUME_VER}-bin.tar.gz

RUN apt-get update && apt-get install -y curl ca-certificates tar && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /opt \
 && curl -fsSL "${FLUME_TGZ}" -o /tmp/flume.tgz \
 && tar -xzf /tmp/flume.tgz -C /opt \
 && ln -s /opt/apache-flume-${FLUME_VER}-bin /opt/flume \
 && rm -f /tmp/flume.tgz

ENV FLUME_HOME=/opt/flume
ENV PATH="${FLUME_HOME}/bin:${PATH}"
WORKDIR /opt/flume

# Mặc định in version; docker-compose sẽ override bằng 'flume-ng agent ...'
CMD ["flume-ng","version"]
