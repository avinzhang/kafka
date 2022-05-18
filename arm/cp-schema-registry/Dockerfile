FROM confluentinc/cp-base-new:latest.arm64

ARG COMMIT_ID=unknown
LABEL io.confluent.docker.git.id=$COMMIT_ID
ARG BUILD_NUMBER=-1
LABEL io.confluent.docker.build.number=$BUILD_NUMBER

MAINTAINER partner-support@confluent.io
LABEL io.confluent.docker=true


ARG CONFLUENT_VERSION=7.1.1
ARG CONFLUENT_PACKAGES_REPO=https://packages.confluent.io/rpm/7.1
ARG CONFLUENT_PLATFORM_LABEL=7.1.1

ENV COMPONENT=schema-registry


# Default listener
EXPOSE 8081

USER root

RUN echo "===> installing ${COMPONENT}..." \
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
    && yum install -y \
        confluent-${COMPONENT}-${CONFLUENT_VERSION} \
        confluent-control-center-${CONFLUENT_VERSION} \
        # We are installing confluent-telemetry package explicitly because
        # Schema Registry's deb/rpm packages cannot directly depend on
        # confluent-telemetry package as Schema Registry is Open Source.
        confluent-telemetry-${CONFLUENT_VERSION} \
        confluent-security-${CONFLUENT_VERSION} \
        confluent-schema-registry-plugins-${CONFLUENT_VERSION} \
    && echo "===> clean up ..."  \
    && yum clean all \
    && rm -rf /tmp/* /etc/yum.repos.d/confluent.repo \
    && echo "===> Setting up ${COMPONENT} dirs" \
    && mkdir -p /etc/${COMPONENT}/secrets /usr/logs \
    && chown appuser:root -R /etc/${COMPONENT} /usr/logs \
    && chmod -R ug+w /etc/${COMPONENT} /etc/${COMPONENT}/secrets

VOLUME ["/etc/${COMPONENT}/secrets"]

COPY --chown=appuser:appuser include/etc/confluent/docker /etc/confluent/docker

USER appuser

CMD ["/etc/confluent/docker/run"]


