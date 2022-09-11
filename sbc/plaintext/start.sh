#!/bin/bash

export TAG=7.2.1.arm64

echo "----------Start zookeeper and broker -------------"
docker-compose up -d --build --no-deps zookeeper1 zookeeper2 zookeeper3 
echo "Done"
echo
docker-compose up -d --build --no-deps kafka1 kafka2 kafka3 
echo
MDS_STARTED=false
while [ $MDS_STARTED == false ]
do
    NUM=`docker-compose logs kafka1 kafka2 kafka3 | grep "Started NetworkTrafficServerConnector" | wc -l`
    if [ $NUM -eq 3 ]; then
      MDS_STARTED=true
      echo "All brokers are started and ready"
    else
      echo "Waiting for brokers to start..."
    fi
    sleep 5
done
echo
echo
#echo ">> start C3"
#docker-compose up -d --build --no-deps controlcenter
#echo
#STARTED=false
#while [ $STARTED == false ]
#do
#    docker-compose logs controlcenter | grep "Started NetworkTrafficServerConnector" &> /dev/null
#    if [ $? -eq 0 ]; then
#      STARTED=true
#      echo "Control Center is started and ready"
#    else
#      echo "Waiting for Control Center to start..."
#    fi
#    sleep 5
#done
echo
echo
echo ">>Create a topic with replica assignments that force data distribution with no replicas on broker 2"
kafka-topics --create --topic sbc --bootstrap-server localhost:1092 --replica-assignment 2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1,2:1
echo
echo ">> Producing messages to topic"
kafka-producer-perf-test \
--producer-props bootstrap.servers=localhost:1092 \
--topic sbc \
--record-size 1000 \
--throughput 1000 \
--num-records 3600000

##watch the topic describe, it takes a while(more than 20 mins) for the rebalance to occur
#watch kafka-topics --bootstrap-server localhost:1092 --describe --topic sbc
