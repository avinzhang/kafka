#!/bin/bash

export TAG=7.2.1

echo "----------Start zookeeper" 
docker-compose up -d --build --no-deps zookeeper1 zookeeper2 zookeeper3 
echo
echo
echo "----------Start Openldap---------"
docker-compose up -d --build --no-deps openldap
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
echo
echo "-----------Start brokers"
docker-compose up -d --build --no-deps kafka1 kafka2 kafka3
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
echo
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
echo "****Cluster ID is $KAFKA_CLUSTER_ID"
echo
echo ">>>Check metadata API endpoint"
curl -k -u mds:mds https://localhost:1090/security/1.0/authenticate
echo
echo ">>>Setup config file for token port"
docker-compose exec kafka1 bash -c 'cat << EOF > /tmp/client-rbac.properties
sasl.mechanism=OAUTHBEARER
security.protocol=SASL_SSL
ssl.truststore.location=/etc/kafka/secrets/user1.truststore.jks
ssl.truststore.password=confluent
sasl.login.callback.handler.class=io.confluent.kafka.clients.plugins.auth.token.TokenUserLoginCallbackHandler
sasl.jaas.config=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username="user1" password="user1" metadataServerUrls="https://kafka1:1090";
EOF'
echo
echo ">>>Setup config for mTls port"
docker-compose exec kafka1 bash -c 'cat << EOF > /tmp/client-ssl.properties
security.protocol=SSL
ssl.keystore.location=/etc/kafka/secrets/user1.keystore.jks
ssl.keystore.password=confluent
ssl.truststore.location=/etc/kafka/secrets/user1.truststore.jks
ssl.truststore.password=confluent
ssl.key.password=confluent
EOF'
echo
echo ">>>Add SystemAdmin user"
confluent iam rbac role-binding create --principal User:sysadmin --role SystemAdmin --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rbac role-binding create --principal User:sysadmin --role SystemAdmin --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id schema-registry
confluent iam rbac role-binding create --principal User:sysadmin --role SystemAdmin --kafka-cluster-id $KAFKA_CLUSTER_ID --connect-cluster-id connect-cluster
confluent iam rbac role-binding create --principal User:sysadmin --role SystemAdmin --kafka-cluster-id $KAFKA_CLUSTER_ID --ksql-cluster-id ksqldb-cluster
echo 
echo "---- Setup Rest Proxy ---"
confluent iam rbac role-binding create --principal User:restproxy --role DeveloperRead --resource Topic:_confluent-command --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rbac role-binding create --principal User:restproxy --role DeveloperWrite --resource Topic:_confluent-command --kafka-cluster-id $KAFKA_CLUSTER_ID
echo

echo
echo "----Setup Schema Registry ----"
echo
echo ">> Adding role binding for user schemaregistry"
confluent iam rbac role-binding create \
    --principal User:schemaregistry \
    --role SecurityAdmin \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --schema-registry-cluster-id schema-registry

confluent iam rbac role-binding create \
    --principal User:schemaregistry \
    --role ClusterAdmin \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

for resource in Topic:_schemas Topic:_confluent-command Topic:_confluent-license Group:schema-registry
do
    confluent iam rbac role-binding create \
        --principal User:schemaregistry \
        --role ResourceOwner \
        --resource $resource \
        --kafka-cluster-id $KAFKA_CLUSTER_ID
done
echo
echo ">> Starting up schema registry"
docker-compose up -d --build --no-deps schemaregistry 
echo
echo
echo "-------------------------------------------------------------------"
echo
echo
echo "----Setup Kafka Connect------------"
echo
echo ">> Download datagen connector"
mkdir -p ./confluent-hub-components
ls ./confluent-hub-components/confluentinc-kafka-connect-datagen/lib/kafka-connect-datagen-*.jar || confluent-hub install  --component-dir ./confluent-hub-components confluentinc/kafka-connect-datagen:latest --no-prompt
echo "Done"
echo ">> Download replicator connector"
ls ./confluent-hub-components/confluentinc-kafka-connect-replicator/lib/replicator-rest-extension-*.jar || confluent-hub install --no-prompt --component-dir ./confluent-hub-components confluentinc/kafka-connect-replicator:latest
echo
echo ">>Download S3 sink connector"
ls confluent-hub-components/confluentinc-kafka-connect-s3/lib/kafka-connect-s3-*.jar || confluent-hub install --component-dir ./confluent-hub-components --no-prompt confluentinc/kafka-connect-s3:latest

ls confluent-hub-components/hadoop-mapred-0.22.0.jar|| wget https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-mapred/0.22.0/hadoop-mapred-0.22.0.jar -P ./confluent-hub-components
echo
echo ">> Adding role binding for connectAdmin"
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
docker-compose exec connect bash -c 'cat << EOF > /tmp/client-rbac.properties
sasl.mechanism=OAUTHBEARER
security.protocol=SASL_SSL
ssl.truststore.location=/etc/kafka/secrets/user1.truststore.jks
ssl.truststore.password=confluent
sasl.login.callback.handler.class=io.confluent.kafka.clients.plugins.auth.token.TokenUserLoginCallbackHandler
sasl.jaas.config=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username="connectUser" password="connectUser" metadataServerUrls="https://kafka1:1090";
EOF'

echo ">> Add role binding for connectUser for managing connectors"
confluent iam rbac role-binding create --principal User:connectUser --role ResourceOwner --resource Connector:datagen-users --kafka-cluster-id $KAFKA_CLUSTER_ID --connect-cluster-id connect-cluster
confluent iam rbac role-binding create --principal User:connectUser --role ResourceOwner --resource Connector:datagen-pageviews --kafka-cluster-id $KAFKA_CLUSTER_ID --connect-cluster-id connect-cluster
confluent iam rbac role-binding create --principal User:connectUser --role ResourceOwner --resource Connector:s3-sink --kafka-cluster-id $KAFKA_CLUSTER_ID --connect-cluster-id connect-cluster


# Consumer group permission for sink connector
confluent iam rbac role-binding create --principal User:connectUser --role ResourceOwner --resource Group:connect-s3-sink --kafka-cluster-id $KAFKA_CLUSTER_ID

#Idempotent producers require cluster write
confluent iam rbac role-binding create --principal User:connectUser --role DeveloperWrite --resource Cluster:kafka-cluster --kafka-cluster-id $KAFKA_CLUSTER_ID

#confluent iam rbac role-binding create --principal User:connectUser --role ResourceOwner --resource Group:connect-datagen-users --kafka-cluster-id $KAFKA_CLUSTER_ID
#confluent iam rbac role-binding create --principal User:connectUser --role ResourceOwner --resource Group:connect-datagen-pageviews --kafka-cluster-id $KAFKA_CLUSTER_ID
#for connector to access topic, subject
confluent iam rbac role-binding create --principal User:connectUser --role ResourceOwner --resource Topic:users --kafka-cluster-id $KAFKA_CLUSTER_ID --prefix
confluent iam rbac role-binding create --principal User:connectUser --role ResourceOwner --resource Topic:pageviews --kafka-cluster-id $KAFKA_CLUSTER_ID --prefix
confluent iam rbac role-binding create --principal User:connectUser --role ResourceOwner --resource Subject:users --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id schema-registry --prefix
confluent iam rbac role-binding create --principal User:connectUser --role ResourceOwner --resource Subject:pageviews --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id schema-registry --prefix


# User to check all connector status
#confluent iam rbac role-binding create --principal User:connectorViewer --role ResourceOwner --resource 'Connector:*' --kafka-cluster-id $KAFKA_CLUSTER_ID --connect-cluster-id connect-cluster
#confluent iam rbac role-binding create --principal User:connectorViewer --role ResourceOwner --resource 'Topic:*' --kafka-cluster-id $KAFKA_CLUSTER_ID --prefix
#confluent iam rbac role-binding create --principal User:connectorViewer --role ResourceOwner --resource 'Subject:*' --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id schema-registry

echo
echo "Produce some JSON SCHEMA format messages"
echo
echo ">> Add rbac roles for connectUser"
confluent iam rbac role-binding create --principal User:connectUser --role ResourceOwner --resource Subject:snacks --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id schema-registry --prefix
confluent iam rbac role-binding create --principal User:connectUser --role ResourceOwner --resource Topic:snacks --kafka-cluster-id $KAFKA_CLUSTER_ID --prefix
echo ">> Producing message"
docker-compose exec -T connect kafka-json-schema-console-producer --broker-list kafka1:1093,kafka2:2093,kafka3:3093 --producer.config /tmp/client-rbac.properties --topic snacks_js --property schema.registry.url=https://schemaregistry:8081 --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info=connectUser:connectUser --property schema.registry.ssl.truststore.location=/etc/kafka/secrets/connect.truststore.jks --property schema.registry.ssl.truststore.password=confluent --property value.schema='
{
  "definitions" : {
    "record:myrecord" : {
      "type" : "object",
      "required" : [ "name", "calories" ],
      "additionalProperties" : false,
      "properties" : {
        "name" : {"type" : "string"},
        "calories" : {"type" : "number"},
        "colour" : {"type" : "string"}
      }
    }
  }
}' << EOF
{"name": "cookie", "calories": 500, "colour": "brown"}
{"name": "cake", "calories": 260, "colour": "white"}
{"name": "timtam", "calories": 80, "colour": "chocolate"}
EOF
echo
echo
echo
echo "-----Setup ksqldb-----------"
echo
export KSQLDB_CLUSTER_ID=ksqldb-cluster
echo ">> Add role binding for ksqldb service principal"
confluent iam rbac role-binding create --principal User:ksqldbAdmin --role ResourceOwner --resource KsqlCluster:ksql-cluster --kafka-cluster-id $KAFKA_CLUSTER_ID --ksql-cluster-id $KSQLDB_CLUSTER_ID
#confluent iam rbac role-binding create --principal User:ksqldbAdmin --role SecurityAdmin --kafka-cluster-id $KAFKA_CLUSTER_ID --ksql-cluster-id $KSQLDB_CLUSTER_ID
confluent iam rbac role-binding create --principal User:ksqldbAdmin --role ResourceOwner --resource Topic:_confluent-ksql-${KSQLDB_CLUSTER_ID}_command_topic --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rbac role-binding create --principal User:ksqldbAdmin --role ResourceOwner --resource Topic:${KSQLDB_CLUSTER_ID}ksql_processing_log --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rbac role-binding create --principal User:ksqldbAdmin --role DeveloperWrite --resource TransactionalId:$KSQLDB_CLUSTER_ID --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rbac role-binding create --principal User:ksqldbAdmin --role ResourceOwner --resource Group:_confluent-ksql-${KSQLDB_CLUSTER_ID} --prefix --kafka-cluster-id $KAFKA_CLUSTER_ID
#role for idempotent producers
confluent iam rbac role-binding create --principal User:ksqldbAdmin --role DeveloperWrite --resource Cluster:kafka-cluster --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rbac role-binding create --principal User:ksqldbAdmin --role ResourceOwner --resource Topic:_confluent-ksql-${KSQLDB_CLUSTER_ID} --prefix --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rbac role-binding create --principal User:ksqldbAdmin --role ResourceOwner --resource Subject:_confluent-ksql-${KSQLDB_CLUSTER_ID} --prefix --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id schema-registry
confluent iam rbac role-binding create --principal User:ksqldbAdmin --role ResourceOwner --resource Topic:_confluent-monitoring --kafka-cluster-id $KAFKA_CLUSTER_ID


echo
echo ">> Start ksqldb server"
docker-compose up -d --build --no-deps ksqldb-server
echo
echo
echo "Add role binding for ksqldbUser"
confluent iam rbac role-binding create --principal User:ksqldbUser --role DeveloperWrite --resource KsqlCluster:ksql-cluster --kafka-cluster-id $KAFKA_CLUSTER_ID --ksql-cluster-id $KSQLDB_CLUSTER_ID
confluent iam rbac role-binding create --principal User:ksqldbUser --role ResourceOwner --resource Group:_confluent-ksql-${KSQLDB_CLUSTER_ID} --prefix --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rbac role-binding create --principal User:ksqldbUser --role DeveloperRead --resource Topic:${KSQLDB_CLUSTER_ID}ksql_processing_log --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rbac role-binding create --principal User:ksqldbUser --role ResourceOwner --resource Topic:_confluent-ksql-${KSQLDB_CLUSTER_ID} --prefix --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rbac role-binding create --principal User:ksqldbUser --role ResourceOwner --resource Subject:_confluent-ksql-${KSQLDB_CLUSTER_ID} --prefix --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id schema-registry
# role for monitoring topic for interceptor
confluent iam rbac role-binding create --principal User:ksqldbUser --role ResourceOwner --resource Topic:_confluent-monitoring --kafka-cluster-id $KAFKA_CLUSTER_ID

#roles for ksqldbUser on resources
confluent iam rbac role-binding create --principal User:ksqldbUser --role ResourceOwner --resource Topic:users --kafka-cluster-id $KAFKA_CLUSTER_ID --prefix
confluent iam rbac role-binding create --principal User:ksqldbUser --role ResourceOwner --resource Subject:users --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id schema-registry --prefix
confluent iam rbac role-binding create --principal User:ksqldbUser --role ResourceOwner --resource Topic:pageviews --kafka-cluster-id $KAFKA_CLUSTER_ID --prefix
confluent iam rbac role-binding create --principal User:ksqldbUser --role ResourceOwner --resource Subject:pageviews --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id schema-registry --prefix
#roles for ksqldbAdmin on resources
confluent iam rbac role-binding create --principal User:ksqldbAdmin --role ResourceOwner --resource Topic:users --kafka-cluster-id $KAFKA_CLUSTER_ID --prefix
confluent iam rbac role-binding create --principal User:ksqldbAdmin --role ResourceOwner --resource Subject:users --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id schema-registry --prefix
confluent iam rbac role-binding create --principal User:ksqldbAdmin --role ResourceOwner --resource Topic:pageviews --kafka-cluster-id $KAFKA_CLUSTER_ID --prefix
confluent iam rbac role-binding create --principal User:ksqldbAdmin --role ResourceOwner --resource Subject:pageviews --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id schema-registry --prefix

# roles for ksqldbUser to run SELECT from stream or table
confluent iam rbac role-binding create --principal User:ksqldbUser --role ResourceOwner --resource Topic:_confluent-ksql-${KSQLDB_CLUSTER_ID}transient --prefix --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rbac role-binding create --principal User:ksqldbUser --role ResourceOwner --resource Subject:_confluent-ksql-${KSQLDB_CLUSTER_ID}transient --prefix --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id schema-registry

# roles to create table
confluent iam rbac role-binding create --principal User:ksqldbAdmin --role ResourceOwner --resource Topic:_confluent-ksql-${KSQLDB_CLUSTER_ID}transient --prefix --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rbac role-binding create --principal User:ksqldbAdmin --role ResourceOwner --resource Subject:_confluent-ksql-${KSQLDB_CLUSTER_ID}transient --prefix --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id schema-registry
confluent iam rbac role-binding create --principal User:ksqldbAdmin --role ResourceOwner --resource Subject:_confluent-ksql-${KSQLDB_CLUSTER_ID} --prefix --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id schema-registry


#For JSON schema topics
confluent iam rbac role-binding create --principal User:ksqldbUser --role ResourceOwner --resource Topic:snacks --kafka-cluster-id $KAFKA_CLUSTER_ID --prefix
confluent iam rbac role-binding create --principal User:ksqldbAdmin --role ResourceOwner --resource Topic:snacks --kafka-cluster-id $KAFKA_CLUSTER_ID --prefix
confluent iam rbac role-binding create --principal User:ksqldbUser --role ResourceOwner --resource Subject:snacks --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id schema-registry --prefix
confluent iam rbac role-binding create --principal User:ksqldbAdmin --role ResourceOwner --resource Subject:snacks --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id schema-registry --prefix


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
echo "Using ksqldb to convert JSON schema to Avro"
docker-compose exec ksqldb-server bash -c "ksql --config-file /tmp/client.properties -u ksqldbUser -p ksqldbUser https://localhost:8088 <<EOF
SET 'auto.offset.reset'='earliest';
CREATE STREAM snacks_js (name VARCHAR, calories INT, colour VARCHAR) WITH (KAFKA_TOPIC='snacks_js', VALUE_FORMAT='JSON_SR'); 
CREATE STREAM snacks_avro WITH (KAFKA_TOPIC='snacks_avro', KEY_FORMAT='KAFKA', PARTITIONS=1, VALUE_FORMAT='AVRO') AS SELECT * FROM snacks_js; 
exit;
EOF"


echo "---Setup role binding for c3Admin user for C3"
confluent iam rbac role-binding create --principal User:c3Admin --role SystemAdmin --kafka-cluster-id $KAFKA_CLUSTER_ID

echo "Done"
echo
echo ">> start C3"
docker-compose up -d --build --no-deps controlcenter
echo

echo ">> Add role binding for c3User -- c3User is Kafka ldap group"
echo "   (all Operator role)"
echo "   * Permission for Kafka cluster"
confluent iam rbac role-binding create --kafka-cluster-id $KAFKA_CLUSTER_ID --principal User:c3User --role ClusterAdmin
echo "   * Permission for Connect cluster"
confluent iam rbac role-binding create --kafka-cluster-id $KAFKA_CLUSTER_ID --principal User:c3User --role ClusterAdmin --connect-cluster-id connect-cluster
echo "   * Permission for schema registry"
confluent iam rbac role-binding create --kafka-cluster-id $KAFKA_CLUSTER_ID --principal User:c3User --role ClusterAdmin --schema-registry-cluster-id schema-registry
echo "   * Permission for ksqldb"
confluent iam rbac role-binding create --kafka-cluster-id $KAFKA_CLUSTER_ID --principal User:c3User --role ClusterAdmin --ksql-cluster-id $KSQLDB_CLUSTER_ID

echo ">> Test group permission: add role for c3users group"
echo ">> user2 belongs to c3users group"
confluent iam rbac role-binding create --kafka-cluster-id $KAFKA_CLUSTER_ID --principal Group:c3users --role ClusterAdmin
echo "   * Permission for Connect cluster"
confluent iam rbac role-binding create --kafka-cluster-id $KAFKA_CLUSTER_ID --principal User:c3users --role ClusterAdmin --connect-cluster-id connect-cluster
echo "   * Permission for schema registry"
confluent iam rbac role-binding create --kafka-cluster-id $KAFKA_CLUSTER_ID --principal User:c3users --role ClusterAdmin --schema-registry-cluster-id schema-registry
echo "   * Permission for ksqldb"
confluent iam rbac role-binding create --kafka-cluster-id $KAFKA_CLUSTER_ID --principal User:c3users --role ClusterAdmin --ksql-cluster-id $KSQLDB_CLUSTER_ID

# role binding for c3User to run ksqldb select queries
confluent iam rbac role-binding create --principal User:c3User --role ResourceOwner --resource Topic:users --kafka-cluster-id $KAFKA_CLUSTER_ID --prefix
confluent iam rbac role-binding create --principal User:c3User --role ResourceOwner --resource Subject:users --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id schema-registry --prefix
confluent iam rbac role-binding create --principal User:c3User --role ResourceOwner --resource Topic:pageviews --kafka-cluster-id $KAFKA_CLUSTER_ID --prefix
confluent iam rbac role-binding create --principal User:c3User --role ResourceOwner --resource Subject:pageviews --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id schema-registry --prefix

confluent iam rbac role-binding create --principal User:c3User --role ResourceOwner --resource Topic:_confluent-ksql-${KSQLDB_CLUSTER_ID}transient --prefix --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rbac role-binding create --principal User:c3User --role ResourceOwner --resource Subject:_confluent-ksql-${KSQLDB_CLUSTER_ID}transient --prefix --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id schema-registry
confluent iam rbac role-binding create --principal User:c3User --role ResourceOwner --resource Group:_confluent-ksql-${KSQLDB_CLUSTER_ID} --prefix --kafka-cluster-id $KAFKA_CLUSTER_ID
echo
echo 
echo "---Start Minio----"
docker-compose up -d --build --no-deps minio

echo ">>>Download mc for mac"
ARCH=`uname -m`
if [ $ARCH == "arm64" ]
  then
    ls mc || wget https://dl.minio.io/client/mc/release/darwin-arm64/mc && chmod +x ./mc
else
  ls mc || wget https://dl.minio.io/client/mc/release/darwin-amd64/mc && chmod +x ./mc
fi
echo
sleep 3
echo ">>>Create bucket"
./mc config host add myminio http://localhost:9000 minio minio123
./mc admin info myminio
./mc mb myminio/mys3bucket
./mc ls myminio/mys3bucket
echo
echo
echo
echo "* Create s3 sink connector to minio-----------done"
curl -i -X POST \
    --cacert ./secrets/ca.crt \
    -u connectUser:connectUser \
    -H "Accept:application/json" \
    -H  "Content-Type:application/json" \
   https://localhost:8083/connectors/ -d '
  {
      "name": "s3-sink",
      "config": {
           "connector.class": "io.confluent.connect.s3.S3SinkConnector",
           "name": "s3-sink",
           "topics": "snacks_avro",
           "key.converter": "org.apache.kafka.connect.storage.StringConverter",
           "value.converter": "io.confluent.connect.avro.AvroConverter",
           "value.converter.schema.registry.url": "https://schemaregistry:8081",
           "value.converter.schema.registry.ssl.truststore.location": "/etc/kafka/secrets/connect.truststore.jks",
           "value.converter.schema.registry.ssl.truststore.password": "confluent",
           "value.converter.basic.auth.credentials.source": "USER_INFO",
           "value.converter.basic.auth.user.info": "connectUser:connectUser",
           "tasks.max": "1",
           "store.url": "http://minio:9000",
           "s3.bucket.name":"mys3bucket",
           "s3.part.size": "5242880",
           "flush.size": "3",
           "storage.class": "io.confluent.connect.s3.storage.S3Storage",
           "format.class": "io.confluent.connect.s3.format.parquet.ParquetFormat",
           "schema.generator.class": "io.confluent.connect.storage.hive.schema.DefaultSchemaGenerator",
           "partitioner.class": "io.confluent.connect.storage.partitioner.DefaultPartitioner",
           "schema.compatibility": "NONE",
           "consumer.override.sasl.jaas.config": "org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username=\"connectUser\" password=\"connectUser\" metadataServerUrls=\"https://kafka1:1090\";"
       }
  }'

echo
sleep 3
curl --cacert ./secrets/ca.crt -u connectUser:connectUser https://localhost:8083/connectors/s3-sink/status
echo
sleep 5
echo ">> List messages in minio storage"
./mc ls myminio/mys3bucket/topics/snacks_avro/partition=0
