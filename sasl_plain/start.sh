#!/bin/bash

export TAG=7.0.1

echo "----------Start zookeeper and broker -------------"
docker-compose up -d --build --no-deps zookeeper1 zookeeper2 zookeeper3 kafka1 kafka2 kafka3 
echo "Done"
echo
MDS_STARTED=false
while [ $MDS_STARTED == false ]
do
    docker-compose logs kafka1 | grep "Started NetworkTrafficServerConnector" &> /dev/null
    if [ $? -eq 0 ]; then
      MDS_STARTED=true
      echo "MDS is started and ready"
    else
      echo "Waiting for MDS to start..."
    fi
    sleep 5
done
docker-compose exec kafka1 bash -c 'cat << EOF > /tmp/client.properties
sasl.mechanism=PLAIN
security.protocol=SASL_PLAINTEXT
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="kafka" password="kafka";
EOF'
echo
echo "Create ACLs for schema registry"
docker-compose exec kafka1 kafka-acls --bootstrap-server kafka1:1093 --command-config /tmp/client.properties --add \
--allow-principal User:'schemaregistry' --operation all --topic _schemas

docker-compose exec kafka1 kafka-acls --bootstrap-server kafka1:1093 --command-config /tmp/client.properties --add \
--allow-principal User:'schemaregistry' --operation all --group schema-registry

docker-compose exec kafka1 kafka-acls --bootstrap-server kafka1:1093 --command-config /tmp/client.properties --add \
--allow-principal User:'schemaregistry' --operation read --topic _confluent-license
echo

echo
docker-compose up -d --build --no-deps schemaregistry

echo
echo "Create ACLS for Control Center user"
docker-compose exec kafka1 kafka-acls --bootstrap-server kafka1:1093 --command-config /tmp/client.properties --add \
--allow-principal User:'c3' --operation all --topic _confluent-controlcenter --resource-pattern-type prefixed
docker-compose exec kafka1 kafka-acls --bootstrap-server kafka1:1093 --command-config /tmp/client.properties --add \
--allow-principal User:'c3' --operation all --topic _confluent-command
docker-compose exec kafka1 kafka-acls --bootstrap-server kafka1:1093 --command-config /tmp/client.properties --add \
--allow-principal User:'c3' --operation all --topic _confluent-metrics
docker-compose exec kafka1 kafka-acls --bootstrap-server kafka1:1093 --command-config /tmp/client.properties --add \
--allow-principal User:'c3' --operation all --topic _confluent-monitoring
docker-compose exec kafka1 kafka-acls --bootstrap-server kafka1:1093 --command-config /tmp/client.properties --add \
--allow-principal User:'c3' --operation all --group _confluent-controlcenter _confluent-controlcenter --resource-pattern-type prefixed
echo
echo ">> start C3"
docker-compose up -d --build --no-deps controlcenter
echo
