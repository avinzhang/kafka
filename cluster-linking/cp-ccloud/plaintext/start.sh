#!/bin/bash

export TAG=7.1.1.arm64

echo "----------Start zookeeper and broker -------------"
docker compose up -d --build --no-deps zookeeper1 zookeeper2 zookeeper3 
echo "Done"
echo
docker compose up -d --build --no-deps kafka1 kafka2 kafka3 schemaregistry
echo
MDS_STARTED=false
while [ $MDS_STARTED == false ]
do
    docker compose logs kafka1 | grep "Started NetworkTrafficServerConnector" &> /dev/null
    if [ $? -eq 0 ]; then
      MDS_STARTED=true
      echo "MDS is started and ready"
    else
      echo "Waiting for MDS to start..."
    fi
    sleep 5
done
echo
echo ">> Download datagen connector"
mkdir -p ./jar/datagen
ls ./jar/datagen/confluentinc-kafka-connect-datagen/lib/kafka-connect-datagen-*.jar || confluent-hub install  --component-dir ./jar/datagen confluentinc/kafka-connect-datagen:latest --no-prompt
echo "Done"
echo ">> Download replicator connector"
ls ./jar/confluentinc-kafka-connect-replicator/lib/replicator-rest-extension-*.jar || confluent-hub install --no-prompt --component-dir ./jar confluentinc/kafka-connect-replicator:latest
echo
echo ">> Starting up Kafka connect"
docker compose up -d --build --no-deps connect
echo
echo
CONNECT_STARTED=false
while [ $CONNECT_STARTED == false ]
do
    docker compose logs connect | grep "Herder started" &> /dev/null
    if [ $? -eq 0 ]; then
      CONNECT_STARTED=true
      echo "Kafka connect is started and ready"
    else
      echo "Waiting for Kafka Connect..."
    fi
    sleep 5
done

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
           "value.converter": "io.confluent.connect.avro.AvroConverter",
           "value.converter.schema.registry.url": "http://schemaregistry:8081",
           "tasks.max": "1",
           "iterations": "1000000000"
       }
   }'
echo
sleep 5
echo ">> Check connector status"
echo "Datagen-users: `curl -s http://localhost:8083/connectors/datagen-users/status`"
echo
echo
echo ">> Add connector: datagen-pageviews"
curl -i -X POST \
    -H "Accept:application/json" \
    -H  "Content-Type:application/json" \
   http://localhost:8083/connectors/ -d '
  {
      "name": "datagen-pageviews",
      "config": {
           "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
           "quickstart": "pageviews",
           "name": "datagen-pageviews",
           "kafka.topic": "pageviews",
           "max.interval": "1000",
           "key.converter": "org.apache.kafka.connect.storage.StringConverter",
           "value.converter": "io.confluent.connect.avro.AvroConverter",
           "value.converter.schema.registry.url": "http://schemaregistry:8081",
           "tasks.max": "1",
           "iterations": "1000000000"
       }
   }'

sleep 5
echo
echo ">> Check connector status"
echo "Datagen-pageviews: `curl -s http://localhost:8083/connectors/datagen-pageviews/status`"
echo

echo "Login Confluent Cloud"
confluent login --save

echo ">> Set cloud environment"
confluent environment use `confluent environment list -ojson | jq -r '.[]|select(.name == "avin").id'`
echo
echo ">> Set cloud cluster ID "
confluent kafka cluster use `terraform -chdir=./cloud output -json | jq -r '."cloud-cluster-id"."value"'`
echo
echo ">> Get cluster link api key"
export CL_API_KEY=`terraform -chdir=./cloud output -json | jq -r '."cluster-link-api-key"."value"'`
export CL_API_SECRET=`terraform -chdir=./cloud output -json | jq -r '."cluster-link-api-secret"."value"'`

echo ">> Create config file for cluster link on cloud cluster"
cat << EOF > /tmp/cluterlink-dst.config
link.mode=DESTINATION
connection.mode=INBOUND
auto.create.mirror.topics.enable=true
auto.create.mirror.topics.filters={ "topicFilters": [ {"name": "user",  "patternType": "PREFIXED",  "filterType": "INCLUDE"} ] }
EOF

echo 
export CLOUD_CLUSTER_ID=`terraform -chdir=./cloud output -json | jq -r '."cloud-cluster-id"."value"'`
export CP_CLUSTER_ID=`curl -s  http://localhost:1090/v1/metadata/id  | grep id |jq -r ".id"`

echo "Create cluster link on Cloud cluster"
confluent kafka link create from-on-prem-link --cluster $CLOUD_CLUSTER_ID --source-cluster-id $CP_CLUSTER_ID --config-file /tmp/cluterlink-dst.config
echo
export CLOUD_ENDPOINT=`confluent kafka cluster describe $CLOUD_CLUSTER_ID -ojson |jq -r .endpoint`
docker-compose exec kafka1 bash -c "cat <<EOF > /tmp/clusterlink-cp-src.config
link.mode=SOURCE
connection.mode=OUTBOUND

bootstrap.servers=$CLOUD_ENDPOINT
ssl.endpoint.identification.algorithm=https
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username='$CL_API_KEY' password='$CL_API_SECRET';

local.listener.name=PLAINTEXT
local.security.protocol=PLAINTEXT
EOF"

echo ">>Create link on source cluster"
docker-compose exec kafka1 bash -c "kafka-cluster-links --bootstrap-server kafka1:1093 --create --link from-on-prem-link --config-file /tmp/clusterlink-cp-src.config --cluster-id $CLOUD_CLUSTER_ID"

echo ">>List link on source cluster"
docker-compose exec kafka1 bash -c "kafka-cluster-links --list --bootstrap-server localhost:1093"

echo ">>Create mirror topics"
confluent kafka mirror create users --link from-on-prem-link

echo >>"list mirrored topics"
confluent kafka mirror list --cluster $CLOUD_CLUSTER_ID

### Delete mirrored topics, requires to exclude the topics first before it can be deleted
#cat << EOF > /tmp/cluterlink-dst.config
#link.mode=DESTINATION
#connection.mode=INBOUND
#auto.create.mirror.topics.enable=true
#auto.create.mirror.topics.filters={ "topicFilters": [ {"name": "user",  "patternType": "PREFIXED",  "filterType": "EXCLUDE"} ] }
#EOF
#
#confluent kafka link update from-on-prem-link --config-file /tmp/cluterlink-dst.config
#confluent kafka topic delete users
#confluent kafka link delete from-on-prem-link
echo

