#!/bin/bash

TAG=6.0.1

echo "----Start two clusters----"
echo "Cluster1: zookeeper and kafka"
echo "Cluster2: zookeeper1 and kafka1"
echo 
docker-compose -f docker-compose.yml -f ./cluster-linking/docker-compose-cluster-linking.yml up -d --build --no-deps zookeeper zookeeper1 kafka kafka1

echo 
echo "Checking kafka is started"
MDS_STARTED=false
while [ $MDS_STARTED == false ]
do
    docker-compose logs kafka | grep "Started NetworkTrafficServerConnector" &> /dev/null
    if [ $? -eq 0 ]; then
      MDS_STARTED=true
      echo "MDS is started and ready"
    else
      echo "Waiting for MDS to start..."
    fi
    sleep 5
done

echo -e "\n>> Create test Topic in kafka"
docker-compose exec kafka kafka-topics  --create --bootstrap-server kafka:9093 --topic test --partitions 1 --config min.insync.replicas=1

echo
echo
sleep 2
echo
echo
echo "Checking kafka1 is started"
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

echo -e "\n>> Create kafka-cluster-link from kafka -> kafka1"
docker-compose exec kafka1 bash -c 'echo "{\"groupFilters\": [{\"name\": \"*\",\"patternType\": \"LITERAL\",\"filterType\": \"INCLUDE\"}]}" > groupFilters.json'
docker-compose exec kafka1 kafka-cluster-links \
	--bootstrap-server kafka1:19093 \
	--create \
	--link-name kafka-cluster-link \
	--config bootstrap.servers=kafka:9093,consumer.offset.sync.enable=true,consumer.offset.sync.ms=10000 \
	--consumer-group-filters-json-file groupFilters.json

sleep 2
echo
echo -e "\n>> Create an mirror of test topic"

docker-compose exec kafka1 kafka-topics --create \
	--bootstrap-server kafka1:19093 \
	--topic test \
	--mirror-topic test \
	--link-name kafka-cluster-link \
	--replication-factor 1

echo "done"
echo
echo
echo "----Produce messages to test topic in kafka in Cluster1-----"
docker-compose exec kafka bash -c "seq 10 | kafka-console-producer --request-required-acks 1 --broker-list localhost:9092 --topic test && echo 'Produced 10 messages.'" 
echo
echo "---Consume messages from test topic in kafka1 from Cluster2----"
docker-compose exec kafka1 bash -c "kafka-console-consumer --bootstrap-server kafka1:19092 --topic test --from-beginning"
echo 
