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
RUN yum install -y confluent-ksqldb-$tag-1
RUN yum install -y confluent-control-center-$tag-1
RUN yum install -y confluent-hub-client-$tag-1
RUN yum install -y confluent-security-$tag-1


COPY ksql-server.properties /etc/ksql/ksql-server.properties
COPY log4j.properties /etc/ksql/log4j.properties

EXPOSE 8088

CMD ksql-server-start /etc/ksql/ksql-server.properties
