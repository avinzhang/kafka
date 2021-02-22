FROM centos:7
ARG repo
RUN rpm --import https://packages.confluent.io/rpm/$repo/archive.key
RUN echo -e "\
[Confluent.dist] \n\
name=Confluent repository (dist) \n\
baseurl=https://packages.confluent.io/rpm/\"$repo\"/7 \n\
gpgcheck=1 \n\
gpgkey=https://packages.confluent.io/rpm/\"$repo\"/archive.key \n\
enabled=1 \n\
\n\
[Confluent] \n\
name=Confluent repository \n\
baseurl=https://packages.confluent.io/rpm/\"$repo\" \n\
gpgcheck=1 \n\
gpgkey=https://packages.confluent.io/rpm/\"$repo\"/archive.key \n\
enabled=1 \
" > /etc/yum.repos.d/confluent.repo
RUN yum clean all

ARG tag

RUN yum install -y java-1.8.0-openjdk
RUN yum install -y confluent-common-$tag-1 confluent-metadata-service-$tag-1 confluent-rest-utils-$tag-1
RUN yum install -y confluent-server-$tag-1
RUN yum install -y confluent-rebalancer-$tag-1


COPY server.properties /etc/kafka/server.properties
COPY log4j.properties /etc/kafka/log4j.properties

EXPOSE 9092

CMD kafka-server-start /etc/kafka/server.properties
