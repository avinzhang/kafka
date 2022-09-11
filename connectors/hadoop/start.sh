#!/bin/bash

export TAG=7.2.1.arm64

mkdir -p ./confluent-hub-components
ls ./confluent-hub-components/confluentinc-kafka-connect-hdfs/lib/hadoop-hdfs*.jar || confluent-hub install  --component-dir ./confluent-hub-components confluentinc/kafka-connect-hdfs:latest --no-prompt
echo
echo "----------Start zookeeper and broker -------------"
docker-compose up -d --build --no-deps zookeeper1 zookeeper2 zookeeper3 
echo "Done"
echo
docker-compose up -d --build --no-deps kafka1 kafka2 kafka3 schemaregistry connect hadoop-namenode hadoop-datanode
echo
echo
ready=false
while [ $ready == false ]
do
    docker-compose logs connect|grep "Herder started" &> /dev/null
    if [ $? -eq 0 ]; then
      ready=true
      echo "*** Kafka Connect is ready ****"
    else
      echo ">>> Waiting for kafka connect to start"
    fi
    sleep 5
done
echo
echo "----Create hdfs sink connector----"
curl -i -X POST -H "Accept:application/json" \
    -H  "Content-Type:application/json" http://localhost:8083/connectors/ \
    -d '{
        "name": "hdfs-sink",
        "config": {
            "connector.class": "io.confluent.connect.hdfs.HdfsSinkConnector",
            "partitioner.class": "io.confluent.connect.storage.partitioner.TimeBasedPartitioner",
            "partition.duration.ms": "1000",
            "path.format": "\u0027year\u0027=YYYY/\u0027month\u0027=MM/\u0027day\u0027=dd/\u0027hour\u0027=HH",
            "locale": "en_AU",
            "timezone": "Australia/Brisbane",
            "tasks.max": "1",
            "topics": "hdfs",
            "hdfs.url": "hdfs://hadoop-namenode:8020",
            "flush.size": "3",
            "name": "hdfs-sink",
            "key.converter": "org.apache.kafka.connect.storage.StringConverter",
            "value.converter": "io.confluent.connect.avro.AvroConverter",
            "value.converter.schema.registry.url": "http://schemaregistry:8081"
        }
    }'

echo
sleep 3
echo ">> Check hdfs connector status"
curl http://localhost:8083/connectors/hdfs-sink/status
echo
echo ">> Produce messages to hdfs topic"
kafka-avro-console-producer --broker-list localhost:1092 --topic hdfs --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}' << EOF
{"f1": "value1"}
{"f1": "value2"}
{"f1": "value3"}
EOF
echo
echo ">> Check data on hdfs"
docker-compose exec hadoop-namenode hadoop fs -ls /topics
