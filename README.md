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
    * C3 has ldap authentication
