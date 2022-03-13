FROM centos:7

# build environment
WORKDIR /root/

# update
RUN yum -y update

# editor
RUN yum -y install vim telnet net-tools 

# kerberos server
RUN yum -y install krb5-server krb5-libs krb5-workstation pam_krb5

RUN mkdir -pv /var/log/kerberos/

ADD ./config.sh /config.sh

ENTRYPOINT ["/config.sh"]

# kerberos server configuration

EXPOSE 88 
