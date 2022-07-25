#!/bin/bash

rm -f *.crt *.csr *_creds *.jks *.srl *.key *.pem *.der *.p12

echo ">>Generate CA private key"
openssl genrsa -out ca.key 2048
echo 
echo ">>Generate CA cert"
openssl req -x509  -new -nodes \
  -key ca.key \
  -days 3650 \
  -out ca.pem \
  -subj "/C=US/ST=CA/L=MVT/O=CFLT/OU=CSE/CN=testca"
echo
echo
echo ">>Validate CA"
openssl x509 -in ca.pem -text -noout

echo
echo
echo ">>Create component server certs"
for i in zookeeper kafka schemaregistry restproxy connect ksqldb controlcenter replicator openldap client
  do
    cat > /tmp/server-domain-component.json <<EOF
    {
      "CN": "$i",
      "hosts": [
        "$i",
        "*.example.com",
        "*.confluent.svc.cluster.local",
        "*.zookeeper.confluent.svc.cluster.local",
        "*.kafka.confluent.svc.cluster.local",
        "*.connect.confluent.svc.cluster.local",
        "*.schemaregistry.confluent.svc.cluster.local",
        "*.ksqldb.confluent.svc.cluster.local",
        "*.controlcenter.confluent.svc.cluster.local"
      ],
      "key": {
        "algo": "rsa",
        "size": 2048
      },
      "names": [
        {
          "C": "US",
          "ST": "Ca",
          "L": "MTV",
          "O": "Confluent",
          "OU": "CSE"
        }
      ]
    }
EOF
    cfssl gencert -ca=./ca.pem \
    -ca-key=./ca.key \
    -config=./ca-config.json \
    -profile=server /tmp/server-domain-component.json | cfssljson -bare ./$i

    echo
    echo "Validate $i cert"
    openssl x509 -in ./$i.pem -text -noout

done
