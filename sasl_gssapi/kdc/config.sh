#!/bin/bash

[[ "TRACE" ]] && set -x

: ${REALM:=EXAMPLE.COM}
: ${DOMAIN_REALM:=example.com}
: ${KERB_MASTER_KEY:=masterkey}
: ${KERB_ADMIN_USER:=admin}
: ${KERB_ADMIN_PASS:=admin}



create_config() {
  : ${KDC_ADDRESS:=$(hostname -f)}

  cat>/etc/krb5.conf<<EOF
[logging]
 default = FILE:/var/log/kerberos/krb5libs.log
 kdc = FILE:/var/log/kerberos/krb5kdc.log
 admin_server = FILE:/var/log/kerberos/kadmind.log

[libdefaults]
 default_realm = $REALM
 dns_lookup_realm = false
 dns_lookup_kdc = false
 ticket_lifetime = 24h
 renew_lifetime = 7d
 forwardable = true
 allow_weak_crypto = true

[realms]
 $REALM = {
  kdc = $KDC_ADDRESS
  admin_server = $KDC_ADDRESS
  default_domain = $DOMAIN_REALM
 }

[domain_realm]
 .$DOMAIN_REALM = $REALM
 $DOMAIN_REALM = $REALM
EOF

cat>/var/kerberos/krb5kdc/kdc.conf<<EOF
[kdcdefaults]
 kdc_ports = 88
 kdc_tcp_ports = 88

[realms]
 $REALM = {
  acl_file = /var/kerberos/krb5kdc/kadm5.acl
  dict_file = /usr/share/dict/words
  admin_keytab = /var/kerberos/krb5kdc/kadm5.keytab
  master_key_type = des3-hmac-sha1
  supported_enctypes = arcfour-hmac:normal des3-hmac-sha1:normal des-cbc-crc:normal des:normal des:v4 des:norealm des:onlyrealm des:afs3
  default_principal_flags = +preauth
 }
EOF
}

create_db() {
  /usr/sbin/kdb5_util -P $KERB_MASTER_KEY -r $REALM create -s
}

create_admin_user() {
  kadmin.local -q "addprinc -pw $KERB_ADMIN_PASS $KERB_ADMIN_USER/admin"
  echo "*/admin@$REALM *" > /var/kerberos/krb5kdc/kadm5.acl
}

create_principals() {


  #Service principal for zookeeper
  kadmin.local -q "addprinc -randkey zookeeper/zookeeper1.example.com@EXAMPLE.COM"
  kadmin.local -q "addprinc -randkey zookeeper/zookeeper2.example.com@EXAMPLE.COM"
  kadmin.local -q "addprinc -randkey zookeeper/zookeeper3.example.com@EXAMPLE.COM"
  rm /tmp/keytab/zookeeper*.keytab
  kadmin.local -q "ktadd -norandkey -k /tmp/keytab/zookeeper1.keytab zookeeper/zookeeper1.example.com@EXAMPLE.COM"
  kadmin.local -q "ktadd -norandkey -k /tmp/keytab/zookeeper2.keytab zookeeper/zookeeper2.example.com@EXAMPLE.COM"
  kadmin.local -q "ktadd -norandkey -k /tmp/keytab/zookeeper3.keytab zookeeper/zookeeper3.example.com@EXAMPLE.COM"

  #Serivce principal for brokers to connect to zookeeper
  kadmin.local -q "addprinc -randkey zkclient@EXAMPLE.COM"
  rm /tmp/keytab/zkclient.keytab
  kadmin.local -q "ktadd -norandkey -k /tmp/keytab/zkclient.keytab zkclient@EXAMPLE.COM"

  #Service principal for brokers
  kadmin.local -q "addprinc -randkey kafka/kafka1.example.com@EXAMPLE.COM"
  kadmin.local -q "addprinc -randkey kafka/kafka2.example.com@EXAMPLE.COM"
  kadmin.local -q "addprinc -randkey kafka/kafka3.example.com@EXAMPLE.COM"
  rm /tmp/keytab/kafka*.keytab
  kadmin.local -q "ktadd -norandkey -k /tmp/keytab/kafka1.keytab kafka/kafka1.example.com@EXAMPLE.COM"
  kadmin.local -q "ktadd -norandkey -k /tmp/keytab/kafka2.keytab kafka/kafka2.example.com@EXAMPLE.COM"
  kadmin.local -q "ktadd -norandkey -k /tmp/keytab/kafka3.keytab kafka/kafka3.example.com@EXAMPLE.COM"

  kadmin.local -q "addprinc -randkey connect/connect.example.com@EXAMPLE.COM"
  rm /tmp/keytab/connect.keytab
  kadmin.local -q "ktadd -norandkey -k /tmp/keytab/connect.keytab connect/connect.example.com@EXAMPLE.COM"

  kadmin.local -q "addprinc -randkey schemaregistry/schemaregistry.example.com@EXAMPLE.COM"
  rm /tmp/keytab/schemaregistry.keytab
  kadmin.local -q "ktadd -norandkey -k /tmp/keytab/schemaregistry.keytab schemaregistry/schemaregistry.example.com@EXAMPLE.COM"

  kadmin.local -q "addprinc -randkey ksqldb-server/ksqldb-server.example.com@EXAMPLE.COM"
  rm /tmp/keytab/ksqldb-server.keytab
  kadmin.local -q "ktadd -norandkey -k /tmp/keytab/ksqldb-server.keytab ksqldb-server/ksqldb-server.example.com@EXAMPLE.COM"

  kadmin.local -q "addprinc -randkey controlcenter/controlcenter.example.com@EXAMPLE.COM"
  rm /tmp/keytab/controlcenter.keytab
  kadmin.local -q "ktadd -norandkey -k /tmp/keytab/controlcenter.keytab controlcenter/controlcenter.example.com@EXAMPLE.COM"

  kadmin.local -q "addprinc -randkey saslproducer/kafka.example.com@EXAMPLE.COM"
  rm /tmp/keytab/saslproducer.keytab
  kadmin.local -q "ktadd -norandkey -k /tmp/keytab/saslproducer.keytab saslproducer/kafka.example.com@EXAMPLE.COM"
}

start_kdc() {
  /usr/sbin/krb5kdc -P /var/run/krb5kdc.pid
  /usr/sbin/_kadmind -P /var/run/kadmind.pid
}

main() {

  if [ ! -f /kerberos_initialized ]; then
    create_config
    create_db
    create_admin_user
    start_kdc
    create_principals
    touch /kerberos_initialized
  fi

  tail -F /var/log/kerberos/krb5kdc.log
}

[[ "$0" == "$BASH_SOURCE" ]] && main "$@"
