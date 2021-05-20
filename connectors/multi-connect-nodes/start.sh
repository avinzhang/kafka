#!/bin/bash

echo "Start zookeeper, kafka, schema registry, 2 connect workers"
docker-compose up -d --build --no-deps zookeeper kafka connect connect1 schemaregistry


echo "----Download datagen connector-----------"
mkdir -p ./jar/datagen
ls ./jar/datagen/confluentinc-kafka-connect-datagen/lib/kafka-connect-datagen-*.jar || confluent-hub install  --component-dir ./jar/datagen confluentinc/kafka-connect-datagen:$datagen_version --no-prompt
echo "Done"
echo

echo
echo
connect_ready=false
while [ $connect_ready == false ]
do
    connect1_ready=false
    docker-compose logs connect|grep "Herder started" &> /dev/null
    if [ $? -eq 0 ]; then
      connect1_ready=true
      echo "*** Kafka Connect Node 1 is ready ****"
    fi
    connect2_ready=false
    docker-compose logs connect1|grep "Herder started" &> /dev/null
    if [ $? -eq 0 ]; then
      connect2_ready=true
      echo "*** Kafka Connect Node 2 is ready ****"
    fi
    if [ $connect1_ready == true ] && [ $connect2_ready == true ]; then
      echo "Both Kafka Connect workers are ready"
      connect_ready=true
    else
      echo ">>> Waiting for kafka connect to start"
    fi
    sleep 5
done
echo
echo

echo "* Create datagen-user connector"
curl -X POST -H "Content-Type: application/json" http://localhost:8083/connectors/ --data '{"name": "datagen-users", "config": {"connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector", "quickstart": "users", "name": "datagen-users", "kafka.topic": "users", "max.interval": "1000", "key.converter": "org.apache.kafka.connect.storage.StringConverter", "value.converter": "io.confluent.connect.avro.AvroConverter", "tasks.max": "1", "iterations": "1000000000",  "key.converter.schema.registry.url": "http://schemaregistry:8081", "value.converter.schema.registry.url": "http://schemaregistry:8081" }}'

echo "* Create datagen-pageviews connector"
curl -X POST -H "Content-Type: application/json" http://localhost:8083/connectors/ --data '{"name": "datagen-pageviews", "config": {"connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector", "quickstart": "pageviews", "name": "datagen-pageviews", "kafka.topic": "pageviews", "max.interval": "1000", "key.converter": "org.apache.kafka.connect.storage.StringConverter", "value.converter": "io.confluent.connect.avro.AvroConverter", "tasks.max": "1", "iterations": "1000000000",  "key.converter.schema.registry.url": "http://schemaregistry:8081", "value.converter.schema.registry.url": "http://schemaregistry:8081" }}'
echo
echo
sleep 3
echo 
echo ">> Check connector status"
echo "Datagen-users: `curl -s http://localhost:8083/connectors/datagen-users/status`"
echo
echo 
echo ">> Check connector status"
echo "Datagen-pageviews: `curl -s http://localhost:8083/connectors/datagen-pageviews/status`"
echo
