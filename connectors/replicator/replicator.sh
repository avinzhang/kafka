#!/bin/bash

TAG=6.1.1

CONNECTOR_VERSION=6.1.1

echo "Download replicator if it's not present"
ls ./jar/confluentinc-kafka-connect-replicator/lib/connect-replicator-$CONNECTOR_VERSION.jar || confluent-hub install  --component-dir ./jar confluentinc/kafka-connect-replicator:$CONNECTOR_VERSION --no-prompt
echo "Done"


echo "----Start source cluster --------------"
docker-compose up -d --build --no-deps zookeeper kafka 
echo
echo
echo  "---Start destination cluster---"
docker-compose -f docker-compose.yml -f ./connectors/replicator/docker-compose-replicator.yml up -d --build --no-deps zookeeper1 kafka1 connect
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

echo 
echo " >>> Create topic test on source cluster"
kafka-topics --bootstrap-server localhost:9092 --create --topic test --replication-factor 1 --partitions 2
echo
echo ">>> Produce 10 messages to the test topic on source cluster"
seq 10 | kafka-console-producer --broker-list localhost:9092 --topic test && echo 'Produced 10 messages.'
echo
echo ">>> Consume messages on source cluster to make sure messages are produced correctly"
kafka-console-consumer --bootstrap-server localhost:9092 --topic test --from-beginning --timeout-ms 5000 2> /dev/null
echo 
echo ">>Create replicator connector on destination cluster"
docker-compose exec connect curl -i -X POST -H "Accept:application/json" \
    -H  "Content-Type:application/json" http://connect:8083/connectors/ \
    -d '{
        "name": "replicator",
        "config": {
            "name": "replicator",
            "tasks.max": 1,
            "connector.class": "io.confluent.connect.replicator.ReplicatorSourceConnector",
            "key.converter":"io.confluent.connect.replicator.util.ByteArrayConverter",
            "value.converter":"io.confluent.connect.replicator.util.ByteArrayConverter",
            "src.kafka.bootstrap.servers":"kafka:9093",
            "dest.kafka.bootstrap.servers":"kafka1:19093",
            "topic.config.sync": "false",
            "topic.whitelist":"test",
            "confluent.topic.replication.factor": "1"
        }
    }' &> /dev/null

echo 
sleep 2
echo ">>Check replicator source connector status"
curl http://localhost:8083/connectors/replicator/status
echo
echo
echo "Consume messages from destination cluster"
kafka-console-consumer --bootstrap-server localhost:19092 --topic test --from-beginning --timeout-ms 5000 2> /dev/null

