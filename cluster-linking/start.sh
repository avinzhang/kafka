#!/bin/bash

export TAG=7.0.0

echo "----Start two clusters----"
echo "Cluster1: zookeeper1 and kafka1"
echo "Cluster2: zookeeper2 and kafka2"
echo
docker-compose up -d --build --no-deps zookeeper2 zookeeper1 kafka2 kafka1

echo
echo ">>Checking if kafka1 is started"
MDS_STARTED=false
while [ $MDS_STARTED == false ]
do
    docker-compose logs kafka1 | grep "Started NetworkTrafficServerConnector" &> /dev/null
    if [ $? -eq 0 ]; then
      MDS_STARTED=true
      echo "kafka1 is started and ready"
    else
      echo "Waiting for kafka1 to start..."
    fi
    sleep 5
done

echo
echo ">>Checking if kafka2 is started"
MDS_STARTED=false
while [ $MDS_STARTED == false ]
do
    docker-compose logs kafka2 | grep "Started NetworkTrafficServerConnector" &> /dev/null
    if [ $? -eq 0 ]; then
      MDS_STARTED=true
      echo "kafka2 is started and ready"
    else
      echo "Waiting for kafka2 to start..."
    fi
    sleep 5
done

echo -e "\n>> Create test Topic in kafka1"
docker-compose exec kafka1 kafka-topics  --create --bootstrap-server kafka1:1093 --topic test --partitions 1 --replication-factor 1
sleep 2
echo ">> Show topics from kafka1"
docker-compose exec kafka1 kafka-topics --list --bootstrap-server kafka1:1093
echo
echo
echo -e "\n>> Create kafka-cluster-link from kafka1 -> kafka2"
docker-compose exec kafka2 bash -c 'echo "{\"groupFilters\": [{\"name\": \"*\",\"patternType\": \"LITERAL\",\"filterType\": \"INCLUDE\"}]}" > groupFilters.json'
docker-compose exec kafka2 kafka-cluster-links \
	--bootstrap-server kafka2:2093 \
	--create \
	--link kafka-cluster-link \
	--config bootstrap.servers=kafka1:1093,consumer.offset.sync.enable=true,consumer.offset.sync.ms=10000 \
	--consumer-group-filters-json-file groupFilters.json

sleep 2
echo ">> List cluster links"
docker-compose exec kafka2 kafka-cluster-links --list --bootstrap-server kafka2:2093 
echo
echo
echo -e "\n>> Create an mirror of test topic on kafka2"
docker-compose exec kafka2 kafka-mirrors --create \
	--bootstrap-server kafka2:2093 \
	--mirror-topic test \
	--link kafka-cluster-link \
	--replication-factor 1

echo ">>done"

echo 
echo ">> List mirrored topics from kafka2"
docker-compose exec kafka2 kafka-cluster-links --list --bootstrap-server kafka2:2093 --include-topics

echo
echo "----Produce messages to test topic in kafka1 of Cluster1-----"
docker-compose exec kafka1 bash -c "seq 10 | kafka-console-producer --request-required-acks 1 --broker-list kafka1:1093 --topic test && echo 'Produced 10 messages.'"
echo
echo "---Consume messages from test topic in kafka2 from Cluster2----"
docker-compose exec kafka2 bash -c "kafka-console-consumer --bootstrap-server kafka2:2093 --topic test --from-beginning --timeout-ms 5000"
echo
echo
echo ">> Check replica status on the destination"
docker-compose exec kafka2 kafka-replica-status --topics test --include-linked --bootstrap-server localhost:2093
echo
echo ">> Verify if destination is read-only"
docker-compose exec kafka2 bash -c "seq 2 | kafka-console-producer --request-required-acks 1 --broker-list kafka2:2093 --topic test"

echo
echo 
echo ">> Cut over the mirrored topic to make it writable"
docker-compose exec kafka2 kafka-mirrors --promote --topics test --bootstrap-server kafka2:2093
echo
echo ">> Check if mirrored topic has stopped mirroring"
docker-compose exec kafka2 kafka-mirrors --describe --topics test --pending-stopped-only --bootstrap-server kafka2:2093
echo 
echo
echo ">> the test topic on kafka2 should be writable"
docker-compose exec kafka2 bash -c "seq 2 | kafka-console-producer --request-required-acks 1 --broker-list kafka2:2093 --topic test"
