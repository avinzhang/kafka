#!/bin/bash

export TAG=7.1.2

echo "----------Start zookeeper and broker -------------"
docker compose up -d --build --no-deps zookeeper1 zookeeper2 zookeeper3 
echo "Done"
echo
docker compose up -d --build --no-deps kafka1 kafka2 kafka3 schemaregistry
echo
MDS_STARTED=false
while [ $MDS_STARTED == false ]
do
    docker compose logs kafka1 | grep "Started NetworkTrafficServerConnector" &> /dev/null
    if [ $? -eq 0 ]; then
      MDS_STARTED=true
      echo "MDS is started and ready"
    else
      echo "Waiting for MDS to start..."
    fi
    sleep 5
done
echo
echo ">> Download datagen connector"
mkdir -p confluent-hub-components
ls ./confluent-hub-components/confluentinc-kafka-connect-datagen/lib/kafka-connect-datagen-*.jar || confluent-hub install  --component-dir ./confluent-hub-components confluentinc/kafka-connect-datagen:latest --no-prompt
echo "Done"
echo
echo ">> Starting up Kafka connect"
docker compose up -d --build --no-deps connect1 connect2 connect3
echo
echo
CONNECT_STARTED=false
while [ $CONNECT_STARTED == false ]
do
    docker compose logs connect1 | grep "Herder started" &> /dev/null
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
   http://localhost:1083/connectors/ -d '
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
           "tasks.max": "2",
           "iterations": "1000000000"
       }
   }'
echo
sleep 5
echo ">> Check connector status"
echo "Datagen-users: `curl -s http://localhost:1083/connectors/datagen-users/status`"
echo
echo
echo ">> Add connector: datagen-pageviews"
curl -i -X POST \
    -H "Accept:application/json" \
    -H  "Content-Type:application/json" \
   http://localhost:1083/connectors/ -d '
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
           "tasks.max": "2",
           "iterations": "1000000000"
       }
   }'

echo
sleep 5
echo ">> Check connector status"
echo "Datagen-pageviews: `curl -s http://localhost:1083/connectors/datagen-pageviews/status`"
echo
echo
echo ">> start C3"
docker compose up -d --build --no-deps controlcenter
echo
