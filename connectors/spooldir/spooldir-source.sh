#!/bin/bash

TAG=5.5.2

CONNECTOR_VERSION=2.0.60

echo "Download spool dir connector if it's not present"
ls ./jar/jcustenborder-kafka-connect-spooldir/lib/kafka-connect-spooldir-$CONNECTOR_VERSION.jar || confluent-hub install  --component-dir ./jar jcustenborder/kafka-connect-spooldir:$CONNECTOR_VERSION --no-prompt
echo "Done"


echo "----Start everything up--------------"
docker-compose up -d --build --no-deps zookeeper kafka schemaregistry &>/dev/null
echo
echo
echo "----Download a csv file-----"
mkdir -p ./connectors/spooldir/data ./connectors/spooldir/error ./connectors/spooldir/finished 
rm ./connectors/spooldir/error/* 
rm ./connectors/spooldir/finished/*
curl "https://api.mockaroo.com/api/58605010?count=1000&key=25fd9c80" > "./connectors/spooldir/data/csv-spooldir-source.csv"
echo
echo  "---Start connect with spooldir volume---"
docker-compose -f docker-compose.yml -f ./connectors/spooldir/docker-compose-spooldir.yml up -d --build --no-deps connect 
echo
connect_ready=false
while [ $connect_ready == false ]
do
    docker-compose logs connect|grep "Herder started" &> /dev/null
    if [ $? -eq 0 ]; then
      connect_ready=true
      echo "*** Kafka Connect is ready ****"
    else
      echo ">>> Waiting for kafka connect to start"
    fi
    sleep 5
done


echo "Create spooldir source connector"
curl -i -X POST -H "Accept:application/json" \
    -H  "Content-Type:application/json" http://localhost:8083/connectors/ \
    -d '{
        "name": "spooldir-source",
        "config": {
            "name": "spooldir-source",
            "tasks.max": 1,
            "connector.class": "com.github.jcustenborder.kafka.connect.spooldir.SpoolDirCsvSourceConnector",
            "input.path": "/spooldir/data",
            "input.file.pattern": "csv-spooldir-source.csv",
            "error.path": "/spooldir/error",
            "finished.path": "/spooldir/finished",
            "halt.on.error": "false",
            "schema.generation.enabled": "true",
            "topic": "spooldir-csv-topic",
            "csv.first.row.as.header": "true",
            "key.converter": "org.apache.kafka.connect.storage.StringConverter",
            "value.converter": "io.confluent.connect.avro.AvroConverter",
            "value.converter.schema.registry.url": "http://schemaregistry:8081"
        }
    }'

echo 
sleep 2
echo "Check spooldir source connector status"
curl http://localhost:8083/connectors/spooldir-source/status
echo
echo
