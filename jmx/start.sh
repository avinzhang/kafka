#!/bin/bash

TAG=5.5.2

echo "----Start everything up--------------"
docker-compose -f docker-compose.yml -f ./jmx/docker-compose-jmx.yml up -d --build --no-deps zookeeper kafka &>/dev/null
echo

echo
echo ">> Check if broker is ready"
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
echo


echo "Get NetworkProcessorAvgIdlePercent metrics"
 kafka-run-class kafka.tools.JmxTool --object-name 'kafka.network:type=SocketServer,name=NetworkProcessorAvgIdlePercent' --jmx-url service:jmx:rmi:///jndi/rmi://localhost:9991/jmxrmi --reporting-interval 1000
