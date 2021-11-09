#!/bin/bash

docker-compose up -d --build --no-deps zookeeper3 zookeeper1 zookeeper2 kafka3 kafka1 kafka2

for broker_node in kafka1 kafka2 kafka3 
  do
    MDS_STARTED=false
    while [ $MDS_STARTED == false ]
    do
        docker-compose logs $broker_node | grep "Started NetworkTrafficServerConnector" &> /dev/null
        if [ $? -eq 0 ]; then
          MDS_STARTED=true
          echo "$broker_node is started and ready"
        else
          echo "Waiting for $broker_node to start..."
          sleep 3
        fi
    done
done

docker-compose up -d --build --no-deps kafka-producer 
sleep 10

# Use below to start a producer
docker-compose exec kafka-producer bash -c "export KAFKA_OPTS="-javaagent:./jolokia-jvm-1.7.0.jar=port=8779,host=0.0.0.0"; node generate-users.js|kafka-console-producer --broker-list kafka1:1093 --topic users" &


docker-compose up -d --build --no-deps elasticsearch kibana metricbeat


#metricbeat dubug logs should show it's capturing the metrics from jolokia
#
echo "Get producer batch-size-avg from jolokia"
echo "console-producer batch-size-avg: `curl -s http://localhost:8779/jolokia/read/kafka.producer:client-id=console-producer,type=producer-metrics/batch-size-avg | jq .value`"

