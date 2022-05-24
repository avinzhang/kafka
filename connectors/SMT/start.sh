#!/bin/bash

export TAG=7.1.1.arm64
datagen_version=latest

echo "----Download datagen connector-----------"
mkdir -p ./confluent-hub-components
ls ./confluent-hub-components/confluentinc-kafka-connect-datagen/lib/kafka-connect-datagen-*.jar || confluent-hub install  --component-dir ./confluent-hub-components confluentinc/kafka-connect-datagen:$datagen_version --no-prompt
echo "Done"
echo
echo
echo "----Start everything up with version $TAG------------"
docker compose up -d --build --no-deps zookeeper kafka connect schemaregistry ksqldb-server #&>/dev/null
echo
echo
connect_ready=false
while [ $connect_ready == false ]
do
    docker compose logs connect|grep "Herder started" &> /dev/null
    if [ $? -eq 0 ]; then
      connect_ready=true
      echo "*** Kafka Connect is ready ****"
    else
      echo ">>> Waiting for kafka connect to start"
    fi
    sleep 5
done
echo
echo
echo "* Create datagen-user connector"
curl -X POST -H "Content-Type: application/json" http://localhost:8083/connectors/ --data '{
  "name": "datagen-users", 
  "config": {
    "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector", 
    "quickstart": "users", 
    "name": "datagen-users", 
    "kafka.topic": "users", 
    "max.interval": "1000", 
    "key.converter": "org.apache.kafka.connect.storage.StringConverter", 
    "value.converter": "io.confluent.connect.avro.AvroConverter", 
    "tasks.max": "1", 
    "iterations": "1000000000",  
    "key.converter.schema.registry.url": "http://schemaregistry:8081", 
    "value.converter.schema.registry.url": "http://schemaregistry:8081", 
    "transforms": "regionidMask, genderMask",
    "transforms.regionidMask.type": "org.apache.kafka.connect.transforms.MaskField$Value",
    "transforms.regionidMask.fields": "regionid",
    "transforms.regionidMask.replacement": "Region_x",
    "transforms.genderMask.type": "org.apache.kafka.connect.transforms.MaskField$Value",
    "transforms.genderMask.fields": "gender",
    "transforms.genderMask.replacement": "SECRET"

    }
 }'

echo "* Create datagen-pageview connector"
curl -X POST -H "Content-Type: application/json" http://localhost:8083/connectors/ --data '{
  "name": "datagen-pageviews", 
  "config": {
    "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector", 
    "quickstart": "pageviews", 
    "name": "datagen-pageviews", 
    "kafka.topic": "pageviews", 
    "max.interval": "1000", 
    "key.converter": "org.apache.kafka.connect.storage.StringConverter", 
    "value.converter": "io.confluent.connect.avro.AvroConverter", 
    "tasks.max": "1", 
    "iterations": "1000000000",  
    "key.converter.schema.registry.url": "http://schemaregistry:8081", 
    "value.converter.schema.registry.url": "http://schemaregistry:8081",
    "transforms": "MaskField",
    "transforms.MaskField.type": "org.apache.kafka.connect.transforms.MaskField$Value",
    "transforms.MaskField.fields": "pageid"
    }
 }'

echo
sleep 3
echo "* Check connector status"
echo "  datagen-users:  `curl -s http://localhost:8083/connectors/datagen-users/status | jq .connector.state`"
echo "  datagen-pageviews:  `curl -s http://localhost:8083/connectors/datagen-pageviews/status | jq .connector.state`"

