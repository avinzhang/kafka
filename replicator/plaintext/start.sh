#!/bin/bash

export TAG=7.0.1
datagen_version=latest
replicator_version=7.0.1

echo "----Download datagen connector-----------"
mkdir -p ./jar/datagen
ls ./jar/datagen/confluentinc-kafka-connect-datagen/lib/kafka-connect-datagen-*.jar || confluent-hub install  --component-dir ./jar/datagen confluentinc/kafka-connect-datagen:$datagen_version --no-prompt
echo "Done"
echo "---Download replicator"
ls ./jar/confluentinc-kafka-connect-replicator/lib/connect-replicator-$replicator_version.jar || confluent-hub install  --component-dir ./jar confluentinc/kafka-connect-replicator:$replicator_version --no-prompt
echo
echo
echo "----Start everything up with version $TAG------------"
docker-compose up -d --build --no-deps zookeeper1 kafka1 connect1 schemaregistry zookeeper2 kafka2 connect2 zookeeper3 kafka3 controlcenter #&>/dev/null
echo
echo
connect_ready=false
while [ $connect_ready == false ]
do
    docker-compose logs connect1|grep "Herder started" &> /dev/null
    if [ $? -eq 0 ]; then
      connect_ready=true
      echo "*** Source Kafka Connect is ready ****"
    else
      echo ">>> Waiting for Source kafka connect to start"
    fi
    sleep 5
done
connect_ready=false
while [ $connect_ready == false ]
do
    docker-compose logs connect2|grep "Herder started" &> /dev/null
    if [ $? -eq 0 ]; then
      connect_ready=true
      echo "*** Dest Kafka Connect is ready ****"
    else
      echo ">>> Waiting for Dest kafka connect to start"
    fi
    sleep 5
done
echo
echo
echo "* Create datagen-user connector"
curl -X POST -H "Content-Type: application/json" http://localhost:8083/connectors/ --data '{"name": "datagen-users", "config": {"connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector", "quickstart": "users", "name": "datagen-users", "kafka.topic": "users", "max.interval": "1000", "key.converter": "org.apache.kafka.connect.storage.StringConverter", "value.converter": "io.confluent.connect.avro.AvroConverter", "tasks.max": "1", "iterations": "1000000000",  "key.converter.schema.registry.url": "http://schemaregistry:8081", "value.converter.schema.registry.url": "http://schemaregistry:8081" }}'

sleep 3
echo "* Check connector status"
echo "  datagen-users:  `curl -s http://localhost:8083/connectors/datagen-users/status | jq .connector.state`"

echo

echo ">>Create replicator connector on destination cluster"
docker-compose exec connect2 curl -i -X POST -H "Accept:application/json" \
    -H  "Content-Type:application/json" http://connect2:18083/connectors/ \
    -d '{
        "name": "replicator",
        "config": {
            "name": "replicator",
            "tasks.max": 1,
            "connector.class": "io.confluent.connect.replicator.ReplicatorSourceConnector",
            "key.converter":"io.confluent.connect.replicator.util.ByteArrayConverter",
            "value.converter":"io.confluent.connect.replicator.util.ByteArrayConverter",
            "src.kafka.bootstrap.servers":"kafka1:9093",
            "dest.kafka.bootstrap.servers":"kafka2:19093",
            "topic.config.sync": "false",
            "topic.whitelist":"users",
            "confluent.topic.replication.factor": "1"
        }
    }' &> /dev/null
sleep 3
echo
echo "* Check replicator status"
echo "  Replicator:  `curl -s http://localhost:18083/connectors/replicator/status | jq .connector.state`"




