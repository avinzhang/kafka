#!/bin/bash

TAG=6.0.1


echo "Download jdbc connector"
ls ./jar/splunk-kafka-connect-splunk/lib/splunk-kafka-connect-v2.0.jar || confluent-hub install  --component-dir ./jar splunk/kafka-connect-splunk:2.0 --no-prompt

echo "Done"


echo "----Start everything up--------------"
docker-compose up -d --build --no-deps zookeeper kafka connect schemaregistry &>/dev/null
echo

echo "----Start splunk-----------"
docker-compose up -d --build --no-deps splunk &>/dev/null
splunk_ready=false
while [ $splunk_ready == false ]
do
    docker-compose logs splunk|grep "begin streaming" &> /dev/null
    if [ $? -eq 0 ]; then
      splunk_ready=true
      echo "*** Splunk is ready ****"
    else
      echo ">>> Waiting for splunk to start"
    fi
    sleep 5
done
echo "Create splunk HEC index"
curl -k -s -u admin:password https://localhost:8089/servicesNS/nobody/search/data/inputs/http -d name=kafka
curl -k -s -u admin:password https://localhost:8089/servicesNS/nobody/search/data/inputs/http/kafka -d enableSSL=0
TOKEN=`curl -k -s -u admin:password https://localhost:8089/servicesNS/nobody/search/data/inputs/http |grep token|cut -d'>' -f2|cut -d'<' -f1`
echo "Token is $TOKEN"
echo "Done"


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

echo "Create splunk sink connector"
curl -i -X POST -H "Accept:application/json" \
    -H  "Content-Type:application/json" http://localhost:8083/connectors/ \
    -d '{
        "name": "splunk-connector",
        "config": {
            "connector.class": "com.splunk.kafka.connect.SplunkSinkConnector",
            "topics": "splunk",
            "tasks.max": 1,
            "splunk.indexes": "main",
            "splunk.hec.uri": "http://splunk:8889",
            "splunk.hec.token": "$TOKEN",
            "splunk.sourcetypes": "my_sourcetype",
            "confluent.topic.bootstrap.servers": "kafka:9093",
            "confluent.topic.replication.factor": 1,
            "value.converter": "org.apache.kafka.connect.storage.StringConverter"
      }
    }'

echo 
sleep 2
echo "Check splunk connector status"
curl http://localhost:8083/connectors/splunk-connector/status

echo "Produce messages to kafka topic"
seq 10|kafka-console-producer --broker-list localhost:9092 --topic splunk
