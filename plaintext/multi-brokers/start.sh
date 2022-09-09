#!/bin/bash

export TAG=7.2.1.arm64

echo "----------Start zookeeper and broker -------------"
docker-compose up -d --build --no-deps zookeeper1 zookeeper2 zookeeper3 
echo "Done"
echo
docker-compose up -d --build --no-deps kafka1 kafka2 kafka3 schemaregistry
echo
MDS_STARTED=false
while [ $MDS_STARTED == false ]
do
    NUM=`docker-compose logs kafka1 kafka2 kafka3 | grep "Started NetworkTrafficServerConnector" | wc -l`
    if [ $NUM -eq 3 ]; then
      MDS_STARTED=true
      echo "All brokers are started and ready"
    else
      echo "Waiting for brokers to start..."
    fi
    sleep 5
done
echo
echo ">> Download datagen connector"
mkdir -p ./confluent-hub-components
ls ./confluent-hub-components/confluentinc-kafka-connect-datagen/lib/kafka-connect-datagen-*.jar || confluent-hub install  --component-dir ./confluent-hub-components confluentinc/kafka-connect-datagen:latest --no-prompt
echo "Done"
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

echo ">> Add connector: datagen-users"
curl -i -X POST \
    -H "Accept:application/json" \
    -H  "Content-Type:application/json" \
   http://localhost:8083/connectors/ -d '
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
           "value.converter.schema.registry.url": "http://schemaregistry:8081",
           "tasks.max": "1",
           "iterations": "1000000000"
       }
   }'
echo
sleep 3
echo ">> Check connector status"
echo "Datagen-users: `curl -s http://localhost:8083/connectors/datagen-users/status`"
echo
echo
echo ">> Add connector: datagen-pageviews"
curl -i -X POST \
    -H "Accept:application/json" \
    -H  "Content-Type:application/json" \
   http://localhost:8083/connectors/ -d '
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
           "value.converter.schema.registry.url": "http://schemaregistry:8081",
           "tasks.max": "1",
           "iterations": "1000000000"
       }
   }'

echo
sleep 3
echo ">> Check connector status"
echo "Datagen-pageviews: `curl -s http://localhost:8083/connectors/datagen-pageviews/status`"
echo
echo
echo
echo "-----Setup ksqldb-----------"
echo
echo
echo ">> Start ksqldb server"
docker-compose up -d --build --no-deps ksqldb-server
echo

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
echo "Start ksql streams and queries"
docker-compose exec ksqldb-server bash -c "ksql http://localhost:8088 <<EOF
SET 'auto.offset.reset'='earliest';
CREATE STREAM pageviews (viewtime BIGINT, userid VARCHAR, pageid VARCHAR) WITH (KAFKA_TOPIC='pageviews', VALUE_FORMAT='AVRO');
CREATE TABLE users (userid VARCHAR PRIMARY KEY, registertime BIGINT, gender VARCHAR, regionid VARCHAR) WITH (KAFKA_TOPIC='users', VALUE_FORMAT='AVRO');
CREATE STREAM pageviews_female with (KAFKA_TOPIC='pageviews_female') AS SELECT users.userid AS userid, pageid, regionid, gender FROM pageviews LEFT JOIN users ON pageviews.userid = users.userid WHERE gender = 'FEMALE';
CREATE STREAM pageviews_female_like_89 WITH (kafka_topic='pageviews_enriched_r8_r9', value_format='AVRO') AS SELECT * FROM pageviews_female WHERE regionid LIKE '%_8' OR regionid LIKE '%_9';
CREATE TABLE pageviews_regions WITH (kafka_topic='pageviews_regions', value_format='AVRO', KEY_FORMAT='avro') AS SELECT gender, regionid , COUNT(*) AS numusers FROM pageviews_female WINDOW TUMBLING (size 30 second) GROUP BY gender, regionid HAVING COUNT(*) > 1;
exit ;
EOF"


echo
echo ">> start C3"
docker-compose up -d --build --no-deps controlcenter
echo
STARTED=false
while [ $STARTED == false ]
do
    docker-compose logs controlcenter | grep "Started NetworkTrafficServerConnector" &> /dev/null
    if [ $? -eq 0 ]; then
      STARTED=true
      echo "Control Center is started and ready"
    else
      echo "Waiting for Control Center to start..."
    fi
    sleep 5
done
echo

