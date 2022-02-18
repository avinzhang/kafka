#!/bin/bash

export TAG=7.0.1
datagen_version=latest
replicator_version=7.0.1

echo "----Download datagen connector-----------"
mkdir -p ./jar/datagen
ls ./jar/datagen/confluentinc-kafka-connect-datagen/lib/kafka-connect-datagen-*.jar || confluent-hub install  --component-dir ./jar/datagen confluentinc/kafka-connect-datagen:$datagen_version --no-prompt
echo "Done"
echo "---Download replicator"
ls ./jar/confluentinc-kafka-connect-replicator/lib/connect-replicator-$replicator_version.jar || confluent-hub install  --component-dir ./jar confluentinc/kafka-connect-replicator:$replicator_version --no-prompt
echo

echo "----------Start Openldap---------"
docker-compose up -d --build --no-deps openldap
echo "Done"
echo
STARTED=false
while [ $STARTED == false ]
do
    docker-compose logs openldap | grep "started" &> /dev/null
    if [ $? -eq 0 ]; then
      STARTED=true
      echo "Openldap is started and ready"
    else
      echo "Waiting for Openldap to start..."
    fi
    sleep 5
done
echo
echo "----------Start zookeeper and broker -------------"
docker-compose up -d --build --no-deps zookeeper1 kafka1 zookeeper2 kafka2 
echo "Done"
echo
echo
MDS_STARTED=false
while [ $MDS_STARTED == false ]
do
    docker-compose logs kafka1 | grep "Started NetworkTrafficServerConnector" &> /dev/null
    if [ $? -eq 0 ]; then
      MDS_STARTED=true
      echo "MDS is started and ready"
    else
      echo "Waiting for MDS to start..."
    fi
    sleep 5
done


OUTPUT=$(
  expect <<END
    log_user 1
    spawn confluent login --url https://localhost:1090 --ca-cert-path ./secrets/ca.crt
    expect "Username: "
    send "mds\r";
    expect "Password: "
    send "mds\r";
    expect "Logged in as "
    set result $expect_out(buffer)
END
)

KAFKA_CLUSTER_ID=`curl -sik https://localhost:1090/v1/metadata/id |grep id |jq -r ".id"`
if [ -z "$KAFKA_CLUSTER_ID" ]; then
    echo "Failed to retrieve kafka cluster id from MDS"
    exit 1
fi
echo "Cluster ID is $KAFKA_CLUSTER_ID"
echo
echo "Setup config file for token port"
docker-compose exec kafka1 bash -c 'cat << EOF > /tmp/client-rbac.properties
sasl.mechanism=OAUTHBEARER
security.protocol=SASL_SSL
ssl.truststore.location=/etc/kafka/secrets/client.truststore.jks
ssl.truststore.password=confluent
sasl.login.callback.handler.class=io.confluent.kafka.clients.plugins.auth.token.TokenUserLoginCallbackHandler
sasl.jaas.config=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username="user1" password="user1" metadataServerUrls="https://kafka1:1090";
EOF'
echo
echo
echo ">> Adding role binding for user schemaregistryUser"
confluent iam rbac role-binding create \
    --principal User:schemaregistry \
    --role SecurityAdmin \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --schema-registry-cluster-id schema-registry

confluent iam rbac role-binding create \
    --principal User:schemaregistry \
    --role ClusterAdmin \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rbac role-binding create \
    --principal User:schemaregistry \
    --role ResourceOwner \
    --resource Topic:_confluent-license \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

for resource in Topic:_schemas Topic:_confluent-command Group:schema-registry
do
    confluent iam rbac role-binding create \
        --principal User:schemaregistry \
        --role ResourceOwner \
        --resource $resource \
        --kafka-cluster-id $KAFKA_CLUSTER_ID
done
echo
echo ">> Starting up schema registry"
docker-compose up -d --build --no-deps schemaregistry &>/dev/null
echo
echo ">> Adding role binding for connectAdmin on cluster1"
confluent iam rbac role-binding create --principal User:connectAdmin --role SecurityAdmin --kafka-cluster-id $KAFKA_CLUSTER_ID --connect-cluster-id connect-cluster
# ResourceOwner for groups and topics on broker
declare -a ConnectResources=(
    "Topic:connect-configs"
    "Topic:connect-offsets"
    "Topic:connect-status"
    "Group:connect-cluster"
    "Topic:_confluent-monitoring"
    "Topic:_confluent-secrets"
    "Topic:_confluent-command"
    "Group:secret-registry"
)
for resource in ${ConnectResources[@]}
do
    confluent iam rbac role-binding create \
        --principal User:connectAdmin \
        --role ResourceOwner \
        --resource $resource \
        --kafka-cluster-id $KAFKA_CLUSTER_ID
done
docker-compose up -d --build --no-deps connect1
echo
echo
connect_ready=false
while [ $connect_ready == false ]
do
    docker-compose logs connect1|grep "Herder started" &> /dev/null
    if [ $? -eq 0 ]; then
      connect_ready=true
      echo "*** Source Kafka Connect is ready ****"
    else
      echo ">>> Waiting for Source kafka connect to start"
    fi
    sleep 5
done
echo
echo ">> Add role binding for connectorUser for managing connectors"
confluent iam rbac role-binding create --principal User:connectUser --role ResourceOwner --resource Connector:datagen-users --kafka-cluster-id $KAFKA_CLUSTER_ID --connect-cluster-id connect-cluster

#Idempotent producers require cluster write
confluent iam rbac role-binding create --principal User:connectUser --role DeveloperWrite --resource Cluster:kafka-cluster --kafka-cluster-id connect-cluster

confluent iam rbac role-binding create --principal User:connectUser --role ResourceOwner --resource Group:connect-datagen-users --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rbac role-binding create --principal User:connectUser --role ResourceOwner --resource Group:connect-replicator --kafka-cluster-id $KAFKA_CLUSTER_ID

# for using connectUser to consume with schema registry on cluster2
confluent iam rbac role-binding create --principal User:connectUser --role ResourceOwner --resource Subject::users --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id schema-registry --prefix

#for connector to access topic, subject
confluent iam rbac role-binding create --principal User:connectUser --role ResourceOwner --resource Topic:users --kafka-cluster-id $KAFKA_CLUSTER_ID --prefix
confluent iam rbac role-binding create --principal User:connectUser --role ResourceOwner --resource Subject:users --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id schema-registry --prefix

echo
echo "* Create datagen-user connector"
curl -i -X POST \
    --cacert ./secrets/ca.crt \
    -u connectUser:connectUser \
    -H "Accept:application/json" \
    -H  "Content-Type:application/json" \
   https://localhost:1083/connectors/ -d '
  {
      "name": "datagen-users",
      "config": {
           "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
           "quickstart": "users",
           "name": "datagen-users",
           "kafka.topic": "users",
           "max.interval": "1000",
           "key.converter": "org.apache.kafka.connect.storage.StringConverter",
           "value.converter": "io.confluent.connect.avro.AvroConverter",
           "value.converter.schema.registry.url": "https://schemaregistry:1081",
           "value.converter.schema.registry.ssl.truststore.location": "/etc/kafka/secrets/connect.truststore.jks",
           "value.converter.schema.registry.ssl.truststore.password": "confluent",
           "value.converter.basic.auth.credentials.source": "USER_INFO",
           "value.converter.basic.auth.user.info": "connectUser:connectUser",
           "tasks.max": "1",
           "iterations": "1000000000",
           "producer.override.sasl.jaas.config": "org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username=\"connectUser\" password=\"connectUser\" metadataServerUrls=\"https://kafka1:1090\";"
       }
   }'
echo

sleep 3
echo "* Check connector status"
echo "  datagen-users:  `curl -sk -u connectUser:connectUser https://localhost:1083/connectors/datagen-users/status | jq .connector.state`"
echo
echo
MDS_STARTED=false
while [ $MDS_STARTED == false ]
do
    docker-compose logs kafka2 | grep "Started NetworkTrafficServerConnector" &> /dev/null
    if [ $? -eq 0 ]; then
      MDS_STARTED=true
      echo "MDS on cluster2 is started and ready"
    else
      echo "Waiting for MDS on cluster2 to start..."
    fi
    sleep 5
done


OUTPUT=$(
  expect <<END
    log_user 1
    spawn confluent login --url https://localhost:2090 --ca-cert-path ./secrets/ca.crt
    expect "Username: "
    send "mds\r";
    expect "Password: "
    send "mds\r";
    expect "Logged in as "
    set result $expect_out(buffer)
END
)

KAFKA_CLUSTER_ID=`curl -sik https://localhost:2090/v1/metadata/id |grep id |jq -r ".id"`
if [ -z "$KAFKA_CLUSTER_ID" ]; then
    echo "Failed to retrieve kafka cluster id from MDS"
    exit 1
fi
echo "Cluster ID is $KAFKA_CLUSTER_ID"
echo
echo "Setup config file for token port"
docker-compose exec kafka2 bash -c 'cat << EOF > /tmp/client-rbac.properties
bootstrap.servers=kafka2:2093
sasl.mechanism=OAUTHBEARER
security.protocol=SASL_SSL
ssl.truststore.location=/etc/kafka/secrets/client.truststore.jks
ssl.truststore.password=confluent
sasl.login.callback.handler.class=io.confluent.kafka.clients.plugins.auth.token.TokenUserLoginCallbackHandler
sasl.jaas.config=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username="connectUser" password="connectUser" metadataServerUrls="https://kafka2:2090";
EOF'
echo
echo ">> Adding role binding for connectAdmin on cluster2"
confluent iam rbac role-binding create --principal User:connectAdmin --role SecurityAdmin --kafka-cluster-id $KAFKA_CLUSTER_ID --connect-cluster-id connect-cluster
# ResourceOwner for groups and topics on broker
declare -a ConnectResources=(
    "Topic:connect-configs"
    "Topic:connect-offsets"
    "Topic:connect-status"
    "Group:connect-cluster"
    "Topic:_confluent-monitoring"
    "Topic:_confluent-secrets"
    "Topic:_confluent-command"
    "Group:secret-registry"
)
for resource in ${ConnectResources[@]}
do
    confluent iam rbac role-binding create \
        --principal User:connectAdmin \
        --role ResourceOwner \
        --resource $resource \
        --kafka-cluster-id $KAFKA_CLUSTER_ID
done
docker-compose up -d --build --no-deps connect2
echo

connect_ready=false
while [ $connect_ready == false ]
do
    docker-compose logs connect2|grep "Herder started" &> /dev/null
    if [ $? -eq 0 ]; then
      connect_ready=true
      echo "*** Dest Kafka Connect is ready ****"
    else
      echo ">>> Waiting for Dest kafka connect to start"
    fi
    sleep 5
done
echo
echo ">> Add role binding for connectorUser for managing connectors"
confluent iam rbac role-binding create --principal User:connectUser --role ResourceOwner --resource Connector:replicator --kafka-cluster-id $KAFKA_CLUSTER_ID --connect-cluster-id connect-cluster

#Idempotent producers require cluster write
confluent iam rbac role-binding create --principal User:connectUser --role DeveloperWrite --resource Cluster:kafka-cluster --kafka-cluster-id connect-cluster

#for connector to access topic, subject
confluent iam rbac role-binding create --principal User:connectUser --role ResourceOwner --resource Topic:users --kafka-cluster-id $KAFKA_CLUSTER_ID --prefix
confluent iam rbac role-binding create --principal User:connectUser --role ResourceOwner --resource Subject::users --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id schema-registry --prefix

confluent iam rbac role-binding create --principal User:connectUser --role ResourceOwner --resource Topic:_confluent --prefix --kafka-cluster-id $KAFKA_CLUSTER_ID


echo ">>Create replicator connector on destination cluster"
curl -i -X POST \
    --cacert ./secrets/ca.crt \
    --cert ./secrets/connect.certificate.pem --key ./secrets/connect.key \
    -u connectUser:connectUser \
    -H "Accept:application/json" \
    -H  "Content-Type:application/json" \
   https://localhost:2083/connectors/ -d '
  {
      "name": "replicator",
      "config": {
           "connector.class": "io.confluent.connect.replicator.ReplicatorSourceConnector",
           "tasks.max": 1,
           "name": "replicator",
           "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
           "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
           "topic.config.sync": "false",
           "topic.whitelist":"users",
           "confluent.topic.replication.factor": "1",
           "src.kafka.bootstrap.servers":"kafka1:1093",
           "src.kafka.security.protocol": "SASL_SSL",
           "src.kafka.ssl.truststore.location": "/etc/kafka/secrets/connect.truststore.jks",
           "src.kafka.ssl.truststore.password": "confluent",
           "src.kafka.sasl.login.callback.handler.class": "io.confluent.kafka.clients.plugins.auth.token.TokenUserLoginCallbackHandler",
           "src.kafka.sasl.jaas.config": "org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username=\"connectUser\" password=\"connectUser\" metadataServerUrls=\"https://kafka1:1090\";",
           "src.kafka.sasl.mechanism": "OAUTHBEARER",
           "src.consumer.group.id": "connect-replicator",
           "dest.kafka.bootstrap.servers": "kafka2:2093",
           "dest.kafka.security.protocol": "SASL_SSL",
           "dest.kafka.ssl.truststore.location": "/etc/kafka/secrets/connect.truststore.jks",
           "dest.kafka.ssl.truststore.password": "confluent",
           "dest.kafka.sasl.login.callback.handler.class": "io.confluent.kafka.clients.plugins.auth.token.TokenUserLoginCallbackHandler",
           "dest.kafka.sasl.jaas.config": "org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username=\"connectUser\" password=\"connectUser\" metadataServerUrls=\"https://kafka2:2090\";",
           "dest.kafka.sasl.mechanism": "OAUTHBEARER",
           "offset.timestamps.commit": "false",
           "producer.override.sasl.jaas.config": "org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username=\"connectUser\" password=\"connectUser\" metadataServerUrls=\"https://kafka2:2090\";",
           "consumer.override.sasl.jaas.config": "org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username=\"connectUser\" password=\"connectUser\" metadataServerUrls=\"https://kafka1:1090\";",
           "provenance.header.enable": "false"
       }
   }'

sleep 3
echo
echo "* Check replicator status"
echo "  Replicator:  `curl -sk -u connectUser:connectUser https://localhost:2083/connectors/replicator/status | jq .connector.state`"

echo "Create role binding for console consumer on cluster2"
confluent iam rbac role-binding create --principal User:connectUser --role ResourceOwner --resource Group:console-consumer --kafka-cluster-id $KAFKA_CLUSTER_ID --prefix 
echo "Setup config file for token port"
docker-compose exec connect2 bash -c 'cat << EOF > /tmp/client-rbac.properties
bootstrap.servers=kafka2:2093
sasl.mechanism=OAUTHBEARER
security.protocol=SASL_SSL
ssl.truststore.location=/etc/kafka/secrets/client.truststore.jks
ssl.truststore.password=confluent
sasl.login.callback.handler.class=io.confluent.kafka.clients.plugins.auth.token.TokenUserLoginCallbackHandler
sasl.jaas.config=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username="connectUser" password="connectUser" metadataServerUrls="https://kafka2:2090";
EOF'
echo

echo "Consume from user topic on cluster2"
docker-compose exec connect2 kafka-avro-console-consumer --bootstrap-server kafka2:2093 --consumer.config /tmp/client-rbac.properties --property "schema.registry.url=https://schemaregistry:1081" --property schema.registry.ssl.truststore.location=/etc/kafka/secrets/connect.truststore.jks --property schema.registry.basic.auth.user.info="connectUser:connectUser" --property basic.auth.credentials.source="USER_INFO" --topic users
