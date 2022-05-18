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

ENV COMPONENT=control-center
ENV CONTROL_CENTER_DATA_DIR=/var/lib/confluent-${COMPONENT}
ENV CONTROL_CENTER_CONFIG_DIR=/etc/confluent-${COMPONENT}


# Default listener
EXPOSE 9021

USER root

RUN echo "===> Installing ${COMPONENT}..." \
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
    && yum install -y confluent-${COMPONENT}-${CONFLUENT_VERSION} \
    && echo "===> Cleaning up ..."  \
    && yum clean all \
    && rm -rf /tmp/* /etc/yum.repos.d/confluent.repo \
    && echo "===> Setting up ${COMPONENT} dirs" \
    && mkdir -p "${CONTROL_CENTER_DATA_DIR}" \
    && chown appuser:root -R "${CONTROL_CENTER_DATA_DIR}" \
    && chown appuser:root -R "${CONTROL_CENTER_CONFIG_DIR}" \
    && chmod -R ug+w "${CONTROL_CENTER_CONFIG_DIR}" "${CONTROL_CENTER_DATA_DIR}"

COPY --chown=appuser:appuser include/etc/confluent/docker /etc/confluent/docker

USER appuser

CMD ["/etc/confluent/docker/run"]
