#!/bin/bash

TAG=7.2.1.arm64

echo "----Download s3 sink connector"
ls confluent-hub-components/confluentinc-kafka-connect-s3-source/lib/kafka-connect-s3-source-*.jar || confluent-hub install --component-dir ./confluent-hub-components --no-prompt confluentinc/kafka-connect-s3-source:latest
echo
echo "----Start everything up--------------"
docker-compose up -d --build --no-deps  zookeeper1 zookeeper2 zookeeper3 kafka1 kafka2 kafka3 schemaregistry connect 
echo
echo 
echo "----Start minio-----------"
docker-compose up -d --build --no-deps minio 
sleep 5
#download mc
brew list mc || brew install minio/stable/mc
echo
echo ">>>Create bucket"
mc config host add myminio http://localhost:9000 minio minio123
mc admin info myminio
mc mb myminio/mys3bucket/mymessage
mc ls myminio/mys3bucket
echo
echo "Upload data to bucket"
cat << EOF > /tmp/message.txt
{"f1":"value1"}
{"f1":"value2"}
{"f1":"value3"}
{"f1":"value4"}
{"f1":"value5"}
{"f1":"value6"}
{"f1":"value7"}
{"f1":"value8"}
EOF
mc cp /tmp/message.txt myminio/mys3bucket/mymessage
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
echo "* Create s3 source connector -----------done"
docker-compose exec connect curl -X POST -H "Content-Type: application/json" http://localhost:8083/connectors/ \
   --data '{
        "name": "s3-source",
        "config": {
          "connector.class": "io.confluent.connect.s3.source.S3SourceConnector",
          "topics.dir":"mymessage",
          "topic.regex.list": "mymessage:.*",
          "value.converter": "org.apache.kafka.connect.json.JsonConverter",
          "value.converter.schemas.enable": "false",
          "format.class": "io.confluent.connect.s3.format.json.JsonFormat",
          "mode": "GENERIC",
          "tasks.max": "1",
          "store.url": "http://minio:9000",
          "s3.bucket.name":"mys3bucket"
          }
        }'
echo
sleep 5
echo
echo " >> checking s3 source connector status"
curl http://localhost:8083/connectors/s3-source/status
echo
echo "View http://localhost:9001 to access minio storage also"
echo 
echo ">> Consume from topic mymessage"
kafka-console-consumer --bootstrap-server localhost:1092 --topic mymessage --from-beginning

