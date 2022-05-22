# CP cluster with RBAC 
  * Zookeepers
    * mTls between zookeepers and brokers
    * brokers must use the same cert to connect to zookeepers
    * brokers will use sasl over mTls if both are enabled. 


  * Brokers
    * port 1092 - plaintext
    * port 1093 - sasl_ssl oauthbearer
    * port 1094 - sasl_plain for broker internal components
    * port 1095 - mtls
      * role binding has to be added as well for the DN for the cert
    * port 1096 - ldap enabled

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



