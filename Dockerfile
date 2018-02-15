FROM debian as compile-lkd
MAINTAINER Marios Andreopoulos <marios@landoop.com>

RUN apt-get update \
    && apt-get install -y \
         wget \
    && rm -rf /var/lib/apt/lists/* \
    && echo "progress = dot:giga" | tee /etc/wgetrc \
    && mkdir -p /mnt /opt /data \
    && wget https://github.com/andmarios/duphard/releases/download/v1.0/duphard -O /bin/duphard \
    && chmod +x /bin/duphard

SHELL ["/bin/bash", "-c"]
WORKDIR /

# Login args for development archives
ARG DEVARCH_USER=${DEVARCH_USER:-}
ARG DEVARCH_PASS=${DEVARCH_PASS:-}
ARG LKD_VERSION=${LKD_VERSION:-1.0.0-r0}

############
# Add kafka/
############

# Add Apache Kafka (includes Connect and Zookeeper)
ARG KAFKA_VERSION="${KAFKA_VERSION:-1.0.0}"
ARG KAFKA_LVERSION="${KAFKA_LVERSION:-${KAFKA_VERSION}-L1}"
ARG KAFKA_URL="${KAFKA_URL:-https://archive.landoop.com/lkd/packages/kafka_2.11-${KAFKA_LVERSION}-lkd.tar.gz}"

RUN wget $DEVARCH_USER $DEVARCH_PASS "$KAFKA_URL" -O /opt/kafka.tar.gz \
    && tar --no-same-owner -xzf /opt/kafka.tar.gz -C /opt \
    && mkdir /opt/landoop/kafka/logs && chmod 1777 /opt/landoop/kafka/logs \
    && rm -rf /opt/kafka.tar.gz

# Add Schema Registry and REST Proxy
ARG REGISTRY_VERSION="${REGISTRY_VERSION:-4.0.0-lkd}"
ARG REGISTRY_URL="${REGISTRY_URL:-https://archive.landoop.com/lkd/packages/schema_registry_${REGISTRY_VERSION}.tar.gz}"
RUN wget $DEVARCH_USER $DEVARCH_PASS "$REGISTRY_URL" -O /opt/registry.tar.gz \
    && tar --no-same-owner -xzf /opt/registry.tar.gz -C /opt/ \
    && rm -rf /opt/registry.tar.gz

ARG REST_VERSION="${REST_VERSION:-4.0.0-lkd}"
ARG REST_URL="${REST_URL:-https://archive.landoop.com/lkd/packages/rest_proxy_${REST_VERSION}.tar.gz}"
RUN wget $DEVARCH_USER $DEVARCH_PASS "$REST_URL" -O /opt/rest.tar.gz \
    && tar --no-same-owner -xzf /opt/rest.tar.gz -C /opt/ \
    && rm -rf /opt/rest.tar.gz

# Configure Connect and Confluent Components to support CORS
RUN echo -e 'access.control.allow.methods=GET,POST,PUT,DELETE,OPTIONS\naccess.control.allow.origin=*' \
         | tee -a /opt/landoop/kafka/etc/schema-registry/schema-registry.properties \
         | tee -a /opt/landoop/kafka/etc/kafka-rest/kafka-rest.properties \
         | tee -a /opt/landoop/kafka/etc/schema-registry/connect-avro-distributed.properties


#################
# Add connectors/
#################

# Add Stream Reactor and needed components
ARG STREAM_REACTOR_VERSION="${STREAM_REACTOR_VERSION:-1.0.0}"
ARG STREAM_REACTOR_URL="${STREAM_REACTOR_URL:-https://archive.landoop.com/stream-reactor/stream-reactor-${STREAM_REACTOR_VERSION}_connect${KAFKA_VERSION}.tar.gz}"
ARG ELASTICSEARCH_2X_VERSION="${ELASTICSEARCH_2X_VERSION:-2.4.6}"
ARG ACTIVEMQ_VERSION="${ACTIVEMQ_VERSION:-5.12.3}"
ARG CALCITE_LINQ4J_VERSION="${CALCITE_LINQ4J_VERSION:-1.12.0}"

RUN wget "${STREAM_REACTOR_URL}" -O /stream-reactor.tar.gz \
    && mkdir -p /opt/landoop/connectors/stream-reactor \
    && tar -xf /stream-reactor.tar.gz \
           --no-same-owner \
           --strip-components=1 \
           -C /opt/landoop/connectors/stream-reactor \
    && rm /stream-reactor.tar.gz \
    && wget https://download.elastic.co/elasticsearch/release/org/elasticsearch/distribution/tar/elasticsearch/${ELASTICSEARCH_2X_VERSION}/elasticsearch-${ELASTICSEARCH_2X_VERSION}.tar.gz \
            -O /elasticsearch.tar.gz \
    && mkdir /elasticsearch \
    && tar -xf /elasticsearch.tar.gz \
           --no-same-owner \
           --strip-components=1 \
           -C /elasticsearch \
    && mv /elasticsearch/lib/*.jar /opt/landoop/connectors/stream-reactor/kafka-connect-elastic/ \
    && rm -rf /elasticsearch* \
    && wget http://central.maven.org/maven2/org/apache/activemq/activemq-all/${ACTIVEMQ_VERSION}/activemq-all-${ACTIVEMQ_VERSION}.jar \
            -P /opt/landoop/connectors/stream-reactor/kafka-connect-jms \
    && wget http://central.maven.org/maven2/org/apache/calcite/calcite-linq4j/${CALCITE_LINQ4J_VERSION}/calcite-linq4j-${CALCITE_LINQ4J_VERSION}.jar \
            -O /calcite-linq4j-${CALCITE_LINQ4J_VERSION}.jar \
    && for path in /opt/landoop/connectors/stream-reactor/kafka-connect-*; do \
          cp /calcite-linq4j-${CALCITE_LINQ4J_VERSION}.jar $path/; \
       done \
    && rm /calcite-linq4j-${CALCITE_LINQ4J_VERSION}.jar \
    && mkdir -p /opt/landoop/kafka/share/java/landoop-common \
    && for file in $(find /opt/landoop/connectors/stream-reactor -maxdepth 2 -type f -exec basename {} \; | sort | uniq -c | grep -E "^\s+20 " | awk '{print $2}' ); do \
         cp /opt/landoop/connectors/stream-reactor/kafka-connect-elastic/$file /opt/landoop/kafka/share/java/landoop-common/; \
         rm -f /opt/landoop/connectors/stream-reactor/kafka-connect-*/$file; \
       done \
    && echo "plugin.path=/opt/landoop/connectors/stream-reactor,/opt/landoop/connectors/third-party" \
            >> /opt/landoop/kafka/etc/schema-registry/connect-avro-distributed.properties

# Add Third Party Connectors

## Twitter
ARG TWITTER_CONNECTOR_URL="https://archive.landoop.com/third-party/kafka-connect-twitter/kafka-connect-twitter-0.1-master-33331ea-connect-1.0.0-jar-with-dependencies.jar"
RUN mkdir -p /opt/landoop/connectors/third-party/kafka-connect-twitter \
    && wget "$TWITTER_CONNECTOR_URL" -P /opt/landoop/connectors/third-party/kafka-connect-twitter

## Kafka Connect JDBC
ARG KAFKA_CONNECT_JDBC_VERSION="${KAFKA_CONNECT_JDBC_VERSION:-4.0.0-lkd}"
ARG KAFKA_CONNECT_JDBC_URL="${KAFKA_CONNECT_JDBC_URL:-https://archive.landoop.com/lkd/packages/kafka-connect-jdbc-${KAFKA_CONNECT_JDBC_VERSION}.tar.gz}"
RUN wget $DEVARCH_USER $DEVARCH_PASS "$KAFKA_CONNECT_JDBC_URL" \
         -O /opt/kafka-connect-jdbc.tar.gz \
    && mkdir -p /opt/landoop/connectors/third-party/ \
    && tar --no-same-owner -xf /opt/kafka-connect-jdbc.tar.gz \
           -C /opt/landoop/connectors/third-party/ \
    && rm -rf /opt/kafka-connect-jdbc.tar.gz

## Kafka Connect ELASTICSEARCH
ARG KAFKA_CONNECT_ELASTICSEARCH_VERSION="${KAFKA_CONNECT_ELASTICSEARCH_VERSION:-4.0.0-lkd}"
ARG KAFKA_CONNECT_ELASTICSEARCH_URL="${KAFKA_CONNECT_ELASTICSEARCH_URL:-https://archive.landoop.com/lkd/packages/kafka-connect-elasticsearch-${KAFKA_CONNECT_ELASTICSEARCH_VERSION}.tar.gz}"
RUN wget $DEVARCH_USER $DEVARCH_PASS "$KAFKA_CONNECT_ELASTICSEARCH_URL" \
         -O /opt/kafka-connect-elasticsearch.tar.gz \
    && mkdir -p /opt/landoop/connectors/third-party/ \
    && tar --no-same-owner -xf /opt/kafka-connect-elasticsearch.tar.gz \
           -C /opt/landoop/connectors/third-party/ \
    && rm -rf /opt/kafka-connect-elasticsearch.tar.gz

## Kafka Connect HDFS
ARG KAFKA_CONNECT_HDFS_VERSION="${KAFKA_CONNECT_HDFS_VERSION:-4.0.0-lkd}"
ARG KAFKA_CONNECT_HDFS_URL="${KAFKA_CONNECT_HDFS_URL:-https://archive.landoop.com/lkd/packages/kafka-connect-hdfs-${KAFKA_CONNECT_HDFS_VERSION}.tar.gz}"
RUN wget $DEVARCH_USER $DEVARCH_PASS "$KAFKA_CONNECT_HDFS_URL" \
         -O /opt/kafka-connect-hdfs.tar.gz \
    && mkdir -p /opt/landoop/connectors/third-party/ \
    && tar --no-same-owner -xf /opt/kafka-connect-hdfs.tar.gz \
           -C /opt/landoop/connectors/third-party/ \
    && rm -rf /opt/kafka-connect-hdfs.tar.gz

# Kafka Connect S3
ARG KAFKA_CONNECT_S3_VERSION="${KAFKA_CONNECT_S3_VERSION:-4.0.0-lkd}"
ARG KAFKA_CONNECT_S3_URL="${KAFKA_CONNECT_S3_URL:-https://archive.landoop.com/lkd/packages/kafka-connect-s3-${KAFKA_CONNECT_S3_VERSION}.tar.gz}"
RUN wget $DEVARCH_USER $DEVARCH_PASS "$KAFKA_CONNECT_S3_URL" \
         -O /opt/kafka-connect-s3.tar.gz \
    && mkdir -p /opt/landoop/connectors/third-party/ \
    && tar --no-same-owner -xf /opt/kafka-connect-s3.tar.gz \
           -C /opt/landoop/connectors/third-party/ \
    && rm -rf /opt/kafka-connect-s3.tar.gz


############
# Add tools/
############

# Add Coyote
ARG COYOTE_VERSION="1.2"
ARG COYOTE_URL="https://github.com/Landoop/coyote/releases/download/v${COYOTE_VERSION}/coyote-${COYOTE_VERSION}"
RUN mkdir -p /opt/landoop/tools/bin/win \
             /opt/landoop/tools/bin/mac \
             /opt/landoop/tools/share/coyote/examples \
    && wget "$COYOTE_URL"-linux-amd64 -O /opt/landoop/tools/bin/coyote \
    && wget "$COYOTE_URL"-darwin-amd64 -O /opt/landoop/tools/bin/mac/coyote \
    && wget "$COYOTE_URL"-windows-amd64.exe -O /opt/landoop/tools/bin/win/coyote \
    && chmod +x /opt/landoop/tools/bin/coyote \
                /opt/landoop/tools/bin/mac/coyote \
                /opt/landoop/tools/bin/win/coyote
ADD lkd/simple-integration-tests.yml /opt/landoop/tools/share/coyote/examples/

# Add Kafka Topic UI, Schema Registry UI, Kafka Connect UI
ARG KAFKA_TOPICS_UI_VERSION="0.9.3"
ARG KAFKA_TOPICS_UI_URL="https://github.com/Landoop/kafka-topics-ui/releases/download/v${KAFKA_TOPICS_UI_VERSION}/kafka-topics-ui-${KAFKA_TOPICS_UI_VERSION}.tar.gz"
ARG SCHEMA_REGISTRY_UI_VERSION="0.9.4"
ARG SCHEMA_REGISTRY_UI_URL="https://github.com/Landoop/schema-registry-ui/releases/download/v.${SCHEMA_REGISTRY_UI_VERSION}/schema-registry-ui-${SCHEMA_REGISTRY_UI_VERSION}.tar.gz"
ARG KAFKA_CONNECT_UI_VERSION="0.9.4"
ARG KAFKA_CONNECT_UI_URL="https://github.com/Landoop/kafka-connect-ui/releases/download/v.${KAFKA_CONNECT_UI_VERSION}/kafka-connect-ui-${KAFKA_CONNECT_UI_VERSION}.tar.gz"
RUN mkdir -p /opt/landoop/tools/share/kafka-topics-ui/ \
             /opt/landoop/tools/share/schema-registry-ui/ \
             /opt/landoop/tools/share/kafka-connect-ui/ \
    && wget "$KAFKA_TOPICS_UI_URL" \
            -O /opt/landoop/tools/share/kafka-topics-ui/kafka-topics-ui.tar.gz \
    && wget "$SCHEMA_REGISTRY_UI_URL" \
            -O /opt/landoop/tools/share/schema-registry-ui/schema-registry-ui.tar.gz \
    && wget "$KAFKA_CONNECT_UI_URL" \
            -O /opt/landoop/tools/share/kafka-connect-ui/kafka-connect-ui.tar.gz

# Add Kafka Autocomplete
ARG KAFKA_AUTOCOMPLETE_VERSION="0.3"
ARG KAFKA_AUTOCOMPLETE_URL="https://github.com/Landoop/kafka-autocomplete/releases/download/${KAFKA_AUTOCOMPLETE_VERSION}/kafka"
RUN mkdir -p /opt/landoop/tools/share/kafka-autocomplete \
             /opt/landoop/tools/share/bash-completion/completions \
    && wget "$KAFKA_AUTOCOMPLETE_URL" \
            -O /opt/landoop/tools/share/kafka-autocomplete/kafka \
    && wget "$KAFKA_AUTOCOMPLETE_URL" \
            -O /opt/landoop/tools/share/bash-completion/completions/kafka

##########
# Finalize
##########

RUN echo "LKD_VERSION=${LKD_VERSION}"                                  | tee -a /opt/landoop/build.info \
    && echo "KAFKA_VERSION=${KAFKA_LVERSION}"                          | tee -a /opt/landoop/build.info \
    && echo "CONNECT_VERSION=${KAFKA_LVERSION}"                        | tee -a /opt/landoop/build.info \
    && echo "SCHEMA_REGISTRY_VERSION=${REGISTRY_VERSION}"              | tee -a /opt/landoop/build.info \
    && echo "REST_PROXY_VERSION=${REST_VERSION}"                       | tee -a /opt/landoop/build.info \
    && echo "STREAM_REACTOR_VERSION=${STREAM_REACTOR_VERSION}"         | tee -a /opt/landoop/build.info \
    && echo "KAFKA_CONNECT_JDBC_VERSION=${KAFKA_CONNECT_JDBC_VERSION}" | tee -a /opt/landoop/build.info \
    && echo "KAFKA_CONNECT_ELASTICSEARCH_VERSION=${KAFKA_CONNECT_ELASTICSEARCH_VERSION}" \
                                                                       | tee -a /opt/landoop/build.info \
    && echo "KAFKA_CONNECT_HDFS_VERSION=${KAFKA_CONNECT_HDFS_VERSION}" | tee -a /opt/landoop/build.info \
    && echo "KAFKA_CONNECT_S3_VERSION=${KAFKA_CONNECT_S3_VERSION}"     | tee -a /opt/landoop/build.info \
    && echo "KAFKA_TOPICS_UI=${KAFKA_TOPICS_UI_VERSION}"               | tee -a /opt/landoop/build.info \
    && echo "SCHEMA_REGISTRY_UI=${SCHEMA_REGISTRY_UI_VERSION}"         | tee -a /opt/landoop/build.info \
    && echo "KAFKA_CONNECT_UI=${KAFKA_CONNECT_UI_VERSION}"             | tee -a /opt/landoop/build.info \
    && echo "COYOTE=${COYOTE_VERSION}"                                 | tee -a /opt/landoop/build.info \
    && echo "KAFKA_AUTOCOMPLETE=${KAFKA_AUTOCOMPLETE_VERSION}"         | tee -a /opt/landoop/build.info

# duphard (replace duplicates with hard links) and create archive
RUN duphard -d=0 /opt/landoop \
    && tar -czf /LKD-${LKD_VERSION}.tar.gz \
           --owner=root \
           --group=root \
           -C /opt \
           landoop \
    && rm -rf /opt/landoop
# Unfortunately we have to make this a separate step in order for docker to understand the change to hardlinks
# Good thing: final image that people download is much smaller (~200MB).
RUN tar xf /LKD-${LKD_VERSION}.tar.gz -C /opt \
    && rm /LKD-${LKD_VERSION}.tar.gz

ENV LKD_VERSION=${LKD_VERSION}
# If this stage is run as container and you mount `/mnt`, we will create the LKD archive there.
CMD ["bash", "-c", "tar -czf /mnt/LKD-${LKD_VERSION}.tar.gz -C /opt landoop; chown --reference=/mnt /mnt/LKD-${LKD_VERSION}.tar.gz"]

FROM alpine
MAINTAINER Marios Andreopoulos <marios@landoop.com>
COPY --from=compile-lkd /opt /opt

# Update, install tooling and some basic setup
RUN apk add --no-cache \
        bash \
        bash-completion \
        bzip2 \
        coreutils \
        curl \
        dumb-init \
        gettext \
        gzip \
        jq \
        libstdc++ \
        openjdk8-jre-base \
        openssl \
        sqlite \
        supervisor \
        tar \
        wget \
    && echo "progress = dot:giga" | tee /etc/wgetrc \
    && mkdir -p /opt \
    && wget https://gitlab.com/andmarios/checkport/uploads/3903dcaeae16cd2d6156213d22f23509/checkport -O /usr/local/bin/checkport \
    && chmod +x /usr/local/bin/checkport \
    && mkdir /extra-connect-jars /connectors \
    && mkdir /etc/supervisord.d /etc/supervisord.templates.d

# # Install LKD (Landoop’s Kafka Distribution)
# ENV LKD_VERSION="1.0.0-r0"
# ARG LKD_URL="https://archive.landoop.com/lkd/packages/lkd-${LKD_VERSION}.tar.gz"
# RUN wget "$LKD_URL" -O /lkd.tar.gz \
#     && tar xf /lkd.tar.gz -C /opt \
#     && rm /lkd.tar.gz \
#     && echo "plugin.path=/opt/landoop/connectors/stream-reactor,/opt/landoop/connectors/third-party,/connectors,/extra-jars" \
#              >> /opt/landoop/kafka/etc/schema-registry/connect-avro-distributed.properties

RUN echo "plugin.path=/opt/landoop/connectors/stream-reactor,/opt/landoop/connectors/third-party,/connectors,/extra-jars" \
          >> /opt/landoop/kafka/etc/schema-registry/connect-avro-distributed.properties

# Create Landoop configuration directory
RUN mkdir /usr/share/landoop

# Add glibc (for Lenses branch, for HDFS connector etc as some java libs need some functions provided by glibc)
ARG GLIBC_INST_VERSION="2.27-r0"
RUN wget https://github.com/sgerrand/alpine-pkg-glibc/releases/download/${GLIBC_INST_VERSION}/glibc-${GLIBC_INST_VERSION}.apk \
    && wget https://github.com/sgerrand/alpine-pkg-glibc/releases/download/${GLIBC_INST_VERSION}/glibc-bin-${GLIBC_INST_VERSION}.apk \
    && wget https://github.com/sgerrand/alpine-pkg-glibc/releases/download/${GLIBC_INST_VERSION}/glibc-i18n-${GLIBC_INST_VERSION}.apk \
    && apk add --no-cache --allow-untrusted glibc-${GLIBC_INST_VERSION}.apk glibc-bin-${GLIBC_INST_VERSION}.apk glibc-i18n-${GLIBC_INST_VERSION}.apk \
    && rm -f glibc-${GLIBC_INST_VERSION}.apk glibc-bin-${GLIBC_INST_VERSION}.apk glibc-i18n-${GLIBC_INST_VERSION}.apk

# Create system symlinks to Kafka binaries
RUN bash -c 'for i in $(find /opt/landoop/kafka/bin -maxdepth 1 -type f); do ln -s $i /usr/local/bin/$(echo $i | sed -e "s>.*/>>"); done'

# Add quickcert
RUN wget https://github.com/andmarios/quickcert/releases/download/1.0/quickcert-1.0-linux-amd64-alpine -O /usr/local/bin/quickcert \
    && chmod 0755 /usr/local/bin/quickcert

# Add Coyote and tests
ADD integration-tests/smoke-tests.sh /usr/local/bin
RUN chmod +x /usr/local/bin/smoke-tests.sh \
    && mkdir -p /var/www/coyote-tests
ADD integration-tests/index.html integration-tests/results /var/www/coyote-tests/

# Setup Kafka Topics UI, Schema Registry UI, Kafka Connect UI
RUN mkdir -p \
      /var/www/kafka-topics-ui \
      /var/www/schema-registry-ui \
      /var/www/kafka-connect-ui \
    && tar xzf /opt/landoop/tools/share/kafka-topics-ui/kafka-topics-ui.tar.gz -C /var/www/kafka-topics-ui \
    && tar xzf /opt/landoop/tools/share/schema-registry-ui/schema-registry-ui.tar.gz -C /var/www/schema-registry-ui \
    && tar xzf /opt/landoop/tools/share/kafka-connect-ui/kafka-connect-ui.tar.gz -C /var/www/kafka-connect-ui
COPY web/registry-ui-env.js /var/www/schema-registry-ui/env.js
COPY web/topics-ui-env.js /var/www/kafka-topics-ui/env.js
COPY web/connect-ui-env.js /var/www/kafka-connect-ui/env.js

# Add and setup Caddy Server
ARG CADDY_URL=https://github.com/mholt/caddy/releases/download/v0.10.10/caddy_v0.10.10_linux_amd64.tar.gz
RUN wget "$CADDY_URL" -O /caddy.tgz \
    && mkdir -p /opt/caddy \
    && tar xzf /caddy.tgz -C /opt/caddy \
    && rm -f /caddy.tgz
ADD web/Caddyfile /usr/share/landoop

# Add fast-data-dev UI
COPY web/index.html web/env.js web/env-webonly.js /var/www/
COPY web/img /var/www/img
RUN ln -s /var/log /var/www/logs

# Add sample data and install normcat
ARG NORMCAT_URL=https://archive.landoop.com/tools/normcat/normcat_lowmem-1.1.1.tgz
RUN wget "$NORMCAT_URL" -O /normcat.tgz \
    && tar xf /normcat.tgz -C /usr/local/bin \
    && rm /normcat.tgz
COPY sample-data /usr/share/landoop/sample-data

# Add executables, settings and configuration
ADD extras/ /usr/share/landoop/
ADD supervisord.conf /etc/supervisord.conf
ADD supervisord.templates.d/* /etc/supervisord.templates.d/
ADD setup-and-run.sh logs-to-kafka.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/setup-and-run.sh /usr/local/bin/logs-to-kafka.sh \
    && ln -s /usr/share/landoop/bashrc /root/.bashrc \
    && cat /etc/supervisord.templates.d/* > /etc/supervisord.d/01-fast-data.conf

ARG BUILD_BRANCH
ARG BUILD_COMMIT
ARG BUILD_TIME
ARG DOCKER_REPO=local
RUN echo "BUILD_BRANCH=${BUILD_BRANCH}"       | tee /build.info \
    && echo "BUILD_COMMIT=${BUILD_COMMIT}"    | tee -a /build.info \
    && echo "BUILD_TIME=${BUILD_TIME}"        | tee -a /build.info \
    && echo "DOCKER_REPO=${DOCKER_REPO}"      | tee -a /build.info \
    && echo "LKD=${LKD_VERSION}"              | tee -a /build.info \
    && cat /opt/landoop/build.info            | tee -a /build.info

EXPOSE 2181 3030 3031 8081 8082 8083 9092
ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["/usr/local/bin/setup-and-run.sh"]
