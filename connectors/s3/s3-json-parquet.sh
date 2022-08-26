#!/bin/bash

TAG=7.2.1.arm64

echo "----Download s3 sink connector"
ls confluent-hub-components/confluentinc-kafka-connect-s3/lib/kafka-connect-s3-*.jar || confluent-hub install --component-dir ./confluent-hub-components --no-prompt confluentinc/kafka-connect-s3:latest
ls confluent-hub-components/confluentinc-kafka-connect-datagen/lib/kafka-connect-datagen-*.jar || confluent-hub install --component-dir ./confluent-hub-components --no-prompt confluentinc/kafka-connect-datagen:latest
ls confluent-hub-components/hadoop-mapred-0.22.0.jar|| wget https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-mapred/0.22.0/hadoop-mapred-0.22.0.jar -P ./confluent-hub-components
echo
echo "----Start everything up--------------"
docker-compose up -d --build --no-deps  zookeeper1 zookeeper2 zookeeper3 kafka1 kafka2 kafka3 schemaregistry connect ksqldb-server controlcenter
echo
echo 
echo "----Start minio-----------"
docker-compose up -d --build --no-deps minio 
sleep 5
#download mc
ls mc || wget https://dl.minio.io/client/mc/release/darwin-arm64/mc && chmod +x ./mc
echo
echo ">>>Create bucket"
./mc config host add myminio http://localhost:9000 minio minio123
./mc admin info myminio
./mc mb myminio/mys3bucket
./mc ls myminio/mys3bucket
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
echo
echo
echo ">> Add connector: datagen-users"
curl -i -X POST \
    -H "Accept:application/json" \
    -H  "Content-Type:application/json" \
   http://localhost:8083/connectors/ -d '
  {
      "name": "datagen-users",
      "config": {
           "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
           "quickstart": "users",
           "name": "datagen-users",
           "kafka.topic": "users",
           "max.interval": "1000",
           "key.converter": "org.apache.kafka.connect.storage.StringConverter",
           "value.converter": "org.apache.kafka.connect.json.JsonConverter",
           "value.converter.schemas.enable": "true",
           "value.converter.schema.registry.url": "http://schemaregistry:8081",
           "tasks.max": "1",
           "iterations": "1000000000"
       }
   }'
echo
sleep 3
echo ">> Check connector status"
echo "Datagen-users: `curl -s http://localhost:8083/connectors/datagen-users/status`"
echo
echo
echo ">> Convert JSON Schema format to Avro using ksqldb"
docker compose exec ksqldb-server bash -c "ksql http://localhost:8088 <<EOF
SET 'auto.offset.reset'='earliest';
CREATE STREAM users (name VARCHAR, calories INT, colour VARCHAR) WITH (KAFKA_TOPIC='users', VALUE_FORMAT='JSON');
CREATE STREAM users_avro WITH (KAFKA_TOPIC='users_avro', KEY_FORMAT='KAFKA', PARTITIONS=1, VALUE_FORMAT='AVRO') AS SELECT * FROM users;
exit;
EOF"
echo
sleep 5
echo
echo "* Create s3 sink connector to minio-----------done"
docker-compose exec connect curl -X POST -H "Content-Type: application/json" http://localhost:8083/connectors/ \
   --data '{
        "name": "s3-sink",
        "config": {
          "connector.class": "io.confluent.connect.s3.S3SinkConnector",
          "topics":"users_avro",
          "key.converter": "org.apache.kafka.connect.storage.StringConverter",
          "value.converter": "io.confluent.connect.avro.AvroConverter",
          "value.converter.schema.registry.url": "http://schemaregistry:8081",
          "tasks.max": "1",
          "store.url": "http://minio:9000",
          "s3.bucket.name":"mys3bucket",
          "s3.part.size": "5242880",
          "flush.size": "3",
          "storage.class": "io.confluent.connect.s3.storage.S3Storage",
          "format.class": "io.confluent.connect.s3.format.parquet.ParquetFormat",
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
echo ">> Check if messages arrived in S3 storage"
./mc ls myminio/mys3bucket/topics/users_avro/partition=0
echo
echo "View http://localhost:9001 to access minio storage also"
