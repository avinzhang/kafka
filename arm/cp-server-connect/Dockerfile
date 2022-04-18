FROM confluentinc/cp-server:latest.arm64

ARG COMMIT_ID=unknown
LABEL io.confluent.docker.git.id=$COMMIT_ID
ARG BUILD_NUMBER=-1
LABEL io.confluent.docker.build.number=$BUILD_NUMBER

MAINTAINER partner-support@confluent.io
LABEL io.confluent.docker=true


ARG CONFLUENT_VERSION=7.1.0
ARG CONFLUENT_PACKAGES_REPO=https://packages.confluent.io/rpm/7.1
ARG CONFLUENT_PLATFORM_LABEL=7.1.0

# allow arg override of required env params
ARG KAFKA_ZOOKEEPER_CONNECT
ENV KAFKA_ZOOKEEPER_CONNECT=${KAFKA_ZOOKEEPER_CONNECT}
ARG KAFKA_ADVERTISED_LISTENERS
ENV KAFKA_ADVERTISED_LISTENERS=${KAFKA_ADVERTISED_LISTENERS}


ENV COMPONENT=kafka-connect

# Default kafka-connect rest.port
EXPOSE 8083

USER root

RUN echo "===> Installing ${COMPONENT}..." \
    && echo "===> Adding confluent repository...${CONFLUENT_PACKAGES_REPO}" \
    && rpm --import ${CONFLUENT_PACKAGES_REPO}/archive.key \
    && printf "[Confluent.dist] \n\
name=Confluent repository (dist) \n\
baseurl=${CONFLUENT_PACKAGES_REPO}/7 \n\
gpgcheck=1 \n\
gpgkey=${CONFLUENT_PACKAGES_REPO}/archive.key \n\
enabled=1 \n\
\n\
[Confluent] \n\
name=Confluent repository \n\
baseurl=${CONFLUENT_PACKAGES_REPO}/ \n\
gpgcheck=1 \n\
gpgkey=${CONFLUENT_PACKAGES_REPO}/archive.key \n\
enabled=1 " > /etc/yum.repos.d/confluent.repo \
    && echo "===> Installing Schema Registry (for Avro jars) ..." \
    && yum install -y confluent-schema-registry-${CONFLUENT_VERSION} \
    && echo "===> Installing Controlcenter for monitoring interceptors ..."\
    && yum install -y confluent-control-center-${CONFLUENT_VERSION} \
    && echo "===> Installing Confluent security plugins ..." \
    && yum install -y confluent-security-${CONFLUENT_VERSION} \
    && echo "===> Installing Confluent Hub client ..." \
    && yum install -y confluent-hub-client-${CONFLUENT_VERSION} \
    && echo "===> Cleaning up ..."  \
    && yum clean all \
    && rm -rf /tmp/* /etc/yum.repos.d/confluent.repo \
    && echo "===> Setting up ${COMPONENT} dirs ..." \
    && mkdir -p /etc/${COMPONENT} /etc/${COMPONENT}/secrets /etc/${COMPONENT}/jars /usr/logs /usr/share/confluent-hub-components \
    && chown appuser:root -R /etc/kafka /etc/${COMPONENT} /etc/schema-registry /usr/logs /usr/share/confluent-hub-components \
    && chmod -R ug+w /etc/kafka /etc/${COMPONENT} /etc/${COMPONENT}/secrets /etc/${COMPONENT}/jars /etc/schema-registry

ENV CONNECT_PLUGIN_PATH=/usr/share/java/,/usr/share/confluent-hub-components/

VOLUME ["/etc/${COMPONENT}/jars", "/etc/${COMPONENT}/secrets"]

COPY --chown=appuser:appuser include/etc/confluent/docker /etc/confluent/docker

USER appuser

CMD ["/etc/confluent/docker/run"]

