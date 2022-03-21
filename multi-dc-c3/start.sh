#!/bin/bash

export TAG=7.0.1

echo "----------Start zookeeper and broker -------------"
docker-compose up -d --build --no-deps zookeeper1 zookeeper2 kafka1 kafka2 schemaregistry1 schemaregistry2
echo "Done"
echo
echo
MDS_STARTED=false
while [ $MDS_STARTED == false ]
do
    docker-compose logs kafka1 | grep "Started NetworkTrafficServerConnector" &> /dev/null
    if [ $? -eq 0 ]; then
      MDS_STARTED=true
      echo "kafka1 is started and ready"
    else
      echo "Waiting for MDS to start..."
    fi
    sleep 5
done

MDS_STARTED=false
while [ $MDS_STARTED == false ]
do
    docker-compose logs kafka2 | grep "Started NetworkTrafficServerConnector" &> /dev/null
    if [ $? -eq 0 ]; then
      MDS_STARTED=true
      echo "Kafka2 is started and ready"
    else
      echo "Waiting for MDS to start..."
    fi
    sleep 5
done
echo
echo "Create users topic on kafka1"
kafka-topics --bootstrap-server localhost:1092 --create --topic users --partitions 2 --replication-factor 1
echo
echo "Produce a record with schema to kafka1"
kafka-avro-console-producer --broker-list localhost:1092 --topic users --property key.serializer=org.apache.kafka.common.serialization.StringSerializer --property schema.registry.url=http://localhost:1081 --property value.schema='{"type":"record","name":"Users","fields":[{"name":"Name","type":"string"},{"name":"Age","type":"int"}]}' << EOF
{"Name": "john", "Age": 10}
EOF
echo
echo
echo "Create users topic on kafka2"
kafka-topics --bootstrap-server localhost:2092 --create --topic users --partitions 2 --replication-factor 1
echo
echo "Produce a record with schema to kafka2"
kafka-avro-console-producer --broker-list localhost:2092 --topic users --property key.serializer=org.apache.kafka.common.serialization.StringSerializer --property schema.registry.url=http://localhost:2081 --property value.schema='{"type":"record","name":"Users","fields":[{"name":"Name","type":"string"},{"name":"Age","type":"int"}]}' << EOF
{"Name": "ben", "Age": 20}
EOF
echo
echo
echo ">> start C3"
docker-compose up -d --build --no-deps controlcenter
echo


