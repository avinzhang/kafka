FROM confluentinc/cp-base-new:6.2.1


USER root

RUN dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
RUN dnf install nodejs -y

COPY generate-users.js /home/appuser/generate-users.js

COPY jolokia-jvm-1.7.0.jar /home/appuser/jolokia-jvm-1.7.0.jar

RUN echo "===> Installing kafka..." \
    && echo "===> Adding confluent repository.." \
    && rpm --import https://packages.confluent.io/rpm/7.0/archive.key \
    && printf "[Confluent.dist] \n\
name=Confluent repository (dist) \n\
baseurl=https://packages.confluent.io/rpm/7.0 \n\
gpgcheck=1 \n\
gpgkey=https://packages.confluent.io/rpm/7.0/archive.key \n\
enabled=1 " > /etc/yum.repos.d/confluent.repo \
    && yum install -y confluent-kafka \
    && yum clean all \
    && rm -rf /tmp/* /etc/yum.repos.d/confluent.repo 


User appuser

CMD ping localhost
