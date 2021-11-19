#!/bin/bash -e
#supports up to kubernetes 1.18 only

export TAG=7.0.0
export INIT_TAG=2.2.0
echo
echo
echo "Namespace is confluent, creating it if it's not created in kubernetes"
kubectl get ns confluent || kubectl create ns confluent
echo
echo "Set current namespace to confluent"
kubectl config set-context --current --namespace confluent
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
sleep 5
echo "Done"
echo
echo "---------------------------------------"
echo "Setup various secrets" 
echo 
echo ">>Create SSL secrets"
# For auto generated SSL certs only
#echo "Generate SSL CA"
#openssl genrsa -out /tmp/ca-key.pem 2048
#openssl req -new -key /tmp/ca-key.pem -x509 -days 1000 -out /tmp/ca.pem -subj '/CN=ca.cse.example.com/OU=CSE/O=CONFLUENT/L=MountainView/ST=Ca/C=US'
#
#echo "Add CA as a secret"
#kubectl -n confluent create secret tls ca-pair-sslcerts \
#  --cert=/tmp/ca.pem \
#  --key=/tmp/ca-key.pem
#
# To use your own SSL certs
echo "Setup TLS secrets for each component"
for i in zookeeper kafka connect schemaregistry ksqldb controlcenter
  do
    echo ">>>>>Creating secret tls-$i"
    kubectl create secret generic tls-$i \
    --from-file=fullchain.pem=../certs/$i-ca1-signed.crt \
    --from-file=cacerts.pem=../certs/ca.crt \
       --from-file=privkey.pem=../certs/$i.key
done
echo
echo
echo "-----------------------------------------"
echo "Install zookeeper"
envsubst < ./zookeeper.yaml | kubectl apply -f -
sleep 20
echo "Wait for zookeeper pods"
kubectl wait --for=condition=Ready pod/zookeeper-0 --timeout=300s -n confluent
kubectl wait --for=condition=Ready pod/zookeeper-1 --timeout=300s -n confluent
kubectl wait --for=condition=Ready pod/zookeeper-2 --timeout=300s -n confluent
echo
echo 
echo "----------------------------------------"
echo "Install kafka broker"
envsubst < ./kafka.yaml | kubectl apply -f -
echo
echo
echo ">>Waiting for kafka pods to be created"
kafka_pod_created=false
while [ $kafka_pod_created == false ]
do
    kubectl get po kafka-0 &> /dev/null && kubectl get po kafka-1 &> /dev/null && kubectl get po kafka-2 &> /dev/null
    if [ $? -eq 0 ]; then
      kafka_pod_created=true
      echo ">>>>All kafka pods are created"
    else
      echo ">>>>Not all kafka pods are created..."
    fi
    sleep 5
done
echo
echo ">>>>Waiting for kafka pods to come up"
kubectl wait --for=condition=Ready pod/kafka-0 --timeout=600s 
kubectl wait --for=condition=Ready pod/kafka-1 --timeout=600s
kubectl wait --for=condition=Ready pod/kafka-2 --timeout=600s 
echo
echo
echo ">>Adding ssl client.properties to kafka-0 pod"
kubectl -n confluent exec -it kafka-0 -- bash -c 'cat << EOF > /tmp/client.properties
security.protocol=SSL
ssl.truststore.location=/mnt/sslcerts/truststore.jks
ssl.truststore.password=mystorepassword
EOF'
echo "Done"

echo 
echo 
echo "-----------------------------------------"
echo "Install schema registry"
envsubst < ./schemaregistry.yaml | kubectl apply -f -
sleep 5
kubectl wait --for=condition=Ready pod/schemaregistry-0 --timeout=600s 
echo
echo 
echo "------------------------------------------"
echo "Install Kafka connect"
envsubst < ./connect.yaml | kubectl apply -f -
sleep 5
echo ">>Waiting for connect pods to come up"
kubectl wait --for=condition=Ready pod/connect-0 --timeout=600s
echo 
echo ">>Waiting for kafka pods to be created"
connect_ready=false
while [ $connect_ready == false ]
do
    kubectl exec -it connect-0 -- curl --cacert /mnt/sslcerts/cacerts.pem https://connect:8083 &> /dev/null 
    if [ $? -eq 0 ]; then
      connect_ready=true
      echo ">>>>kafka connect is ready"
    else
      echo ">>>>waiting for kafka connect to become ready..."
    fi
    sleep 5
done
echo
echo "Create datagen-users connector"
kubectl exec -it connect-0 -- curl --cacert /mnt/sslcerts/cacerts.pem -X POST -H "Content-Type: application/json" https://connect:8083/connectors/ \
-d '{"name": "datagen-users",
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
       "value.converter.schema.registry.url": "https://schemaregistry:8081",
       "value.converter.schema.registry.ssl.truststore.location": "/mnt/sslcerts/truststore.p12",
       "value.converter.schema.registry.ssl.truststore.password": "mystorepassword"
       }
  }'
echo "Done"

echo "Creat datagen-pageviews connector"
kubectl exec -it connect-0 -- curl --cacert /mnt/sslcerts/cacerts.pem -X POST -H "Content-Type: application/json" https://connect:8083/connectors/ \
-d '{"name": "datagen-pageviews",
     "config": {
       "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
       "quickstart": "pageviews",
       "name": "datagen-pageviews",
       "kafka.topic": "pageviews",
       "max.interval": "1000",
       "key.converter": "org.apache.kafka.connect.storage.StringConverter",
       "value.converter": "io.confluent.connect.avro.AvroConverter",
       "value.converter.schema.registry.url": "https://schemaregistry:8081",
       "value.converter.schema.registry.ssl.truststore.location": "/mnt/sslcerts/truststore.p12",
       "value.converter.schema.registry.ssl.truststore.password": "mystorepassword",
       "tasks.max": "1",
       "iterations": "1000000000"
       }
    }'
echo "Done"
echo 
echo ">>Check connectors status"
kubectl exec -it connect-0 -- curl --cacert /mnt/sslcerts/cacerts.pem https://connect:8083/connectors/datagen-users/status
echo
kubectl exec -it connect-0 -- curl --cacert /mnt/sslcerts/cacerts.pem https://connect:8083/connectors/datagen-pageviews/status
echo
echo
echo "------------------------------------------"
echo "Install ksqldb"
envsubst < ./ksqldb.yaml | kubectl apply -f -
sleep 5
echo 
ksqldb_pod_created=false
while [ $ksqldb_pod_created == false ]
do
    kubectl get po ksqldb-0 
    if [ $? -eq 0 ]; then
      ksqldb_pod_created=true
      echo ">>>>All ksqldb pods are created"
    else
      echo ">>>>Not all ksqldb pods are created..."
    fi
    sleep 5
done
echo
echo ">>>>Waiting for ksqldb pods to come up"
kubectl wait --for=condition=Ready pod/ksqldb-0 --timeout=600s 

echo "Create ksqldb config file for client"
kubectl exec -it ksqldb-0 -- bash -c 'cat << EOF > /tmp/client-ssl.properties
ssl.truststore.location=/mnt/sslcerts/truststore.p12
ssl.truststore.password=mystorepassword
EOF'
echo "Done"
echo "Create ksqldb streams"
kubectl exec -it  ksqldb-0 --  bash -c "ksql --config-file /tmp/client-ssl.properties https://ksqldb:8088 <<EOF
SET 'auto.offset.reset'='earliest';
CREATE STREAM pageviews (viewtime BIGINT, userid VARCHAR, pageid VARCHAR) WITH (KAFKA_TOPIC='pageviews', REPLICAS=3, VALUE_FORMAT='AVRO');
CREATE TABLE users (userid VARCHAR PRIMARY KEY, registertime BIGINT, gender VARCHAR, regionid VARCHAR) WITH (KAFKA_TOPIC='users', VALUE_FORMAT='AVRO');
CREATE STREAM pageviews_female AS SELECT users.userid AS userid, pageid, regionid, gender FROM pageviews LEFT JOIN users ON pageviews.userid = users.userid WHERE gender = 'FEMALE';
CREATE STREAM pageviews_female_like_89 WITH (kafka_topic='pageviews_enriched_r8_r9', value_format='AVRO') AS SELECT * FROM pageviews_female WHERE regionid LIKE '%_8' OR regionid LIKE '%_9';
CREATE TABLE pageviews_regions with (kafka_topic='pageviews_regions', key_format='json') AS SELECT gender, regionid , COUNT(*) AS numusers FROM pageviews_female WINDOW TUMBLING (size 30 second) GROUP BY gender, regionid HAVING COUNT(*) > 1;
exit ;
EOF"
echo
echo
echo "------------------------------------------"
echo "Install Control Center"
envsubst < ./controlcenter.yaml | kubectl apply -f -
sleep 5
echo ">>Waiting for controlcenter pods to come up"
c3_pod_created=false
while [ $c3_pod_created == false ]
do
    kubectl get po controlcenter-0 &> /dev/null 
    if [ $? -eq 0 ]; then
      c3_pod_created=true
      echo ">>>>All Control Center pods are created"
    else
      echo ">>>>Not all c3 pods are created..."
    fi
    sleep 5
done
echo
kubectl wait --for=condition=Ready pod/controlcenter-0 --timeout=600s
echo "Completed"
