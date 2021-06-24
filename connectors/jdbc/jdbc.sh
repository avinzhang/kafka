#!/bin/bash

TAG=5.5.1

echo "----Download mysql java plugin-------"
if [ ! -f ./jar/mysql-connector-java-8.0.22.jar ]
  then
    wget -P ./jar https://repo1.maven.org/maven2/mysql/mysql-connector-java/8.0.22/mysql-connector-java-8.0.22.jar
fi
echo "Done"
echo
echo "---Download jdbc connector"
ls ./jar/confluentinc-kafka-connect-jdbc/lib/kafka-connect-jdbc-*.jar || confluent-hub install --component-dir ./jar --no-prompt confluentinc/kafka-connect-jdbc:10.0.1
echo
echo "----Start everything up--------------"
docker-compose up -d --build --no-deps zookeeper kafka connect schemaregistry 
echo
echo "----Start mysql-----------"
docker-compose up -d --build --no-deps mysql &>/dev/null
echo "Done"
echo 
echo "----Start postgres------------"
docker-compose up -d --build --no-deps postgres &>/dev/null
echo "Done"
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
echo "--------cat datasource from mysqldb---------------"
cat ./connectors/mysql/db.sql
echo "--------------------------------------------"
echo "* Create jdbc source connector to mysql----------done"
docker-compose exec connect curl -X POST -H "Accept:application/json" \
    -H  "Content-Type:application/json" http://localhost:8083/connectors/ \
    -d '{
      "name": "jdbc-mysql-connector",
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
        "mode":"incrementing",
        "table.whitelist" : "student",
        "tasks.max": "1",
        "incrementing.column.name":"id",
        "topic.prefix":""
      }
    }' 
echo
echo "* Create jdbc sink connector to postgres-----------done"
docker-compose exec connect curl -X POST -H "Content-Type: application/json" http://localhost:8083/connectors/ \
   --data '{
        "name": "jdbc-sink", 
        "config": {
          "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector", 
          "auto.create":"true", 
          "topics":"student", 
          "key.converter": "io.confluent.connect.avro.AvroConverter", 
          "value.converter": "io.confluent.connect.avro.AvroConverter", 
          "tasks.max": "1", 
          "connection.url": "jdbc:postgresql://postgres:5432/postgresdb",  
          "connection.user":"postgres", 
          "connection.password":"postgres", 
          "key.converter.schema.registry.url": "http://schemaregistry:8081", 
          "value.converter.schema.registry.url": "http://schemaregistry:8081" 
          }
        }'
echo
sleep 5
echo
echo
echo "Display records from postgresdb"
docker-compose exec postgres psql -U postgres postgresdb -c "select * from student"
