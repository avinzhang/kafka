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

# Cluster-linking:
  * cluster-linking
    
# ksqldb:
  * ksql.sh - full cluster with ksql streams and tables 
    
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

