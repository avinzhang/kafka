#!/bin/bash


echo "Starting up Openldap, zookeeper and broker"
#docker-compose up -d --build --no-deps openldap zookeeper kafka1 &>/dev/null
docker-compose up -d --build --no-deps openldap zookeeper kafka1 kafka2

echo "Waiting for broker to start up"

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
    spawn confluent login --url http://localhost:18090
    expect "Username: "
    send "mds\r";
    expect "Password: "
    send "mds\r";
    expect "Logged in as "
    set result $expect_out(buffer)
END
)

echo "$OUTPUT"

  if [[ ! "$OUTPUT" =~ "Logged in as" ]]; then
    echo "Failed to log into MDS.  Please check all parameters and run again"
    exit 1
  fi

KAFKA_CLUSTER_ID=$(confluent cluster describe --url http://localhost:18090|grep Resource|awk '{print $4}')
echo "Kafka cluster id is $KAFKA_CLUSTER_ID"
echo "-------------------------------------------------------------------"
echo

echo "Adding role binding for user superUser"
confluent iam rolebinding create --principal User:superUser --role SystemAdmin --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rolebinding create --principal User:superUser --role SystemAdmin --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id schema-registry
confluent iam rolebinding create --principal User:superUser --role SystemAdmin --kafka-cluster-id $KAFKA_CLUSTER_ID --connect-cluster-id connect-cluster
confluent iam rolebinding create --principal User:superUser --role SystemAdmin --kafka-cluster-id $KAFKA_CLUSTER_ID --ksql-cluster-id ksql-cluster
echo "--------------------------------------------------------------------"
echo
echo "Adding role binding for user schemaregistryUser"
confluent iam rolebinding create \
    --principal User:schemaregistryUser \
    --role SecurityAdmin \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --schema-registry-cluster-id schema-registry
 
confluent iam rolebinding create \
    --principal User:schemaregistryUser \
    --role ClusterAdmin \
    --kafka-cluster-id $KAFKA_CLUSTER_ID 

confluent iam rolebinding create \
    --principal User:schemaregistryUser \
    --role DeveloperRead \
    --resource Topic:_confluent-license \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal User:schemaregistryUser \
    --role DeveloperWrite \
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

echo "For schema registry 6.0.0, _confluet-license topic needs to be pre created since we only have 2 brokers"
docker-compose exec kafka-1 kafka-topics --bootstrap-server kafka1:9092 --create --topic _confluent-license --replication-factor 1 --partitions 1
echo "Starting up schema registry"
#docker-compose up -d --build --no-deps schemaregistry &>/dev/null
docker-compose up -d --build --no-deps schemaregistry
echo "-------------------------------------------------------------------"
echo
echo
echo "Adding role binding for user connectAdmin for Kafka Connect"
confluent iam rolebinding create --principal User:connectAdmin --role SecurityAdmin --kafka-cluster-id $KAFKA_CLUSTER_ID --connect-cluster-id connect-cluster

# ResourceOwner for groups and topics on broker
declare -a ConnectResources=(
    "Topic:connect-configs"
    "Topic:connect-offsets"
    "Topic:connect-status"
    "Group:connect-cluster"
    "Topic:_confluent-monitoring"
    "Topic:_confluent-secrets"
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

echo "Add role binding for connectorUser for managing connectors"
confluent iam rolebinding create --principal User:connectorUser --role ResourceOwner --resource Connector:datagen-users --kafka-cluster-id $KAFKA_CLUSTER_ID --connect-cluster-id connect-cluster
confluent iam rolebinding create --principal User:connectorUser --role ResourceOwner --resource Connector:datagen-pageviews --kafka-cluster-id $KAFKA_CLUSTER_ID --connect-cluster-id connect-cluster

#for connector to access topic, subject
confluent iam rolebinding create --principal User:connectorUser --role ResourceOwner --resource Topic:users --kafka-cluster-id $KAFKA_CLUSTER_ID --prefix
confluent iam rolebinding create --principal User:connectorUser --role ResourceOwner --resource Topic:pageviews --kafka-cluster-id $KAFKA_CLUSTER_ID --prefix
confluent iam rolebinding create --principal User:connectorUser --role ResourceOwner --resource Subject:users --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id schema-registry
confluent iam rolebinding create --principal User:connectorUser --role ResourceOwner --resource Subject:pageviews --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id schema-registry


# User to check all connector status
confluent iam rolebinding create --principal User:connectorViewer --role ResourceOwner --resource 'Connector:*' --kafka-cluster-id $KAFKA_CLUSTER_ID --connect-cluster-id connect-cluster
confluent iam rolebinding create --principal User:connectorViewer --role ResourceOwner --resource 'Topic:*' --kafka-cluster-id $KAFKA_CLUSTER_ID --prefix
confluent iam rolebinding create --principal User:connectorViewer --role ResourceOwner --resource 'Subject:*' --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id schema-registry


echo "Starting up Kafka connect"
#docker-compose up -d --build --no-deps connect &>/dev/null
docker-compose up -d --build --no-deps connect
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

echo

echo "Add connector: datagen-users"
curl -i -X POST \
    --cacert ./scripts/security/snakeoil-ca-1.crt \
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
           "value.converter": "org.apache.kafka.connect.json.JsonConverter",
           "value.converter.schemas.enable": "false",
           "tasks.max": "1",
           "iterations": "1000000000",
           "producer.override.sasl.jaas.config": "org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username=\"connectorUser\" password=\"connectorUser\" metadataServerUrls=\"http://kafka1:18090,http://kafka2:28090\";"
       }
   }'

echo 
echo "Add connector: datagen-pageviews"
curl -i -X POST \
    --cacert ./scripts/security/snakeoil-ca-1.crt \
    -u connectorUser:connectorUser \
    -H "Accept:application/json" \
    -H  "Content-Type:application/json" \
   https://localhost:8083/connectors/ -d '
  {
    "name": "datagen-pageviews",
    "config": {
       "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
       "quickstart": "pageviews",
       "max.interval": "1000",
       "kafka.topic": "pageviews",
       "key.converter": "org.apache.kafka.connect.storage.StringConverter",
       "value.converter": "org.apache.kafka.connect.json.JsonConverter",
       "value.converter.schemas.enable": "false",
       "tasks.max": "1",
       "iterations": "1000000000",
       "producer.override.sasl.jaas.config": "org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username=\"connectorUser\" password=\"connectorUser\" metadataServerUrls=\"http://kafka1:18090,http://kafka2:28090\";"
    }
  }'

echo "-------------------------------------------------------------"
echo
echo
echo "Add role binding for ksqlAdmin user"
confluent iam rolebinding create --principal User:ksqlAdmin --role ResourceOwner --resource KsqlCluster:ksql-cluster --kafka-cluster-id $KAFKA_CLUSTER_ID --ksql-cluster-id ksql-cluster
confluent iam rolebinding create --principal User:ksqlAdmin --role DeveloperRead --resource Group:_confluent-ksql-ksql-cluster --prefix --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rolebinding create --principal User:ksqlAdmin --role ResourceOwner --resource Topic:_confluent-ksql-ksql-cluster --prefix --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rolebinding create --principal User:ksqlAdmin --role ResourceOwner --resource Subject:_confluent-ksql-ksql-cluster --prefix --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id schema-registry
confluent iam rolebinding create --principal User:ksqlAdmin --role ResourceOwner --resource Topic:_confluent-monitoring --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rolebinding create --principal User:ksqlAdmin --role ResourceOwner --resource Topic:ksql-clusterksql_processing_log --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rolebinding create --principal User:ksqlAdmin --role DeveloperRead --resource 'Topic:*' --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rolebinding create --principal User:ksqlAdmin --role DeveloperWrite --resource TransactionalId:ksql-cluster --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rolebinding create --principal User:ksqlAdmin --role ResourceOwner --resource 'Topic:*' --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rolebinding create --principal User:ksqlAdmin --role ResourceOwner --resource 'Subject:*' --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id schema-registry


#add rolebinding for ksqlUser user to create streams or tables"
confluent iam rolebinding create --principal User:ksqlUser --role DeveloperWrite --resource KsqlCluster:ksql-cluster --kafka-cluster-id $KAFKA_CLUSTER_ID --ksql-cluster-id ksql-cluster
confluent iam rolebinding create --principal User:ksqlUser --role ResourceOwner --resource 'Subject:*' --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id schema-registry
confluent iam rolebinding create --principal User:ksqlUser --role DeveloperRead --resource 'Topic:*' --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rolebinding create --principal User:ksqlUser --role ResourceOwner --resource 'Topic:*' --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rolebinding create --principal User:ksqlUser --role DeveloperRead --resource Topic:ksql-clusterksql_processing_log --prefix --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rolebinding create --principal User:ksqlUser --role DeveloperWrite --resource TransactionalId:ksql-cluster --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rolebinding create --principal User:ksqlUser --role ResourceOwner --resource Group:_confluent-ksql-ksql-cluster --prefix --kafka-cluster-id $KAFKA_CLUSTER_ID


echo "Starting up ksqldb server"
#docker-compose up -d --build --no-deps ksqldb-server &>/dev/null
docker-compose up -d --build --no-deps ksqldb-server 

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
echo "Start ksql streams and queries"
echo
docker-compose exec ksqldb-server bash -c "ksql --config-file /tmp/ksqlclient.properties -u ksqlUser -p ksqlUser https://localhost:8088 <<EOF
SET 'auto.offset.reset'='earliest';
CREATE STREAM pageviews (viewtime BIGINT, userid VARCHAR, pageid VARCHAR) WITH (KAFKA_TOPIC='pageviews', REPLICAS=1, VALUE_FORMAT='AVRO');
CREATE TABLE users (registertime BIGINT, gender VARCHAR, regionid VARCHAR, userid VARCHAR, interests array<VARCHAR>, contactinfo map<VARCHAR, VARCHAR>) WITH (KAFKA_TOPIC='users', VALUE_FORMAT='AVRO', KEY = 'userid');
CREATE STREAM pageviews_female AS SELECT users.userid AS userid, pageid, regionid, gender FROM pageviews LEFT JOIN users ON pageviews.userid = users.userid WHERE gender = 'FEMALE';
CREATE STREAM pageviews_female_like_89 WITH (kafka_topic='pageviews_enriched_r8_r9', value_format='AVRO') AS SELECT * FROM pageviews_female WHERE regionid LIKE '%_8' OR regionid LIKE '%_9';
CREATE TABLE pageviews_regions AS SELECT gender, regionid , COUNT(*) AS numusers FROM pageviews_female WINDOW TUMBLING (size 30 second) GROUP BY gender, regionid HAVING COUNT(*) > 1;
exit ;
EOF"


echo
echo "----------------------------------------------------------"
echo
echo
echo "Adding role binding for user c3Admin for Control Center"
confluent iam rolebinding create --principal User:c3Admin --role SystemAdmin --kafka-cluster-id $KAFKA_CLUSTER_ID
echo
echo
echo "Adding an additional test user for C3 GUI login"
confluent iam rolebinding create --principal User:c3User --role Operator --kafka-cluster-id $KAFKA_CLUSTER_ID

echo "Starting up Control Center"
#docker-compose up -d --build --no-deps controlcenter &>/dev/null
docker-compose up -d --build --no-deps controlcenter 
echo 
echo "Waiting for Control Center to start...."

C3_STARTED=false
while [ $C3_STARTED == false ]
do
    docker-compose logs controlcenter | grep "Started NetworkTrafficServerConnector" &> /dev/null
    if [ $? -eq 0 ]; then
      C3_STARTED=true
      echo "Control Center is started and ready"
    else
      echo "Waiting for Control Center to start..."
    fi
    sleep 5
done


echo "Use superUser to log into Control Center to see everything"
