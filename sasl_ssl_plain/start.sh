#!/bin/bash

TAG=6.0.1
datagen_version=latest

echo
echo
echo "----Download datagen connector-----------"
mkdir -p ./jar/datagen
ls jar/datagen/confluentinc-kafka-connect-datagen/lib/kafka-connect-datagen-0.4.0.jar || confluent-hub install  --component-dir ./jar/datagen confluentinc/kafka-connect-datagen:$datagen_version --no-prompt
echo "Done"
echo
echo
echo "----Start everything up with version $TAG------------"
docker-compose up -d --build --no-deps zookeeper kafka connect schemaregistry ksqldb-server controlcenter openldap &>/dev/null
exit
echo
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
echo
echo "* Create datagen-user connector"
curl --cacert ./secrets/snakeoil-ca-1.crt --key ./secrets/connect.key --cert ./secrets/connect-ca1-signed.crt -X POST -H "Content-Type: application/json" https://localhost:8083/connectors/ --data '{"name": "datagen-users", "config": {"connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector", "quickstart": "users", "name": "datagen-users", "kafka.topic": "users", "max.interval": "1000", "key.converter": "org.apache.kafka.connect.storage.StringConverter", "value.converter": "io.confluent.connect.avro.AvroConverter", "tasks.max": "1", "iterations": "1000000000",  "key.converter.schema.registry.url": "https://schemaregistry:8081", "key.converter.schema.registry.ssl.truststore.location": "/etc/kafka/secrets/connect.truststore.jks", "key.converter.schema.registry.ssl.truststore.password": "confluent", "value.converter.schema.registry.url": "https://schemaregistry:8081", "value.converter.schema.registry.ssl.truststore.location": "/etc/kafka/secrets/connect.truststore.jks", "value.converter.schema.registry.ssl.truststore.password": "confluent" }}'

echo "* Create datagen-pageviews connector"
curl --cacert ./secrets/snakeoil-ca-1.crt --key ./secrets/connect.key --cert ./secrets/connect-ca1-signed.crt -X POST -H "Content-Type: application/json" https://localhost:8083/connectors/ --data '{"name": "datagen-pageviews", "config": {"connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector", "quickstart": "pageviews", "name": "datagen-pageviews", "kafka.topic": "pageviews", "max.interval": "1000", "key.converter": "org.apache.kafka.connect.storage.StringConverter", "value.converter": "io.confluent.connect.avro.AvroConverter", "tasks.max": "1", "iterations": "1000000000",  "key.converter.schema.registry.url": "https://schemaregistry:8081", "key.converter.schema.registry.ssl.truststore.location": "/etc/kafka/secrets/connect.truststore.jks", "key.converter.schema.registry.ssl.truststore.password": "confluent", "value.converter.schema.registry.url": "https://schemaregistry:8081", "value.converter.schema.registry.ssl.truststore.location": "/etc/kafka/secrets/connect.truststore.jks", "value.converter.schema.registry.ssl.truststore.password": "confluent" }}'
echo
echo
echo
ksql_ready=false
while [ $ksql_ready == false ]
do
    docker-compose logs ksqldb-server|grep "Server up and running" &> /dev/null
    if [ $? -eq 0 ]; then
      ksql_ready=true
      echo "*** ksqldb is ready ****"
    else
      echo ">>> Waiting for ksqldb to start"
    fi
    sleep 5
done
echo
echo "----Create ksql CLI config file--------"
docker-compose exec ksqldb-server bash -c "cat << EOF > /tmp/client.properties
ssl.truststore.location=/etc/kafka/secrets/ksqldb-server.truststore.jks
ssl.truststore.password=confluent
EOF"
echo "Done"
echo
echo "----Create ksqldb streams----------------"
docker-compose exec ksqldb-server bash -c "ksql --config-file /tmp/client.properties https://ksqldb-server:8088 <<EOF
SET 'auto.offset.reset'='earliest';
CREATE STREAM pageviews (viewtime BIGINT, userid VARCHAR, pageid VARCHAR) WITH (KAFKA_TOPIC='pageviews', REPLICAS=1, VALUE_FORMAT='AVRO');
CREATE TABLE users (userid VARCHAR PRIMARY KEY, registertime BIGINT, gender VARCHAR, regionid VARCHAR) WITH (KAFKA_TOPIC='users', VALUE_FORMAT='AVRO');
CREATE STREAM pageviews_female AS SELECT users.userid AS userid, pageid, regionid, gender FROM pageviews LEFT JOIN users ON pageviews.userid = users.userid WHERE gender = 'FEMALE';
CREATE STREAM pageviews_female_like_89 WITH (kafka_topic='pageviews_enriched_r8_r9', value_format='AVRO') AS SELECT * FROM pageviews_female WHERE regionid LIKE '%_8' OR regionid LIKE '%_9';
CREATE TABLE pageviews_regions AS SELECT gender, regionid , COUNT(*) AS numusers FROM pageviews_female WINDOW TUMBLING (size 30 second) GROUP BY gender, regionid HAVING COUNT(*) > 1;
exit ;
EOF" &> /dev/null
echo "* Creating ktable users ....done"
echo "* Creating kstream pageviews ....done"
echo "* Creating persistent kstream pageviews_female ....done"
echo "* Creating persistent kstream pageviews_female_like_89 ....done"
echo "* Creating persistent ktable pageviews_region .....done"
