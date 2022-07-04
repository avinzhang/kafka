#!/bin/bash

export TAG=7.1.2.arm64
echo
echo "----Start everything up with version $TAG------------"
docker-compose up -d --build --no-deps zookeeper1 zookeeper2 zookeeper3 kafka1 kafka2 kafka3 &>/dev/null
echo
echo
echo
echo ">> Check if brokers are ready"
MDS_STARTED=false
while [ $MDS_STARTED == false ]
do
    docker-compose logs kafka1 | grep "Started NetworkTrafficServerConnector"  &> /dev/null && docker-compose logs kafka2 | grep "Started NetworkTrafficServerConnector"  &> /dev/null && docker-compose logs kafka3 | grep "Started NetworkTrafficServerConnector" &> /dev/null
    if [ $? -eq 0 ]; then
      MDS_STARTED=true
      echo "MDS is started and ready"
    else
      echo "Waiting for MDS to start..."
    fi
    sleep 5
done



java -jar cmdline-jmxclient-0.10.3.jar admin:admin localhost:1991 kafka.network:name=RequestQueueTimeMs,request=ReplicaStatus,type=RequestMetrics

# Using JmxTool
kafka-run-class kafka.tools.JmxTool --object-name kafka.network:name=RequestQueueTimeMs,request=ReplicaStatus,type=RequestMetrics --jmx-url service:jmx:rmi://localhost/jndi/rmi://localhost:1991/jmxrmi --jmx-auth-prop admin=admin --one-time true

# Using JmxTool display individual attribute only
kafka-run-class kafka.tools.JmxTool --object-name kafka.network:name=RequestQueueTimeMs,request=ReplicaStatus,type=RequestMetrics --attributes "99thPercentile" --jmx-url service:jmx:rmi://localhost/jndi/rmi://localhost:1991/jmxrmi --jmx-auth-prop admin=admin --one-time true

