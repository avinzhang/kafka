#!/bin/bash

TAG=7.2.1

echo "Setup metadata.properties for broker logs"
mkdir -p logs/kafka1 logs/kafka3 logs/kafka2
CLUSTER_ID=`kafka-storage random-uuid`
cat << EOF > ./logs/kafka1/meta.properties
cluster.id=$CLUSTER_ID
version=1
node.id=1
EOF


cat << EOF > ./logs/kafka2/meta.properties
cluster.id=$CLUSTER_ID
version=1
node.id=2
EOF


cat << EOF > ./logs/kafka3/meta.properties
cluster.id=$CLUSTER_ID
version=1
node.id=3
EOF
echo
echo "Start brokers in KRaft mode"
docker-compose up -d kafka1 kafka2 kafka3
