#!/bin/bash

TAG=6.0.1

echo "Starting up zookeeper and kafka"
docker-compose -f docker-compose.yml -f ./security/restproxy-principal-propagation/docker-compose-basic-sasl.yml up -d --build --no-deps zookeeper kafka

MDS_STARTED=false
while [ $MDS_STARTED == false ]
do
    docker-compose logs kafka | grep "Started NetworkTrafficServerConnector" &> /dev/null
    if [ $? -eq 0 ]; then
      MDS_STARTED=true
      echo "Broker is started and ready"
    else
      echo "Waiting for kafka broker to start..."
    fi
    sleep 5
done

echo "Start restproxy"
docker-compose -f docker-compose.yml -f ./security/restproxy-principal-propagation/docker-compose-mtls-sasl.yml up -d --build --no-deps restproxy 

RESTPROXY_STARTED=false
while [ $RESTPROXY_STARTED == false ]
do
    docker-compose logs restproxy | grep "Started NetworkTrafficServerConnector" &> /dev/null
    if [ $? -eq 0 ]; then
      RESTPROXY_STARTED=true
      echo "Rest Proxy is started and ready"
    else
      echo "Waiting for Rest Proxy to start..."
    fi
    sleep 5
done
echo
echo
echo "Get kafka cluster details via Rest Proxy"
KAFKA_CLUSTER_ID=`curl -s --cacert ./secrets/snakeoil-ca-1.crt --cert ./secrets/client.certificate.pem --key ./secrets/client.key https://localhost:8082/v3/clusters |jq '.data'|jq -r '.[].cluster_id'`
echo "Kafka cluster id is $KAFKA_CLUSTER_ID"

echo
echo "Creat topic test"
curl -s --cacert ./secrets/snakeoil-ca-1.crt --cert ./secrets/client.certificate.pem --key ./secrets/client.key -X POST \
     -H "Content-Type: application/json" \
     -d "{\"topic_name\":\"test\",\"partitions_count\":1,\"replication_factor\":1,\"configs\":[]}" \
     "https://localhost:8082/v3/clusters/${KAFKA_CLUSTER_ID}/topics" | jq .
