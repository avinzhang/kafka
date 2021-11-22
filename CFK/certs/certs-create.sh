#!/bin/bash

#set -o nounset \
#    -o errexit \
#    -o verbose \
#    -o xtrace

# Cleanup files
rm -f *.crt *.csr *_creds *.jks *.srl *.key *.pem *.der *.p12

ns=confluent

# Generate CA key
openssl req -new -x509 -keyout ca.key -out ca.crt -days 365 -subj '/CN=ca.test.confluent.io/OU=TEST/O=CONFLUENT/L=MountainView/S=Ca/C=US' -passin pass:confluent -passout pass:confluent

for i in kafka schemaregistry restproxy connect replicator zookeeper controlcenter ksqldb openldap client
do
	# Create host keystore
	keytool -genkey -noprompt \
				 -alias $i \
				 -dname "CN=$cn,OU=TEST,O=CONFLUENT,L=MountainView,S=Ca,C=US" \
                                 -ext "SAN=dns:$i,dns:localhost" \
				 -keystore $i.keystore.jks \
				 -keyalg RSA \
				 -storepass confluent \
				 -keypass confluent

	# Create the certificate signing request (CSR)
	keytool -keystore $i.keystore.jks -alias $i -certreq -file $i.csr -storepass confluent -keypass confluent -ext "SAN=dns:$i,dns:localhost"
        #openssl req -in $i.csr -text -noout
if [ $i == "kafka" ]
then
  openssl x509 -req -CA ca.crt -CAkey ca.key -in $i.csr -out $i-ca1-signed.crt -days 9999 -CAcreateserial -passin pass:confluent -extensions v3_req -extfile <(cat <<EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no
[req_distinguished_name]
CN = $cn
[v3_req]
subjectAltName = @alt_names
[alt_names]
DNS.1 = $i
DNS.2 = localhost
DNS.3 = *.cluster.local
DNS.4 = *.svc.cluster.local
DNS.5 = *.$ns.svc.cluster.local
DNS.6 = *.kafka.$ns.svc.cluster.local
DNS.7 = *.$i.$ns.svc.cluster.local
DNS.8 = $i.mycfk.com
DNS.9 = b0.mycfk.com
DNS.10 = b1.mycfk.com
DNS.11 = b2.mycfk.com

EOF
)
else
        # Sign the host certificate with the certificate authority (CA)
        openssl x509 -req -CA ca.crt -CAkey ca.key -in $i.csr -out $i-ca1-signed.crt -days 9999 -CAcreateserial -passin pass:confluent -extensions v3_req -extfile <(cat <<EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no
[req_distinguished_name]
CN = $cn
[v3_req]
subjectAltName = @alt_names
[alt_names]
DNS.1 = $i
DNS.2 = localhost
DNS.3 = *.cluster.local
DNS.4 = *.svc.cluster.local
DNS.5 = *.$ns.svc.cluster.local
DNS.6 = *.kafka.$ns.svc.cluster.local
DNS.7 = *.$i.$ns.svc.cluster.local
DNS.8 = $i.mycfk.com

EOF
)
fi
        #openssl x509 -noout -text -in $i-ca1-signed.crt

        # Sign and import the CA cert into the keystore
	keytool -noprompt -keystore $i.keystore.jks -alias CARoot -import -file ca.crt -storepass confluent -keypass confluent
        #keytool -list -v -keystore kafka.$i.keystore.jks -storepass confluent

        # Sign and import the host certificate into the keystore
	keytool -noprompt -keystore $i.keystore.jks -alias $i -import -file $i-ca1-signed.crt -storepass confluent -keypass confluent -ext "SAN=dns:$i,dns:localhost"
        #keytool -list -v -keystore kafka.$i.keystore.jks -storepass confluent

	# Create truststore and import the CA cert
	keytool -noprompt -keystore $i.truststore.jks -alias CARoot -import -file ca.crt -storepass confluent -keypass confluent

	# Save creds
  	echo "confluent" > ${i}_sslkey_creds
  	echo "confluent" > ${i}_keystore_creds
  	echo "confluent" > ${i}_truststore_creds

	# Create pem files and keys used for Schema Registry HTTPS testing
	#   openssl x509 -noout -modulus -in client.certificate.pem | openssl md5
	#   openssl rsa -noout -modulus -in client.key | openssl md5 
    #   echo "GET /" | openssl s_client -connect localhost:8085/subjects -cert client.certificate.pem -key client.key -tls1
	keytool -export -alias $i -file $i.der -keystore $i.keystore.jks -storepass confluent
	openssl x509 -inform der -in $i.der -out $i.certificate.pem
	keytool -importkeystore -srckeystore $i.keystore.jks -destkeystore $i.keystore.p12 -deststoretype PKCS12 -deststorepass confluent -srcstorepass confluent -noprompt
	openssl pkcs12 -in $i.keystore.p12 -nodes -nocerts -out $i.key -passin pass:confluent

done
