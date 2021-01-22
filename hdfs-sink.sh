#!/bin/bash

TAG=6.0.1


echo "Download hdfs connector"
mkdir -p jar
ls ./jar/confluentinc-kafka-connect-hdfs/lib/hadoop-hdfs*.jar || confluent-hub install  --component-dir ./jar confluentinc/kafka-connect-hdfs:10.0.0 --no-prompt
echo "Done"


echo "----Start everything up--------------"
docker-compose up -d --build --no-deps zookeeper kafka connect schemaregistry &>/dev/null
echo

echo "----Start hadoop-----------"
docker-compose up -d --build --no-deps hadoop-namenode hadoop-datanode &>/dev/null


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

#The connector JSON is not parsing single quotes “ ‘ “ when path.format is configured. You need to escape that character and replace it with \u0027 instead of single quote (')
#For example, if you configure like : "path.format": "'year'=YYYY/'month'=MM/'day'=dd/'hour'=HH"
#It should be configured as:
#"path.format": "\u0027year\u0027=YYYY/\u0027month\u0027=MM/\u0027day\u0027=dd/\u0027hour\u0027=HH"
echo
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
sleep 2
echo ">> Check hdfs connector status"
curl http://localhost:8083/connectors/hdfs-sink/status
echo
echo
echo ">> Producer messages to hdfs topic"
kafka-avro-console-producer --broker-list localhost:9092 --topic hdfs --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}' << EOF
{"f1": "value1"}
{"f1": "value2"}
{"f1": "value3"}
EOF
sleep 2
echo
echo
echo ">> Check data on hdfs"
docker-compose exec hadoop-namenode hadoop fs -ls /topics
