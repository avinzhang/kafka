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


