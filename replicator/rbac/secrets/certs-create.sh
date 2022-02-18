#!/bin/bash

#set -o nounset \
#    -o errexit \
#    -o verbose \
#    -o xtrace

# Cleanup files
rm -f *.crt *.csr *_creds *.jks *.srl *.key *.pem *.der *.p12

# Generate CA key
openssl req -new -x509 -keyout ca.key -out ca.crt -days 365 -subj '/CN=ca.example.com/O=EXAMPLE/L=MountainView/S=Ca/C=US' -passin pass:confluent -passout pass:confluent

for i in zookeeper3 zookeeper1 zookeeper2 kafka3 kafka1 kafka2 client schemaregistry restproxy connect connect1 ksqldb-server controlcenter openldap
do
	echo "------------------------------- $i -------------------------------"

	# Create host keystore
	keytool -genkey -noprompt \
				 -alias $i \
				 -dname "CN=$i,OU=Support,O=EXAMPLE,L=MountainView,S=Ca,C=US" \
                                 -ext "SAN=dns:$i,dns:localhost" \
				 -keystore $i.keystore.jks \
				 -keyalg RSA \
				 -storepass confluent \
				 -keypass confluent

	# Create the certificate signing request (CSR)
	keytool -keystore $i.keystore.jks -alias $i -certreq -file $i.csr -storepass confluent -keypass confluent -ext "SAN=dns:$i,dns:localhost"
        #openssl req -in $i.csr -text -noout
  if [[ $i = "zookeeper1" ]]; then
    openssl x509 -req -CA ca.crt -CAkey ca.key -in $i.csr -out $i-ca-signed.crt -days 9999 -CAcreateserial -passin pass:confluent -extensions v3_req -extfile <(cat <<EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no
[req_distinguished_name]
CN = $i
[v3_req]
subjectAltName = @alt_names
[alt_names]
DNS.1 = $i
DNS.2 = localhost
DNS.3 = zookeeper2
DNS.4 = zookeeper3
EOF
)
  else
        # Sign the host certificate with the certificate authority (CA)
        openssl x509 -req -CA ca.crt -CAkey ca.key -in $i.csr -out $i-ca-signed.crt -days 9999 -CAcreateserial -passin pass:confluent -extensions v3_req -extfile <(cat <<EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no
[req_distinguished_name]
CN = $i
[v3_req]
subjectAltName = @alt_names
[alt_names]
DNS.1 = $i
DNS.2 = localhost
EOF
)
 fi

        # Sign and import the CA cert into the keystore
	keytool -noprompt -keystore $i.keystore.jks -alias CARoot -import -file ca.crt -storepass confluent -keypass confluent

        # Sign and import the host certificate into the keystore
	keytool -noprompt -keystore $i.keystore.jks -alias $i -import -file $i-ca-signed.crt -storepass confluent -keypass confluent -ext "SAN=dns:$i,dns:localhost"

	# Create truststore and import the CA cert
	keytool -noprompt -keystore $i.truststore.jks -alias CARoot -import -file ca.crt -storepass confluent -keypass confluent

	# Save creds
  	echo "confluent" > ${i}_sslkey_creds
  	echo "confluent" > ${i}_keystore_creds
  	echo "confluent" > ${i}_truststore_creds

	# Create pem files and keys 
	keytool -export -alias $i -file $i.der -keystore $i.keystore.jks -storepass confluent
	openssl x509 -inform der -in $i.der -out $i.certificate.pem
	keytool -importkeystore -srckeystore $i.keystore.jks -destkeystore $i.keystore.p12 -deststoretype PKCS12 -deststorepass confluent -srcstorepass confluent -noprompt
	openssl pkcs12 -in $i.keystore.p12 -nodes -nocerts -out $i.key -passin pass:confluent

done
