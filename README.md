# Connectors:
  * couchbase-source
  * hdfs-sink
  * jdbc: 
    * source to mysql
    * sink to postgres
  * multi-connect-node
    * starts 2 connect workers
  * s3-sink.sh
    * jdbc source to postgres
    * s3 sink to s3
  * splunk-source
  * spooldir-source
  * sqlserver
    * using jdbc source to sqlserver

# Confluent Cloud
  * ccloud commands and how to

# Cluster-linking:
  * cluster-linking

# jmx
  * enabling jmx on broker, how to get jmx metrics

# ksqldb:
  * ksql.sh - full cluster with ksql streams and tables 

# zookeeper:
  * multiple zookeepers
    
# Security:
  * zookeeper mtls
  * sasl_ssl_plain
    * sasl_ssl with plain for all components.  
    * ldap enabled on port 9094 on broker
      ```
      kafka-topics --bootstrap-server localhost:9094 --command-config ./security/sasl_ssl_plain/client.properties --list
      ```
    * C3 has ldap authentication
  * sasl_ssl_gssapi
    * all components using gssapi including zookeeper
  * restproxy-principal-propagation
    * restproxy-basic-to-sasl 
    * restproxy-mtls-to-sasl
  * rbac 
  * rbac_customised_docker


# SSL debug commands
  * find out issuer of a cert
  ```
   openssl x509 -in cert.pem -noout -issuer
  ```

  * check what certs are in a file
  ```
   keytool -printcert -v -file cert.pem
  ```

  * check certificates in a keystore
  ```
   keytool -v -list -keystore keystroe.jks
  ```

  * check particular cert with alias
  ```
   keytool -v -list -keystore keystore.jks -alias alias_name
  ```

  * Delete a cert from keystore
  ```
   keytool -delete -alias alias -keystore keystore.jks
  ```

  * change keystore password
  ```
   keytool -storepasswd -new newpass -keystore keystore.jks
  ```

  * export a certificate from keystore
  ```
   keytool -export -alias alias -file exported.crt -keystore keystore.jks
  ```

  * Import new CA to trusted certs
  ```
   keytool -import trustcacerts -file ca.pem -alias alias_for_ca -keystore truststore.jks
  ```

  * Check and verify certificate chain is included in keystore
  ```
   keytool -list -v -keystore keystore.jks |grep -A 1 "Owner"
  ```

  * verify a cert
  ```
  openssl verify cert.pem
  ```

  * Retrieve the subject of the Root CA certificate file
  ```
  openssl x509 -noout -subject -in ca.pem
  ```

  * verify the certificate chain using CA
  ```
  openssl verify -CAfile ca.pem cert.pem
  ```
  * verify cert chain using CA and intermediate CA
  ```
  openssl verify -CAfile ca.pem -untrusted intermediate.cert.pem cert.pem
  ```

  * List each cert in order with the issuer and subject from chain cert
  ```
  openssl crl2pkcs7 -nocrl -certfile chain.pem | openssl pkcs7 -print_certs -noout
  ```

  It is required to put the server certificate file first, and then the intermediate certificate file(s)
