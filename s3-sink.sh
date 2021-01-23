#!/bin/bash

TAG=6.0.1

echo
echo "----Start everything up--------------"
docker-compose up -d --build --no-deps zookeeper kafka schemaregistry &>/dev/null
echo
echo "----Download jdbc connector"
ls ./jar/confluentinc-kafka-connect-jdbc/lib/kafka-connect-jdbc-*.jar  || confluent-hub install --component-dir ./jar --no-prompt confluentinc/kafka-connect-jdbc:10.0.1
echo
echo "---Download s3 sink connector"
ls ./jar/confluentinc-kafka-connect-s3/lib/kafka-connect-s3-*.jar || confluent-hub install --component-dir ./jar --no-prompt confluentinc/kafka-connect-s3:5.5.3

echo "----Start connect----"
docker-compose -f docker-compose.yml -f ./connectors/s3/docker-compose-s3.yml up -d --build --no-deps connect &>/dev/null
echo 
echo "----Start postgres------------"
docker-compose up -d --build --no-deps postgres &>/dev/null
echo "Done"
echo
echo "----Start minio-----------"
docker-compose up -d --build --no-deps minio &>/dev/null
sleep 5
echo "----Create bucket--------"
docker-compose up -d --build --no-deps create-buckets &>/dev/null
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
echo "* Create jdbc source connector to postgresql----------done"
docker-compose exec connect curl -X POST -H "Accept:application/json" \
    -H  "Content-Type:application/json" http://localhost:8083/connectors/ \
    -d '{
      "name": "jdbc-pg-connector",
      "config": {
        "connector.class":"io.confluent.connect.jdbc.JdbcSourceConnector",
        "key.converter":"io.confluent.connect.avro.AvroConverter",
        "value.converter":"io.confluent.connect.avro.AvroConverter",
        "key.converter.schema.registry.url":"http://schemaregistry:8081",
        "value.converter.schema.registry.url":"http://schemaregistry:8081",
        "errors.log.enable":"true",
        "errors.log.include.messages":"true",
        "connection.url":"jdbc:postgresql://postgres:5432/postgresdb",
        "connection.user":"postgres",
        "connection.password":"postgres",
        "mode":"incrementing",
        "table.whitelist" : "customers",
        "tasks.max": "1",
        "incrementing.column.name":"id",
        "topic.prefix":""
      }
    }' 
echo
echo "* Create s3 sink connector to minio-----------done"
docker-compose exec connect curl -X POST -H "Content-Type: application/json" http://localhost:8083/connectors/ \
   --data '{
        "name": "s3-sink", 
        "config": {
          "connector.class": "io.confluent.connect.s3.S3SinkConnector", 
          "topics":"customers", 
          "key.converter": "io.confluent.connect.avro.AvroConverter", 
          "key.converter.schema.registry.url": "http://schemaregistry:8081", 
          "value.converter": "io.confluent.connect.avro.AvroConverter", 
          "value.converter.schema.registry.url": "http://schemaregistry:8081",
          "tasks.max": "1", 
          "store.url": "http://minio:9000",
          "s3.bucket.name":"mys3bucket",
          "s3.part.size": "5242880",
          "flush.size": "3",
          "storage.class": "io.confluent.connect.s3.storage.S3Storage",
          "format.class": "io.confluent.connect.s3.format.avro.AvroFormat",
          "schema.generator.class": "io.confluent.connect.storage.hive.schema.DefaultSchemaGenerator",
          "partitioner.class": "io.confluent.connect.storage.partitioner.DefaultPartitioner",
          "schema.compatibility": "NONE"
          }
        }'
echo
sleep 5
echo
echo " >> checking s3 sink connector status"
curl http://localhost:8083/connectors/s3-sink/status
echo
echo "Go to http://localhost:9000 to access minio storage"
