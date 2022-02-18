#!/bin/bash

export TAG=7.0.1

echo "----------Start Openldap---------"
docker-compose up -d --build --no-deps openldap
echo "Done"
echo
echo
echo "----------Start zookeeper and broker -------------"
docker-compose up -d --build --no-deps zookeeper3 zookeeper1 zookeeper2 kafka3 kafka1 kafka2
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
    send "superUser\r";
    expect "Password: "
    send "superUser\r";
    expect "Logged in as "
    set result $expect_out(buffer)
END
)

echo "$OUTPUT"

  if [[ ! "$OUTPUT" =~ "Logged in as" ]]; then
    echo "Failed to log into MDS.  Please check all parameters and run again"
    exit 1
  fi

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
sasl.jaas.config=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username="normalUser" password="normalUser" metadataServerUrls="https://kafka1:1090,https://kafka2:2090";
EOF'
echo
echo "Setup config for mTls port"
docker-compose exec kafka1 bash -c 'cat << EOF > /tmp/client-ssl.properties
security.protocol=SSL
ssl.keystore.location=/etc/kafka/secrets/client.keystore.jks
ssl.keystore.password=confluent
ssl.truststore.location=/etc/kafka/secrets/client.truststore.jks
ssl.truststore.password=confluent
ssl.key.password=confluent
EOF'
echo "client  user from client keystore has to be granted role bindings"
confluent iam rolebinding create \
    --principal User:client \
    --role ResourceOwner \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --resource Topic:_confluent-license
echo
echo 
echo "---- Setup Rest Proxy ---"
confluent iam rolebinding create --principal User:restAdmin --role DeveloperRead --resource Topic:_confluent-license --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rolebinding create --principal User:restAdmin --role DeveloperWrite --resource Topic:_confluent-license --kafka-cluster-id $KAFKA_CLUSTER_ID
echo
echo
echo "----Setup Schema Registry ----"
export SR_CLUSTER_ID=schema-registry
echo
echo ">> Adding role binding for user schemaregistryUser"
confluent iam rolebinding create \
    --principal User:schemaregistryUser \
    --role SecurityAdmin \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --schema-registry-cluster-id $SR_CLUSTER_ID

confluent iam rolebinding create \
    --principal User:schemaregistryUser \
    --role ClusterAdmin \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal User:schemaregistryUser \
    --role ResourceOwner \
    --resource Topic:_confluent-license \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

for resource in Topic:_schemas Group:schema-registry
do
    confluent iam rolebinding create \
        --principal User:schemaregistryUser \
        --role ResourceOwner \
        --resource $resource \
        --kafka-cluster-id $KAFKA_CLUSTER_ID
done
echo
echo ">> Starting up schema registry"
docker-compose up -d --build --no-deps schemaregistry &>/dev/null
echo
echo
echo "-------------------------------------------------------------------"
echo
echo
echo "----Setup Kafka Connect------------"
echo
export CONNECT_CLUSTER_ID=connect-cluster
echo ">> Download datagen connector"
mkdir -p ./jar/datagen
ls ./jar/datagen/confluentinc-kafka-connect-datagen/lib/kafka-connect-datagen-*.jar || confluent-hub install  --component-dir ./jar/datagen confluentinc/kafka-connect-datagen:latest --no-prompt
echo "Done"
echo ">> Download replicator connector"
ls ./jar/confluentinc-kafka-connect-replicator/lib/replicator-rest-extension-*.jar || confluent-hub install --no-prompt --component-dir ./jar confluentinc/kafka-connect-replicator:latest
echo
echo ">> Adding role binding for connectAdmin"
confluent iam rolebinding create --principal User:connectAdmin --role SecurityAdmin --kafka-cluster-id $KAFKA_CLUSTER_ID --connect-cluster-id $CONNECT_CLUSTER_ID
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
    confluent iam rolebinding create \
        --principal User:connectAdmin \
        --role ResourceOwner \
        --resource $resource \
        --kafka-cluster-id $KAFKA_CLUSTER_ID
done

echo
echo
echo ">> Starting up Kafka connect"
docker-compose up -d --build --no-deps connect
echo
echo
CONNECT_STARTED=false
while [ $CONNECT_STARTED == false ]
do
    docker-compose logs connect | grep "Herder started" &> /dev/null
    if [ $? -eq 0 ]; then
      CONNECT_STARTED=true
      echo "Kafka connect is started and ready"
    else
      echo "Waiting for Kafka Connect..."
    fi
    sleep 5
done

echo ">> Add role binding for connectorUser for managing connectors"
confluent iam rolebinding create --principal User:connectorUser --role ResourceOwner --resource Connector:datagen-users --kafka-cluster-id $KAFKA_CLUSTER_ID --connect-cluster-id $CONNECT_CLUSTER_ID
confluent iam rolebinding create --principal User:connectorUser --role ResourceOwner --resource Connector:datagen-pageviews --kafka-cluster-id $KAFKA_CLUSTER_ID --connect-cluster-id $CONNECT_CLUSTER_ID

#Idempotent producers require cluster write
confluent iam rolebinding create --principal User:connectorUser --role DeveloperWrite --resource Cluster:kafka-cluster --kafka-cluster-id $KAFKA_CLUSTER_ID

#confluent iam rolebinding create --principal User:connectorUser --role ResourceOwner --resource Group:connect-datagen-users --kafka-cluster-id $KAFKA_CLUSTER_ID
#confluent iam rolebinding create --principal User:connectorUser --role ResourceOwner --resource Group:connect-datagen-pageviews --kafka-cluster-id $KAFKA_CLUSTER_ID
#for connector to access topic, subject
confluent iam rolebinding create --principal User:connectorUser --role ResourceOwner --resource Topic:users --kafka-cluster-id $KAFKA_CLUSTER_ID --prefix
confluent iam rolebinding create --principal User:connectorUser --role ResourceOwner --resource Topic:pageviews --kafka-cluster-id $KAFKA_CLUSTER_ID --prefix
confluent iam rolebinding create --principal User:connectorUser --role ResourceOwner --resource Subject:users --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id $SR_CLUSTER_ID --prefix
confluent iam rolebinding create --principal User:connectorUser --role ResourceOwner --resource Subject:pageviews --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id $SR_CLUSTER_ID --prefix


# User to check all connector status
confluent iam rolebinding create --principal User:connectorViewer --role ResourceOwner --resource 'Connector:*' --kafka-cluster-id $KAFKA_CLUSTER_ID --connect-cluster-id $CONNECT_CLUSTER_ID
confluent iam rolebinding create --principal User:connectorViewer --role ResourceOwner --resource 'Topic:*' --kafka-cluster-id $KAFKA_CLUSTER_ID --prefix
confluent iam rolebinding create --principal User:connectorViewer --role ResourceOwner --resource 'Subject:*' --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id $SR_CLUSTER_ID

echo
echo

echo ">> Add connector: datagen-users"
curl -i -X POST \
    --cacert ./secrets/ca.crt \
    -u connectorUser:connectorUser \
    -H "Accept:application/json" \
    -H  "Content-Type:application/json" \
   https://localhost:8083/connectors/ -d '
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
           "value.converter.schema.registry.url": "https://schemaregistry:8081",
           "value.converter.schema.registry.ssl.truststore.location": "/etc/kafka/secrets/connect.truststore.jks",
           "value.converter.schema.registry.ssl.truststore.password": "confluent",
           "value.converter.basic.auth.credentials.source": "USER_INFO",
           "value.converter.basic.auth.user.info": "connectorUser:connectorUser",
           "tasks.max": "1",
           "iterations": "1000000000",
           "producer.override.sasl.jaas.config": "org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username=\"connectorUser\" password=\"connectorUser\" metadataServerUrls=\"https://kafka1:1090,https://kafka2:2090\";"
       }
   }'
echo
echo ">> Check connector status"
echo "Datagen-users: `curl -s --cacert ./secrets/ca.crt -u connectorViewer:connectorViewer https://localhost:8083/connectors/datagen-users/status`"
echo
echo
echo ">> Add connector: datagen-pageviews"
curl -i -X POST \
    --cacert ./secrets/ca.crt \
    --cert ./secrets/connect.certificate.pem --key ./secrets/connect.key \
    -u connectorUser:connectorUser \
    -H "Accept:application/json" \
    -H  "Content-Type:application/json" \
   https://localhost:8083/connectors/ -d '
  {
      "name": "datagen-pageviews",
      "config": {
           "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
           "quickstart": "pageviews",
           "name": "datagen-pageviews",
           "kafka.topic": "pageviews",
           "max.interval": "1000",
           "key.converter": "org.apache.kafka.connect.storage.StringConverter",
           "value.converter": "io.confluent.connect.avro.AvroConverter",
           "value.converter.schema.registry.url": "https://schemaregistry:8081",
           "value.converter.schema.registry.ssl.truststore.location": "/etc/kafka/secrets/connect.truststore.jks",
           "value.converter.schema.registry.ssl.truststore.password": "confluent",
           "value.converter.basic.auth.credentials.source": "USER_INFO",
           "value.converter.basic.auth.user.info": "connectorUser:connectorUser",
           "tasks.max": "1",
           "iterations": "1000000000",
           "producer.override.sasl.jaas.config": "org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username=\"connectorUser\" password=\"connectorUser\" metadataServerUrls=\"https://kafka2:2090,https://kafka1:1090\";"
       }
   }'

echo
echo ">> Check connector status"
echo "Datagen-pageviews: `curl -s --cacert ./secrets/ca.crt -u connectorViewer:connectorViewer https://localhost:8083/connectors/datagen-pageviews/status`"
echo
echo
echo
echo "-----Setup ksqldb-----------"
echo
export KSQLDB_CLUSTER_ID=ksqldb-cluster
echo ">> Add role binding for ksqldb service principal"
confluent iam rolebinding create --principal User:ksqlAdmin --role ResourceOwner --resource KsqlCluster:ksql-cluster --kafka-cluster-id $KAFKA_CLUSTER_ID --ksql-cluster-id $KSQLDB_CLUSTER_ID
#confluent iam rolebinding create --principal User:ksqlAdmin --role SecurityAdmin --kafka-cluster-id $KAFKA_CLUSTER_ID --ksql-cluster-id $KSQLDB_CLUSTER_ID
confluent iam rolebinding create --principal User:ksqlAdmin --role ResourceOwner --resource Topic:_confluent-ksql-${KSQLDB_CLUSTER_ID}_command_topic --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rolebinding create --principal User:ksqlAdmin --role ResourceOwner --resource Topic:${KSQLDB_CLUSTER_ID}ksql_processing_log --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rolebinding create --principal User:ksqlAdmin --role DeveloperWrite --resource TransactionalId:$KSQLDB_CLUSTER_ID --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rolebinding create --principal User:ksqlAdmin --role ResourceOwner --resource Group:_confluent-ksql-${KSQLDB_CLUSTER_ID} --prefix --kafka-cluster-id $KAFKA_CLUSTER_ID
#role for idempotent producers
confluent iam rolebinding create --principal User:ksqlAdmin --role DeveloperWrite --resource Cluster:kafka-cluster --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create --principal User:ksqlAdmin --role ResourceOwner --resource Topic:_confluent-ksql-${KSQLDB_CLUSTER_ID} --prefix --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rolebinding create --principal User:ksqlAdmin --role ResourceOwner --resource Subject:_confluent-ksql-${KSQLDB_CLUSTER_ID} --prefix --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id $SR_CLUSTER_ID
confluent iam rolebinding create --principal User:ksqlAdmin --role ResourceOwner --resource Topic:_confluent-monitoring --kafka-cluster-id $KAFKA_CLUSTER_ID


echo
echo ">> Start ksqldb server"
docker-compose up -d --build --no-deps ksqldb-server
echo
echo
echo "Add role binding for ksqlUser"
confluent iam rolebinding create --principal User:ksqlUser --role DeveloperWrite --resource KsqlCluster:ksql-cluster --kafka-cluster-id $KAFKA_CLUSTER_ID --ksql-cluster-id $KSQLDB_CLUSTER_ID
confluent iam rolebinding create --principal User:ksqlUser --role ResourceOwner --resource Group:_confluent-ksql-${KSQLDB_CLUSTER_ID} --prefix --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rolebinding create --principal User:ksqlUser --role DeveloperRead --resource Topic:${KSQLDB_CLUSTER_ID}ksql_processing_log --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rolebinding create --principal User:ksqlUser --role ResourceOwner --resource Topic:_confluent-ksql-${KSQLDB_CLUSTER_ID} --prefix --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rolebinding create --principal User:ksqlUser --role ResourceOwner --resource Subject:_confluent-ksql-${KSQLDB_CLUSTER_ID} --prefix --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id $SR_CLUSTER_ID
# role for monitoring topic for interceptor
confluent iam rolebinding create --principal User:ksqlUser --role ResourceOwner --resource Topic:_confluent-monitoring --kafka-cluster-id $KAFKA_CLUSTER_ID

#roles for ksqlUser on resources
confluent iam rolebinding create --principal User:ksqlUser --role ResourceOwner --resource Topic:users --kafka-cluster-id $KAFKA_CLUSTER_ID --prefix
confluent iam rolebinding create --principal User:ksqlUser --role ResourceOwner --resource Subject:users --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id $SR_CLUSTER_ID --prefix
confluent iam rolebinding create --principal User:ksqlUser --role ResourceOwner --resource Topic:pageviews --kafka-cluster-id $KAFKA_CLUSTER_ID --prefix
confluent iam rolebinding create --principal User:ksqlUser --role ResourceOwner --resource Subject:pageviews --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id $SR_CLUSTER_ID --prefix
#roles for ksqlAdmin on resources
confluent iam rolebinding create --principal User:ksqlAdmin --role ResourceOwner --resource Topic:users --kafka-cluster-id $KAFKA_CLUSTER_ID --prefix
confluent iam rolebinding create --principal User:ksqlAdmin --role ResourceOwner --resource Subject:users --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id $SR_CLUSTER_ID --prefix
confluent iam rolebinding create --principal User:ksqlAdmin --role ResourceOwner --resource Topic:pageviews --kafka-cluster-id $KAFKA_CLUSTER_ID --prefix
confluent iam rolebinding create --principal User:ksqlAdmin --role ResourceOwner --resource Subject:pageviews --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id $SR_CLUSTER_ID --prefix

# roles for ksqlUser to run SELECT from stream or table
confluent iam rolebinding create --principal User:ksqlUser --role ResourceOwner --resource Topic:_confluent-ksql-${KSQLDB_CLUSTER_ID}transient --prefix --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rolebinding create --principal User:ksqlUser --role ResourceOwner --resource Subject:_confluent-ksql-${KSQLDB_CLUSTER_ID}transient --prefix --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id $SR_CLUSTER_ID

# roles to create table
confluent iam rolebinding create --principal User:ksqlAdmin --role ResourceOwner --resource Topic:_confluent-ksql-${KSQLDB_CLUSTER_ID}transient --prefix --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rolebinding create --principal User:ksqlAdmin --role ResourceOwner --resource Subject:_confluent-ksql-${KSQLDB_CLUSTER_ID}transient --prefix --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id $SR_CLUSTER_ID
confluent iam rolebinding create --principal User:ksqlAdmin --role ResourceOwner --resource Subject:_confluent-ksql-${KSQLDB_CLUSTER_ID} --prefix --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id $SR_CLUSTER_ID




echo "Waiting"
KSQL_STARTED=false
while [ $KSQL_STARTED == false ]
do
    docker-compose logs ksqldb-server | grep "Server up and running" &> /dev/null
    if [ $? -eq 0 ]; then
      KSQL_STARTED=true
      echo "KSQLDB is started and ready"
    else
      echo "Waiting for KSQLDB to start..."
    fi
    sleep 5
done
echo

echo
docker-compose exec ksqldb-server bash -c "cat << EOF > /tmp/client.properties
ssl.truststore.location=/etc/kafka/secrets/ksqldb-server.truststore.jks
ssl.truststore.password=confluent
EOF"

echo "Start ksql streams and queries"
docker-compose exec ksqldb-server bash -c "ksql --config-file /tmp/client.properties -u ksqlUser -p ksqlUser https://localhost:8088 <<EOF
SET 'auto.offset.reset'='earliest';
CREATE STREAM pageviews (viewtime BIGINT, userid VARCHAR, pageid VARCHAR) WITH (KAFKA_TOPIC='pageviews', VALUE_FORMAT='AVRO');
CREATE TABLE users (userid VARCHAR PRIMARY KEY, registertime BIGINT, gender VARCHAR, regionid VARCHAR) WITH (KAFKA_TOPIC='users', VALUE_FORMAT='AVRO');
CREATE STREAM pageviews_female with (KAFKA_TOPIC='pageviews_female') AS SELECT users.userid AS userid, pageid, regionid, gender FROM pageviews LEFT JOIN users ON pageviews.userid = users.userid WHERE gender = 'FEMALE';
CREATE STREAM pageviews_female_like_89 WITH (kafka_topic='pageviews_enriched_r8_r9', value_format='AVRO') AS SELECT * FROM pageviews_female WHERE regionid LIKE '%_8' OR regionid LIKE '%_9';
CREATE TABLE pageviews_regions WITH (kafka_topic='pageviews_regions', value_format='AVRO', KEY_FORMAT='avro') AS SELECT gender, regionid , COUNT(*) AS numusers FROM pageviews_female WINDOW TUMBLING (size 30 second) GROUP BY gender, regionid HAVING COUNT(*) > 1;
exit ;
EOF"


echo "---Setup role binding for c3Admin user for C3"
confluent iam rolebinding create --principal User:c3Admin --role SystemAdmin --kafka-cluster-id $KAFKA_CLUSTER_ID

echo "Done"
echo
echo ">> start C3"
docker-compose up -d --build --no-deps controlcenter
echo

echo ">> Add role binding for c3User -- c3User is Kafka ldap group"
echo "   (all Operator role)"
echo "   * Permission for Kafka cluster"
confluent iam rolebinding create --kafka-cluster-id $KAFKA_CLUSTER_ID --principal User:c3User --role ClusterAdmin
echo "   * Permission for Connect cluster"
confluent iam rolebinding create --kafka-cluster-id $KAFKA_CLUSTER_ID --principal User:c3User --role ClusterAdmin --connect-cluster-id $CONNECT_CLUSTER_ID
echo "   * Permission for schema registry"
confluent iam rolebinding create --kafka-cluster-id $KAFKA_CLUSTER_ID --principal User:c3User --role ClusterAdmin --schema-registry-cluster-id $SR_CLUSTER_ID
echo "   * Permission for ksqldb"
confluent iam rolebinding create --kafka-cluster-id $KAFKA_CLUSTER_ID --principal User:c3User --role ClusterAdmin --ksql-cluster-id $KSQLDB_CLUSTER_ID
