#!/bin/bash

export TAG=7.2.1.arm64

echo "----------Start zookeeper and broker -------------"
docker compose up -d --build --no-deps zookeeper1 zookeeper2 zookeeper3 
echo "Done"
echo
docker compose up -d --build --no-deps kafka1 kafka2 kafka3 schemaregistry mysql
echo
MDS_STARTED=false
while [ $MDS_STARTED == false ]
do
    docker compose logs kafka1 | grep "Started NetworkTrafficServerConnector" &> /dev/null
    if [ $? -eq 0 ]; then
      MDS_STARTED=true
      echo "MDS is started and ready"
    else
      echo "Waiting for MDS to start..."
    fi
    sleep 5
done
echo
echo ">> Download debezium mysql source connector"
mkdir -p ./confluent-hub-components
ls confluent-hub-components/debezium-debezium-connector-mysql/lib/debezium-connector-mysql-*.jar || confluent-hub install  --component-dir ./confluent-hub-components debezium/debezium-connector-mysql:latest --no-prompt
echo "Done"
echo
echo ">> Starting up Kafka connect"
docker compose up -d --build --no-deps connect
echo
echo
CONNECT_STARTED=false
while [ $CONNECT_STARTED == false ]
do
    docker compose logs connect | grep "Herder started" &> /dev/null
    if [ $? -eq 0 ]; then
      CONNECT_STARTED=true
      echo "Kafka connect is started and ready"
    else
      echo "Waiting for Kafka Connect..."
    fi
    sleep 5
done

echo ">> Add connector: inventory-connector"
curl -i -X POST \
    -H "Accept:application/json" \
    -H  "Content-Type:application/json" \
   http://localhost:8083/connectors/ -d '
  {
      "name": "debezium-mysql-connector",
      "config": {
           "connector.class": "io.debezium.connector.mysql.MySqlConnector",
           "name": "debezium-mysql-connector",
           "tasks.max": "1",
           "database.hostname": "mysql",
           "database.port": "3306",
           "database.user": "debezium",
           "database.password": "dbz",
           "database.server.id": "184054",
           "database.server.name": "mysql",
           "database.whitelist": "inventory",
           "database.history.kafka.bootstrap.servers": "kafka1:1093,kafka2:2093,kafka3:3093",
           "database.history.kafka.topic": "schema-changes.inventory",
           "key.converter": "org.apache.kafka.connect.storage.StringConverter",
           "value.converter": "io.confluent.connect.avro.AvroConverter",
           "value.converter.schema.registry.url": "http://schemaregistry:8081"
       }
   }'
echo
echo ">> Check connector status"
echo "debezium-mysql-connector: `curl -s http://localhost:8083/connectors/debezium-mysql-connector/status`"
echo
sleep 3
echo ">> Consume the topic"
kafka-avro-console-consumer --bootstrap-server localhost:1092 --topic mysql.inventory.customers --from-beginning --property schema.registry.url=http://localhost:8081
