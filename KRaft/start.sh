#!/bin/bash

echo "Setup metadata.properties for broker logs"
mkdir -p logs/kafka logs/kafka1 logs/kafka2

cat << EOF > ./logs/kafka/meta.properties
cluster.id=tbtfRiB3TrayNpmSUeV7Gg
version=1
node.id=0
EOF


cat << EOF > ./logs/kafka1/meta.properties
cluster.id=tbtfRiB3TrayNpmSUeV7Gg
version=1
node.id=1
EOF


cat << EOF > ./logs/kafka2/meta.properties
cluster.id=tbtfRiB3TrayNpmSUeV7Gg
version=1
node.id=2
EOF
echo
echo "Start brokers in KRaft mode"
docker-compose up -d kafka kafka1 kafka2
