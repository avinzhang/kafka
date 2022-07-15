#!/bin/bash

#CLOUD_CLUSTER_ENDPOINT=`terraform -chdir=./cloud output -json | jq -r '."cloud-cluster-endpoint"."value"'`
#REPLICATOR_API_KEY=`terraform -chdir=./cloud output -json | jq -r '."replicator-api-key"."value"'`
#REPLICATOR_API_SECRET=`terraform -chdir=./cloud output -json | jq -r '."replicator-api-secret"."value"'`

curl -i -X POST \
    --cacert ./secrets/ca.crt \
    -u connectUser:connectUser \
    -H "Accept:application/json" \
    -H  "Content-Type:application/json" \
   https://localhost:8083/connectors/ -d '
  {
      "name": "replicator",
      "config": {
           "connector.class": "io.confluent.connect.replicator.ReplicatorSourceConnector",
           "tasks.max": "1",
           "name": "replicator",
           "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
           "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
           "topic.config.sync": "false",
           "topic.whitelist": "users",
           "confluent.topic.replication.factor": "3",
           "src.kafka.bootstrap.servers": "kafka1:1094,kafka2:2094,kafka3:3094",
           "src.kafka.security.protocol": "SASL_PLAINTEXT",
           "src.kafka.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"connectUser\" password=\"connectUser\";",
           "src.kafka.sasl.mechanism": "PLAIN",
           "src.consumer.group.id": "connect-replicator",
           "dest.kafka.bootstrap.servers": "pkc-ldvj1.ap-southeast-2.aws.confluent.cloud:9092",
           "dest.kafka.security.protocol": "SASL_SSL",
           "dest.kafka.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"NXHICQQ2HJNJ2POT\" password=\"bZSZXlZ3rnG2SJwFNEACKxprxuVruiv9HSE0BZ1JlHfIogIx1VSlZdM4z0RWWHuK\";",
           "dest.kafka.ssl.truststore.location": "/etc/kafka/secrets/cacerts",
           "dest.kafka.ssl.truststore.password": "changeit",
           "dest.kafka.sasl.mechanism": "PLAIN",
           "offset.timestamps.commit": "false",
           "producer.override.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"NXHICQQ2HJNJ2POT\" password=\"bZSZXlZ3rnG2SJwFNEACKxprxuVruiv9HSE0BZ1JlHfIogIx1VSlZdM4z0RWWHuK\";",
           "producer.override.security.protocol": "SASL_SSL",
           "producer.override.sasl.mechanism":"PLAIN",
           "producer.override.bootstrap.servers": "pkc-ldvj1.ap-southeast-2.aws.confluent.cloud:9092",
           "producer.override.ssl.truststore.location": "/etc/kafka/secrets/cacerts",
           "producer.override.ssl.truststore.password": "changeit",
           "producer.override.sasl.login.callback.handler.class": "org.apache.kafka.common.security.authenticator.AbstractLogin$DefaultLoginCallbackHandler",
           "provenance.header.enable": "false"
       }
   }'

sleep 10
echo
echo "* Check replicator status"
echo "  Replicator:  `curl -sk -u connectUser:connectUser https://localhost:8083/connectors/replicator/status | jq .connector.state`"
