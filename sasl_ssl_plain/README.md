* mtls setup between zookeeper and kafka
  Use zookeeper-shell to connect requires export JVM variables, or log into broker container to connect
```
export KAFKA_OPTS="-Dzookeeper.clientCnxnSocket=org.apache.zookeeper.ClientCnxnSocketNetty
        -Dzookeeper.client.secure=true
        -Dzookeeper.ssl.keyStore.location=./secrets/client.keystore.jks
        -Dzookeeper.ssl.keyStore.password=confluent
        -Dzookeeper.ssl.trustStore.location=./secrets/client.truststore.jks
        -Dzookeeper.ssl.trustStore.password=confluent"

zookeeper-shell localhost:2182
```

* kafka:
  ldap enabled on port 9094

* C3 is enabled with ldap basic auth 
  login: superUser/superUser
