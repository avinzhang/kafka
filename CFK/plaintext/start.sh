#!/bin/bash -e

export TAG=7.0.0
export INIT_TAG=2.2.0
echo "Starting up Confluent for Kubernetes"
echo
echo
echo "Creating namespace Confluent if it's not created in kubernetes"
kubectl get ns confluent || kubectl create ns confluent
echo "Set current namespace to confluent"
kubectl config set-context --current --namespace confluent
echo
echo "------------------------------------------"
echo
echo "Add helm repo"
helm repo add confluentinc https://packages.confluent.io/helm
helm repo update

echo 
echo "---------------------------------------"
echo
echo
echo "Install confluent for kubernetes"
helm upgrade --install confluent-operator confluentinc/confluent-for-kubernetes
echo
echo
echo "Install Confluent Platform components"
envsubst < ./plaintext-2.2.0.yaml | kubectl apply -f -
sleep 10
echo 
echo 
echo "-----------------------------------------------------"
echo "Checking kafka connect status"
echo
sleep 10
echo ">>Waiting for kafka connect pods to be created"
connect_pod_created=false
while [ $connect_pod_created == false ]
do
    kubectl get po connect-0 
    if [ $? -eq 0 ]; then
      connect_pod_created=true
      echo ">>>>All connect pods are created"
    else
      echo ">>>>Waiting for connect pods to be created"
    fi
    sleep 5
done
echo
echo ">>Waiting for connect pods to come up"
kubectl wait --for=condition=Ready pod/connect-0 --timeout=400s
echo
echo 
echo ">>Waiting for schema registry pods to be created"
schemaregistry_pod_created=false
while [ $schemaregistry_pod_created == false ]
do
    kubectl get po schemaregistry-0
    if [ $? -eq 0 ]; then
      schemaregistry_pod_created=true
      echo ">>>>All schema registry pods are created"
    else
      echo ">>>>Waiting for schema registry pods to be created"
    fi
    sleep 5
done
echo ">>Waiting for schemaregistry pods to come up"
kubectl wait --for=condition=Ready pod/schemaregistry-0 --timeout=400s 
echo
echo
echo
echo ">> Adding connector: datagen-users"
kubectl exec -it connect-0 -- curl -i -X POST \
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
   }' &> /dev/null

echo
echo ">> Add connector: datagen-pageviews"

kubectl exec -it connect-0 -- curl -i -X POST \
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
   }' &> /dev/null
echo
sleep 3
echo ">>>> Check datagen-users connector status: `kubectl exec -it connect-0 -- curl http://localhost:8083/connectors/datagen-users/status | jq .connector.state`"
echo 
echo ">>>> Check datagen-pageviews connector status: `kubectl exec -it connect-0 -- curl http://localhost:8083/connectors/datagen-pageviews/status | jq .connector.state`" 
echo 
echo 
echo "----------------------------------------------------"
echo ">>Waiting for schema registry pods to be created"
ksql_pod_created=false
while [ $ksql_pod_created == false ]
do
    kubectl get po ksqldb-0
    if [ $? -eq 0 ]; then
      ksql_pod_created=true
      echo ">>>>All ksqldb pods are created"
    else
      echo ">>>>Waiting for ksqldb pods to be created"
    fi
    sleep 5
done
echo "Check ksqldb status"
kubectl wait --for=condition=Ready pod/ksqldb-0 --timeout=400s 
echo
echo ">>Create ksqldb streams"
kubectl exec -it ksqldb-0 -- bash -c "ksql http://ksqldb:8088 <<EOF
SET 'auto.offset.reset'='earliest';
SET 'ksql.schema.registry.url'='http://schemaregistry:8081';
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


