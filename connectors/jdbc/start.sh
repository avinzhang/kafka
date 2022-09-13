#!/bin/bash

export TAG=7.2.1.arm64

mkdir -p ./confluent-hub-components
ls ./confluent-hub-components/confluentinc-kafka-connect-jdbc/lib/kafka-connect-jdbc*.jar || confluent-hub install  --component-dir ./confluent-hub-components confluentinc/kafka-connect-jdbc:latest --no-prompt
echo
echo "----Download mysql java plugin-------"
ls ./confluent-hub-components/mysql-connector-java-8.0.22.jar || wget -P ./confluent-hub-components https://repo1.maven.org/maven2/mysql/mysql-connector-java/8.0.22/mysql-connector-java-8.0.22.jar
echo "Done"
echo
echo "----------Start zookeeper and broker -------------"
docker-compose up -d --build --no-deps zookeeper1 zookeeper2 zookeeper3 
echo "Done"
echo
docker-compose up -d --build --no-deps kafka1 kafka2 kafka3 schemaregistry connect mysql
echo
echo
ready=false
while [ $ready == false ]
do
    docker-compose logs connect|grep "Herder started" &> /dev/null
    if [ $? -eq 0 ]; then
      ready=true
      echo "*** Kafka Connect is ready ****"
    else
      echo ">>> Waiting for kafka connect to start"
    fi
    sleep 5
done
echo
sleep 3
echo ">> Check hdfs connector status"
curl http://localhost:8083/connectors/hdfs-sink/status
echo
echo
echo "--------show datasource records from mysql---------------"
docker-compose exec mysql mysql -uroot -prootpass -e "use mysqldb;select * from student" 
echo
echo "--------------------------------------------"
echo "* Create jdbc source connector to mysql----------done"
docker-compose exec connect curl -X POST -H "Accept:application/json" \
    -H  "Content-Type:application/json" http://localhost:8083/connectors/ \
    -d '{
      "name": "jdbc-connector",
      "config": {
        "connector.class":"io.confluent.connect.jdbc.JdbcSourceConnector",
        "key.converter":"io.confluent.connect.avro.AvroConverter",
        "value.converter":"io.confluent.connect.avro.AvroConverter",
        "key.converter.schema.registry.url":"http://schemaregistry:8081",
        "value.converter.schema.registry.url":"http://schemaregistry:8081",
        "errors.log.enable":"true",
        "errors.log.include.messages":"true",
        "connection.url":"jdbc:mysql://mysql:3306/mysqldb",
        "connection.user":"root",
        "connection.password":"rootpass",
        "mode":"timestamp+incrementing",
        "timestamp.column.name": "updated_at",
        "table.whitelist" : "student",
        "tasks.max": "1",
        "incrementing.column.name":"id",
        "topic.prefix":""
      }
    }'
echo
sleep 5
echo
echo ">> Consume records from kafka"
kafka-avro-console-consumer --bootstrap-server localhost:1092 --topic student --from-beginning --property schema.registry.url=http://localhost:8081
