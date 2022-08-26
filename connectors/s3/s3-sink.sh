#!/bin/bash

TAG=7.2.1.arm64

echo "----Download s3 sink connector"
ls confluent-hub-components/confluentinc-kafka-connect-s3/lib/kafka-connect-s3-*.jar || confluent-hub install --component-dir ./confluent-hub-components --no-prompt confluentinc/kafka-connect-s3:latest

ls confluent-hub-components/hadoop-mapred-0.22.0.jar|| wget https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-mapred/0.22.0/hadoop-mapred-0.22.0.jar -P ./confluent-hub-components
echo
echo "----Start everything up--------------"
docker-compose up -d --build --no-deps  zookeeper1 zookeeper2 zookeeper3 kafka1 kafka2 kafka3 schemaregistry connect ksqldb-server
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
echo "Produce some JSON SCHEMA format messages"
echo
kafka-json-schema-console-producer --broker-list localhost:1092,localhost:2092,localhost:3092 --topic snacks_js --property schema.registry.url=http://localhost:8081 --property value.schema='
{
  "definitions" : {
    "record:myrecord" : {
      "type" : "object",
      "required" : [ "name", "calories" ],
      "additionalProperties" : false,
      "properties" : {
        "name" : {"type" : "string"},
        "calories" : {"type" : "number"},
        "colour" : {"type" : "string"}
      }
    }
  }
}' << EOF
{"name": "cookie", "calories": 500, "colour": "brown"}
{"name": "cake", "calories": 260, "colour": "white"}
{"name": "timtam", "calories": 80, "colour": "chocolate"}
EOF
echo
echo
echo ">> Convert JSON Schema format to Avro using ksqldb"
docker compose exec ksqldb-server bash -c "ksql http://localhost:8088 <<EOF
SET 'auto.offset.reset'='earliest';
CREATE STREAM snacks_js (name VARCHAR, calories INT, colour VARCHAR) WITH (KAFKA_TOPIC='snacks_js', VALUE_FORMAT='JSON_SR');
CREATE STREAM snacks_avro WITH (KAFKA_TOPIC='snacks_avro', KEY_FORMAT='KAFKA', PARTITIONS=1, VALUE_FORMAT='AVRO') AS SELECT * FROM snacks_js;
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
          "topics":"snacks_avro",
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
./mc ls myminio/mys3bucket/topics/snacks_avro/partition=0
echo
echo "View http://localhost:9001 to access minio storage also"
