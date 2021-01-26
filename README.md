# Connectors:
  * couchbase-source
  * hdfs-sink
  * jdbc: 
    * source to mysql
    * sink to postgres
  * s3-sink.sh
    * jdbc source to postgres
    * s3 sink to s3
  * splunk-source
  * spooldir-source
  * sqlserver
    * using jdbc source to sqlserver
    
# Security:
  * zookeeper mtls
  * sasl_ssl_plain
    * sasl_ssl with plain for all components.  
    * ldap enabled on port 9094 on broker
      ```
      kafka-topics --bootstrap-server localhost:9094 --command-config ./security/sasl_ssl_plain/client.properties --list
      ```
    * C3 has ldap authentication
  * restproxy-principal-propagation
    * restproxy-basic-to-sasl 
