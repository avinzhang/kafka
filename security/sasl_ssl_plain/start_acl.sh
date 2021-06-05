#!/bin/bash

TAG=6.1.1

echo "----Start everything up with version $TAG------------"
docker-compose -f docker-compose.yml -f ./security/sasl_ssl_plain/docker-compose-sasl-ssl-plain-with-authorizer.yml up -d --build --no-deps openldap zookeeper kafka 

echo 
echo ">> Check if broker is ready"
MDS_STARTED=false
while [ $MDS_STARTED == false ]
do
    docker-compose logs kafka | grep "Started NetworkTrafficServerConnector" &> /dev/null
    if [ $? -eq 0 ]; then
      MDS_STARTED=true
      echo "MDS is started and ready"
    else
      echo "Waiting for MDS to start..."
    fi
    sleep 5
done
echo
echo "Add client.properties to kafka broker"
docker-compose exec kafka bash -c 'cat << EOF > /tmp/client.properties
sasl.mechanism=PLAIN
security.protocol=SASL_SSL
ssl.truststore.location=/etc/kafka/secrets/kafka.truststore.jks
ssl.truststore.password=confluent
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="kafka" password="kafka";
EOF'
echo 
echo "----Download datagen connector-----------"
mkdir -p ./jar/datagen
ls ./jar/datagen/confluentinc-kafka-connect-datagen/lib/kafka-connect-datagen-0.4.0.jar || confluent-hub install  --component-dir ./jar/datagen confluentinc/kafka-connect-datagen:latest --no-prompt
echo "Done"
echo
echo "Create ACLs for kafka connect worker"
docker-compose exec kafka kafka-acls --bootstrap-server kafka:9093 --command-config /tmp/client.properties --add \
--allow-principal User:'connect' --operation all --topic connect --resource-pattern-type prefixed
docker-compose exec kafka kafka-acls --bootstrap-server kafka:9093 --command-config /tmp/client.properties --add \
--allow-principal User:'connect' --operation read --topic _confluent-monitoring 
docker-compose exec kafka kafka-acls --bootstrap-server kafka:9093 --command-config /tmp/client.properties --add \
--allow-principal User:'connect' --operation all --topic _confluent-secrets
docker-compose exec kafka kafka-acls --bootstrap-server kafka:9093 --command-config /tmp/client.properties --add \
--allow-principal User:'connect' --operation all --topic _confluent-command
docker-compose exec kafka kafka-acls --bootstrap-server kafka:9093 --command-config /tmp/client.properties --add \
--allow-principal User:'connect' --operation all --group connect-cluster
echo
echo "Create ACLs for schema registry"
docker-compose exec kafka kafka-acls --bootstrap-server kafka:9093 --command-config /tmp/client.properties --add \
--allow-principal User:'schemaregistry' --operation all --topic _schemas

docker-compose exec kafka kafka-acls --bootstrap-server kafka:9093 --command-config /tmp/client.properties --add \
--allow-principal User:'schemaregistry' --operation all --group schema-registry

docker-compose exec kafka kafka-acls --bootstrap-server kafka:9093 --command-config /tmp/client.properties --add \
--allow-principal User:'schemaregistry' --operation read --topic _confluent-license
echo
echo "---Start schemaregistry connect" 
docker-compose -f docker-compose.yml -f ./security/sasl_ssl_plain/docker-compose-sasl-ssl-plain-with-authorizer.yml up -d --build --no-deps schemaregistry connect 
echo
echo
echo ">> Check if kafka connect is ready"
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
echo "Create ACLs for connect user to create datagen-user connector"
docker-compose exec kafka kafka-acls --bootstrap-server kafka:9093 --command-config /tmp/client.properties --add \
--allow-principal User:'connect' --operation all --topic users 
echo
echo "* Create datagen-user connector"
curl --cacert ./secrets/ca.crt --key ./secrets/connect.key --cert ./secrets/connect-ca-signed.crt -X POST -H "Content-Type: application/json" https://localhost:8083/connectors/ --data '{
  "name": "datagen-users", 
  "config": {
    "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector", 
    "quickstart": "users", 
    "name": "datagen-users", 
    "kafka.topic": "users", 
    "max.interval": "1000", 
    "key.converter": "org.apache.kafka.connect.storage.StringConverter", 
    "value.converter": "io.confluent.connect.avro.AvroConverter", 
    "tasks.max": "1", 
    "iterations": "1000000000",  
    "key.converter.schema.registry.url": "https://schemaregistry:8081", 
    "key.converter.schema.registry.ssl.truststore.location": "/etc/kafka/secrets/connect.truststore.jks", 
    "key.converter.schema.registry.ssl.truststore.password": "confluent", 
    "value.converter.schema.registry.url": "https://schemaregistry:8081", 
    "value.converter.schema.registry.ssl.truststore.location": "/etc/kafka/secrets/connect.truststore.jks", 
    "value.converter.schema.registry.ssl.truststore.password": "confluent" 
    }
  }'

echo
sleep 2
echo "     Check status"
curl --cacert ./secrets/ca.crt  https://localhost:8083/connectors/datagen-users/status
echo 
echo "Create ACLs for connect user to create datagen-pageviews connector"
docker-compose exec kafka kafka-acls --bootstrap-server kafka:9093 --command-config /tmp/client.properties --add \
--allow-principal User:'connect' --operation all --topic pageviews
echo "* Create datagen-pageviews connector"
curl --cacert ./secrets/ca.crt --key ./secrets/connect.key --cert ./secrets/connect-ca-signed.crt -X POST -H "Content-Type: application/json" https://localhost:8083/connectors/ --data '{
  "name": "datagen-pageviews", 
  "config": {
    "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector", 
    "quickstart": "pageviews", 
    "name": "datagen-pageviews", 
    "kafka.topic": "pageviews", 
    "max.interval": "1000", 
    "key.converter": "org.apache.kafka.connect.storage.StringConverter", 
    "value.converter": "io.confluent.connect.avro.AvroConverter", 
    "tasks.max": "1", "iterations": "1000000000",  
    "key.converter.schema.registry.url": "https://schemaregistry:8081", 
    "key.converter.schema.registry.ssl.truststore.location": "/etc/kafka/secrets/connect.truststore.jks", 
    "key.converter.schema.registry.ssl.truststore.password": "confluent", 
    "value.converter.schema.registry.url": "https://schemaregistry:8081", 
    "value.converter.schema.registry.ssl.truststore.location": "/etc/kafka/secrets/connect.truststore.jks", 
    "value.converter.schema.registry.ssl.truststore.password": "confluent" 
    }
  }'

echo
sleep 2
echo "     Check status"
curl --cacert ./secrets/ca.crt  https://localhost:8083/connectors/datagen-pageviews/status
echo  
echo
echo "Create ACLs for ksqldb-server cluster"
docker-compose exec kafka kafka-acls --bootstrap-server kafka:9093 --command-config /tmp/client.properties --add \
--allow-principal User:'ksql' --operation all --topic _confluent-ksql-ksql-cluster --resource-pattern-type prefixed

docker-compose exec kafka kafka-acls --bootstrap-server kafka:9093 --command-config /tmp/client.properties --add \
--allow-principal User:'ksql' --operation all --topic _confluent-monitoring
docker-compose exec kafka kafka-acls --bootstrap-server kafka:9093 --command-config /tmp/client.properties --add \
--allow-principal User:'ksql' --operation all --topic ksql-clusterksql_processing_log
docker-compose exec kafka kafka-acls --bootstrap-server kafka:9093 --command-config /tmp/client.properties --add \
--allow-principal User:'ksql' --operation all --group _confluent-ksql-ksql-cluster --resource-pattern-type prefixed
echo
echo "Create ACLS for streams and tables"
docker-compose exec kafka kafka-acls --bootstrap-server kafka:9093 --command-config /tmp/client.properties --add \
--allow-principal User:'ksql' --operation all --topic users --resource-pattern-type prefixed
docker-compose exec kafka kafka-acls --bootstrap-server kafka:9093 --command-config /tmp/client.properties --add \
--allow-principal User:'ksql' --operation all --topic PAGEVIEWS --resource-pattern-type prefixed
docker-compose exec kafka kafka-acls --bootstrap-server kafka:9093 --command-config /tmp/client.properties --add \
--allow-principal User:'ksql' --operation all --transactional-id ksql-cluster 

echo "Create ACLs for restproxy"
echo "Create ACLS for Control Center user"
docker-compose exec kafka kafka-acls --bootstrap-server kafka:9093 --command-config /tmp/client.properties --add \
--allow-principal User:'c3' --operation all --topic _confluent-controlcenter --resource-pattern-type prefixed
docker-compose exec kafka kafka-acls --bootstrap-server kafka:9093 --command-config /tmp/client.properties --add \
--allow-principal User:'c3' --operation all --topic _confluent-command
docker-compose exec kafka kafka-acls --bootstrap-server kafka:9093 --command-config /tmp/client.properties --add \
--allow-principal User:'c3' --operation all --topic _confluent-metrics
docker-compose exec kafka kafka-acls --bootstrap-server kafka:9093 --command-config /tmp/client.properties --add \
--allow-principal User:'c3' --operation all --topic _confluent-monitoring
docker-compose exec kafka kafka-acls --bootstrap-server kafka:9093 --command-config /tmp/client.properties --add \
--allow-principal User:'c3' --operation all --group _confluent-controlcenter _confluent-controlcenter --resource-pattern-type prefixed
echo
docker-compose -f docker-compose.yml -f ./security/sasl_ssl_plain/docker-compose-sasl-ssl-plain-with-authorizer.yml up -d --build --no-deps ksqldb-server restproxy controlcenter 
echo
echo ">> Check if ksqldb server is ready"
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
echo
echo ">> Create ksql CLI config file--------"
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
