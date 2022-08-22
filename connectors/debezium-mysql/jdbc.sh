#!/bin/bash

TAG=7.2.1.arm64

echo "----Download jdbc connector-------"
mkdir -p ./confluent-hub-components
ls confluent-hub-components/confluentinc-kafka-connect-jdbc/lib/kafka-connect-jdbc-*.jar || confluent-hub install  --component-dir ./confluent-hub-components confluentinc/kafka-connect-jdbc:latest --no-prompt
echo
echo "----Start everything up--------------"
docker-compose up -d --build --no-deps zookeeper1 zookeeper2 zookeeper3 kafka1 kafka2 kafka3 schemaregistry mysql connect
echo
echo
connect_ready=false
while [ $connect_ready == false ]
do
    docker-compose logs connect|grep "Herder started" &> /dev/null
    if [ $? -eq 0 ]; then
      connect_ready=true
      echo "*** Kafka Connect is ready ****"
    else
      echo ">>> Waiting for kafka connect to start"
    fi
    sleep 5
done
echo
echo "* Create jdbc source connector to mysql----------done"
docker-compose exec connect curl -X POST -H "Accept:application/json" \
    -H  "Content-Type:application/json" http://localhost:8083/connectors/ \
    -d '{
      "name": "jdbc-mysql-connector",
      "config": {
        "connector.class":"io.confluent.connect.jdbc.JdbcSourceConnector",
        "key.converter":"org.apache.kafka.connect.storage.StringConverter",
        "value.converter":"io.confluent.connect.avro.AvroConverter",
        "value.converter.schema.registry.url":"http://schemaregistry:8081",
        "errors.log.enable":"true",
        "errors.log.include.messages":"true",
        "connection.url":"jdbc:mysql://mysql:3306/inventory",
        "connection.user":"debezium",
        "connection.password":"dbz",
        "mode":"incrementing",
        "table.whitelist" : "customers",
        "tasks.max": "1",
        "incrementing.column.name":"id",
        "topic.prefix":""
      }
    }' 
echo
sleep 5
echo
echo
echo "Consume records"
kafka-avro-console-consumer --bootstrap-server localhost:1092 --topic customers --from-beginning --property schema.registry.url=http://localhost:8081
