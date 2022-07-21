#!/bin/bash

export TAG=7.2.0.arm64
datagen_version=latest

echo
echo "----Start everything up with version $TAG------------"
docker compose up -d --build --no-deps zookeeper1 zookeeper2 zookeeper3 kafka1 kafka2 kafka3 #&>/dev/null
echo
echo
ready=false
while [ $ready == false ]
do
    docker-compose logs kafka1 | grep "Started NetworkTrafficServerConnector"  &> /dev/null && docker-compose logs kafka2 | grep "Started NetworkTrafficServerConnector"  &> /dev/null && docker-compose logs kafka3 | grep "Started NetworkTrafficServerConnector" &> /dev/null
    if [ $? -eq 0 ]; then
      ready=true
      echo "*** Kafka broker is ready ****"
    else
      echo ">>> Waiting for kafka broker to start"
    fi
    sleep 5
done
echo
echo
echo ">>Create a topic - mytopic"
kafka-topics --bootstrap-server localhost:1092,localhost:2092,localhost:3092 --topic mytopic --create --replication-factor 3 --partitions 2
echo
echo ">>>>Describe the topic"
kafka-topics --bootstrap-server localhost:1092 --topic mytopic --describe
echo
echo
cat << EOF > /tmp/messages 
a:1
b:2
c:3
d:4
e:5
f:6
g:7
h:8
EOF
echo ">>Produce the following messages with idempotence"
cat /tmp/messages
kafka-console-producer --broker-list localhost:1092,localhost:2092,localhost:3092 --property client.id=myApp --producer-property enable.idempotence=true --request-required-acks all  --property max.in.flight.requests.per.connection=5 --property retries=2147483647 --property "parse.key=true" --property "key.separator=:" --topic mytopic < /tmp/messages
echo
echo
sleep 2
echo ">>Consume all messages, messages should not be in order"
kafka-console-consumer --bootstrap-server localhost:1092,localhost:2092,localhost:3092 --topic mytopic --from-beginning --property print.key=true --property key.separator=":" --timeout-ms 5000
#message order is not maintained across topic partitions, it is only maintained per partition
echo 
echo ">>Consume messages from partition 0"
kafka-console-consumer --bootstrap-server localhost:1092,localhost:2092,localhost:3092 --topic mytopic --from-beginning --property print.key=true --property key.separator=":" --partition 0 --timeout-ms 2000
echo
echo ">>Dump log partition 0 file"
docker-compose exec kafka1 kafka-dump-log --print-data-log --files '/var/lib/kafka/data/mytopic-0/00000000000000000000.log' --deep-iteration
echo
echo ">>Dump log partition 1 file"
docker-compose exec kafka1 kafka-dump-log --print-data-log --files '/var/lib/kafka/data/mytopic-1/00000000000000000000.log' --deep-iteration
#Note the familiar producerId: 0, which corresponds to the earlier log output from the producer application run. (If the producer were not configured to be idempotent, this would show producerId: -1.)
#Also observe that each message has a unique sequence number, starting with sequence: 0, that are not duplicated and are all in order. The broker checks the sequence number to ensure idempotency per partition, such that if a producer experiences a retriable exception and resends a message, sequence numbers will not be duplicated or out of order in the committed log. (If the producer were not configured to be idempotent, the messages would show sequence: -1.)
