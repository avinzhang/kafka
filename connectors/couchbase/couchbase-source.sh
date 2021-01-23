#!/bin/bash

TAG=6.0.1


echo "Download couchbase connector"
ls ./jar/couchbase-kafka-connect-couchbase/lib/kafka-connect-couchbase*.jar || confluent-hub install  --component-dir ./jar couchbase/kafka-connect-couchbase:4.0.2 --no-prompt

echo "Done"


echo "----Start everything up--------------"
docker-compose up -d --build --no-deps zookeeper kafka connect schemaregistry couchbase &>/dev/null
echo
sleep 5
echo
couchbase_ready=false
while [ $couchbase_ready == false ]
do
    docker-compose exec couchbase cat /opt/couchbase/var/lib/couchbase/logs/info.log|grep "Couchbase Server has started on web port 8091" &> /dev/null
    if [ $? -eq 0 ]; then
      couchbase_ready=true
      echo "*** Couchbase is ready ****"
    else
      echo ">>> Waiting for couchbase to start"
    fi
    sleep 2
done

echo " ---Init couchbase cluster"
docker-compose exec couchbase couchbase-cli cluster-init --cluster-username=admin --cluster-password=administrator --services=data,index,query,fts --cluster-ramsize=5512 --cluster-index-ramsize=256 --cluster-fts-ramsize=256 --index-storage-setting=memopt

echo "Create bucket"
docker-compose exec couchbase couchbase-cli bucket-create -c localhost -u admin -p administrator --bucket=couch --bucket-type=couchbase --bucket-ramsize=128 --bucket-replica=1 --wait


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

echo "Create couchbase source connector"
curl -i -X POST -H "Accept:application/json" \
    -H  "Content-Type:application/json" http://localhost:8083/connectors/ \
    -d '{
        "name": "couchbase-source",
        "config": {
            "tasks.max": "1",
            "connector.class": "com.couchbase.connect.kafka.CouchbaseSourceConnector",
            "couchbase.timeout.ms": "2000",
            "couchbase.bucket": "couch",
            "couchbase.username": "admin",
            "couchbase.password": "administrator",
            "couchbase.seed.nodes": "couchbase",
            "couchbase.source.handler": "com.couchbase.connect.kafka.handler.source.RawJsonSourceHandler",
            "value.converter": "org.apache.kafka.connect.converters.ByteArrayConverter",
            "couchbase.stream_from": "SAVED_OFFSET_OR_BEGINNING",
            "couchbase.compression": "ENABLED",
            "couchbase.flow_control_buffer": "128m",
            "couchbase.persistence_polling_interval": "100ms",
            "topic.name": "couchbase",
            "schemaRegistryLocation":"http://schema-registry:8081"
      }
    }'
echo 
sleep 2
echo "Check couchbase connector status"
curl http://localhost:8083/connectors/couchbase-source/status

