#!/bin/bash

export TAG=6.1.1
echo
echo "----Start everything up with version $TAG------------"
docker-compose up -d --build --no-deps zookeeper kafka &>/dev/null
echo
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




java -jar cmdline-jmxclient-0.10.3.jar admin:admin localhost:9991 kafka.network:name=RequestQueueTimeMs,request=ReplicaStatus,type=RequestMetrics