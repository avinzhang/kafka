#
# Copyright 2019 Confluent Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

ARG DOCKER_UPSTREAM_REGISTRY
ARG DOCKER_UPSTREAM_TAG=latest.arm64

FROM ${DOCKER_UPSTREAM_REGISTRY}confluentinc/cp-base-new:${DOCKER_UPSTREAM_TAG}

ARG PROJECT_VERSION=7.1.1

LABEL release=$PROJECT_VERSION
LABEL name=$ARTIFACT_ID
LABEL summary="Confluent platform server image."
LABEL description="Confluent platform server image."
ARG BUILD_NUMBER=-1

ARG CONFLUENT_VERSION=7.1.1
ARG CONFLUENT_PACKAGES_REPO=https://packages.confluent.io/rpm/7.1
ARG CONFLUENT_PLATFORM_LABEL=7.1.1

# allow arg override of required env params
ARG KAFKA_ZOOKEEPER_CONNECT
ENV KAFKA_ZOOKEEPER_CONNECT=${KAFKA_ZOOKEEPER_CONNECT}
ARG KAFKA_ADVERTISED_LISTENERS
ENV KAFKA_ADVERTISED_LISTENERS=${KAFKA_ADVERTISED_LISTENERS}

ENV COMPONENT=kafka

# primary
EXPOSE 9092

USER root

RUN echo "===> Installing ${COMPONENT}..." \
    && echo "===> Adding confluent repository...${CONFLUENT_PACKAGES_REPO}" \
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
    && echo "===> installing ${COMPONENT}..." \
    && yum install -y confluent-server-${CONFLUENT_VERSION} \
    && echo "===> installing confluent-rebalancer ..." \
    && yum install -y confluent-rebalancer-${CONFLUENT_VERSION} \
    && echo "===> installing confluent-security ..." \
    && yum install -y confluent-security-${CONFLUENT_VERSION} \
    && echo "===> clean up ..."  \
    && yum clean all \
    && rm -rf /tmp/* /etc/yum.repos.d/confluent.repo \
    && echo "===> Setting up ${COMPONENT} dirs" \
    && mkdir -p /var/lib/${COMPONENT}/data /etc/${COMPONENT}/secrets \
    && chown -R appuser:root /etc/kafka /var/log/kafka /var/log/confluent /var/lib/kafka /var/lib/zookeeper /etc/${COMPONENT}/secrets \
    && chmod -R ug+w /etc/kafka /var/lib/${COMPONENT}/data /etc/${COMPONENT}/secrets /var/log/kafka

VOLUME ["/var/lib/${COMPONENT}/data", "/etc/${COMPONENT}/secrets"]

COPY --chown=appuser:appuser include/etc/confluent/docker /etc/confluent/docker

USER appuser

CMD ["/etc/confluent/docker/run"]
