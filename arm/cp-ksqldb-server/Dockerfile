FROM confluentinc/cp-base-new:latest.arm64

ARG COMMIT_ID=unknown
LABEL io.confluent.docker.git.id=$COMMIT_ID
ARG BUILD_NUMBER=-1
LABEL io.confluent.docker.build.number=$BUILD_NUMBER

MAINTAINER partner-support@confluent.io
LABEL io.confluent.docker=true


ARG CONFLUENT_VERSION=7.1.0
ARG CONFLUENT_PACKAGES_REPO=https://packages.confluent.io/rpm/7.1
ARG CONFLUENT_PLATFORM_LABEL=7.1.0

ENV COMPONENT=ksqldb-server
ENV KSQL_CLASSPATH=/usr/share/java/${COMPONENT}/*


# Default listener
EXPOSE 8088

USER root

ADD --chown=appuser:appuser artifacts/* /usr/share/java/${COMPONENT}/
#ADD --chown=appuser:appuser target/${ARTIFACT_ID}-${PROJECT_VERSION}-package/share/doc/* /usr/share/doc/${ARTIFACT_ID}/
ADD --chown=appuser:appuser ksqldb-console-scripts-*/* /usr/bin/
ADD --chown=appuser:appuser ksqldb-etc-*/* /etc/ksqldb/

COPY --chown=appuser:appuser ksqldb-etc-*/* /etc/confluent/docker/
COPY --chown=appuser:appuser include/etc/confluent/docker/* /etc/confluent/docker/

RUN mkdir -p /etc/${COMPONENT} /etc/${COMPONENT}/secrets /usr/logs \
  && chown appuser:root -R /etc/${COMPONENT} /usr/logs \
  && chmod ug+w -R /etc/${COMPONENT} /usr/logs

RUN echo "===> Adding confluent repository...${CONFLUENT_PACKAGES_REPO}" \
    && rpm --import ${CONFLUENT_PACKAGES_REPO}/archive.key \
    && printf "[Confluent.dist] \n\
name=Confluent repository (dist) \n\
baseurl=${CONFLUENT_PACKAGES_REPO}/\$releasever \n\
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
    && echo "===> Installing Confluent security plugins ..." \
    && yum install -y confluent-security-${CONFLUENT_VERSION} \
    && echo "===> Installing Confluent Hub client ..." \
    && yum install -y confluent-hub-client-${CONFLUENT_VERSION} \
    && echo "===> Installing Confluent Telemetry package ..." \
    # We are installing confluent-telemetry package explicitly because
    # KSQL's deb/rpm packages cannot directly depend on
    # confluent-telemetry package as KSQL is Open Source.
    && yum install -y confluent-telemetry-${CONFLUENT_VERSION} \
    && echo "===> Cleaning up ..."  \
    && yum clean all \
    && rm -rf /tmp/* /etc/yum.repos.d/confluent.repo \
    && mkdir -p /usr/share/confluent-hub-components \
    && chown appuser:appuser -R /usr/share/confluent-hub-components \
    && mkdir -p /var/lib/kafka-streams \
    && chown appuser:appuser -R /var/lib/kafka-streams

RUN chmod +x /etc/confluent/docker/run
RUN chmod +x /etc/confluent/docker/configure
RUN chmod +x /etc/confluent/docker/launch
RUN chmod +x /etc/confluent/docker/ensure

USER appuser

CMD ["/etc/confluent/docker/run"]
