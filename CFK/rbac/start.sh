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
echo "INSTALL LDAP SERVER-------"
helm upgrade --install openldap stable/openldap -f ./openldap.yaml
echo "done"
echo
echo "---------------------------------------"
echo "Setup various secrets" 
echo 
echo ">>Create SSL secrets"
# For auto generated SSL certs only
#echo "Generate SSL CA"
#openssl genrsa -out /tmp/ca-key.pem 2048
#openssl req -new -key /tmp/ca-key.pem -x509 -days 1000 -out /tmp/ca.pem -subj '/CN=ca.cse.example.com/OU=CSE/O=CONFLUENT/L=MountainView/ST=Ca/C=US'

#echo "Add CA as a secret"
#kubectl -n confluent create secret tls ca-pair-sslcerts \
#  --cert=/tmp/ca.pem \
#  --key=/tmp/ca-key.pem

# To use your own SSL certs
echo "Setup TLS secrets for each component"
for i in zookeeper kafka connect schemaregistry ksql controlcenter
  do
    echo ">>>>>Creating secret tls-$i"
    kubectl create secret generic tls-$i \
    --from-file=fullchain.pem=../certs/$i-ca1-signed.crt \
    --from-file=cacerts.pem=../certs/ca.crt \
       --from-file=privkey.pem=../certs/$i.key
done

echo
echo
echo ">>Setup secrets for sasl users"
kubectl create secret generic credential \
 --from-file=plain-users.json=./secrets/creds-kafka-sasl-users.json \
 --from-file=digest-users.json=./secrets/creds-zookeeper-sasl-digest-users.json \
 --from-file=digest.txt=./secrets/creds-kafka-zookeeper-credentials.txt \
 --from-file=plain.txt=./secrets/creds-client-kafka-sasl-user.txt \
 --from-file=basic.txt=./secrets/creds-control-center-users.txt \
 --from-file=ldap.txt=./secrets/ldap.txt -n confluent
echo "Done"
echo 
echo ">>Setup secret for MDS token"
kubectl create secret generic mds-token \
  --from-file=mdsPublicKey.pem=./secrets/mds-publickey.txt \
  --from-file=mdsTokenKeyPair.pem=./secrets/mds-tokenkeypair.txt
echo "Done"
echo 
echo ">>setup oauth credential for each component"
kubectl create secret generic mds-client \
  --from-file=bearer.txt=./secrets/bearer.txt
kubectl create secret generic c3-mds-client \
  --from-file=bearer.txt=./secrets/c3-mds-client.txt
kubectl create secret generic connect-mds-client \
  --from-file=bearer.txt=./secrets/connect-mds-client.txt
kubectl create secret generic sr-mds-client \
  --from-file=bearer.txt=./secrets/sr-mds-client.txt
kubectl create secret generic ksqldb-mds-client \
  --from-file=bearer.txt=./secrets/ksqldb-mds-client.txt
kubectl create secret generic rest-credential \
  --from-file=bearer.txt=./secrets/bearer.txt \
  --from-file=basic.txt=./secrets/bearer.txt
echo "Done"

# Updated secrets
#kubectl -n confluent create secret generic mds-client --save-config --dry-run=client \
#  --from-file=bearer.txt=./bearer.txt -oyaml | kubectl apply -f -
#kubectl -n confluent create secret generic c3-mds-client --save-config --dry-run=client \
#  --from-file=bearer.txt=./c3-mds-client.txt -oyaml | kubectl apply -f -
#kubectl -n confluent create secret generic connect-mds-client --save-config --dry-run=client \
#  --from-file=bearer.txt=./connect-mds-client.txt -oyaml | kubectl apply -f -
#kubectl -n confluent create secret generic sr-mds-client --save-config --dry-run=client \
#  --from-file=bearer.txt=./sr-mds-client.txt -oyaml | kubectl apply -f -
#kubectl -n confluent create secret generic ksqldb-mds-client --save-config --dry-run=client \
#  --from-file=bearer.txt=./ksqldb-mds-client.txt -oyaml | kubectl apply -f -
#kubectl -n confluent create secret generic rest-credential --save-config --dry-run=client \
#  --from-file=bearer.txt=./bearer.txt \
#  --from-file=basic.txt=./bearer.txt -oyaml | kubectl apply -f -

echo 
echo
echo "-----------------------------------------"
echo "Install zookeeper"
envsubst < ./zookeeper.yaml | kubectl apply -f -
sleep 20
echo "Wait for zookeeper pods"
kubectl wait --for=condition=Ready pod/zookeeper-0 --timeout=300s
kubectl wait --for=condition=Ready pod/zookeeper-1 --timeout=300s
kubectl wait --for=condition=Ready pod/zookeeper-2 --timeout=300s
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
echo ">>Adding client-rbac.properties to kafka-0 pod"
kubectl exec -it kafka-0 -- bash -c 'cat << EOF > /tmp/client-rbac.properties
sasl.mechanism=OAUTHBEARER
security.protocol=SASL_SSL
ssl.truststore.location=/mnt/sslcerts/truststore.p12
ssl.truststore.password=mystorepassword
sasl.login.callback.handler.class=io.confluent.kafka.clients.plugins.auth.token.TokenUserLoginCallbackHandler
sasl.jaas.config=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username="kafka" password="kafka" metadataServerUrls="https://kafka:8090";
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
echo "Create datagen-users connector"
kubectl exec -it connect-0 -- curl --cacert /mnt/sslcerts/cacerts.pem -u connectuser:connectuser -X POST -H "Content-Type: application/json" https://localhost:8083/connectors/ \
-d '{"name": "datagen-users",
     "config": {
       "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
       "quickstart": "users",
       "name": "datagen-users",
       "kafka.topic": "users",
       "max.interval": "1000",
       "key.converter": "io.confluent.connect.avro.AvroConverter",
       "value.converter": "io.confluent.connect.avro.AvroConverter",
       "tasks.max": "1",
       "iterations": "1000000000",
       "key.converter.schema.registry.url": "https://schemaregistry:8081",
       "key.converter.schema.registry.ssl.truststore.location": "/mnt/sslcerts/truststore.p12",
       "key.converter.schema.registry.ssl.truststore.password": "mystorepassword",
       "key.converter.basic.auth.credentials.source": "USER_INFO",
       "key.converter.basic.auth.user.info": "connectuser:connectuser",
       "value.converter.schema.registry.url": "https://schemaregistry:8081",
       "value.converter.schema.registry.ssl.truststore.location": "/mnt/sslcerts/truststore.p12",
       "value.converter.schema.registry.ssl.truststore.password": "mystorepassword",
       "value.converter.basic.auth.credentials.source": "USER_INFO",
       "value.converter.basic.auth.user.info": "connectuser:connectuser",
       "producer.override.sasl.jaas.config": "org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username=\"connectuser\" password=\"connectuser\" metadataServerUrls=\"https://kafka:8090\";"
       }
  }'
echo "Done"

echo "Creat datagen-pageviews connector"
kubectl exec -it connect-0 -- curl --cacert /mnt/sslcerts/cacerts.pem -u connectuser:connectuser -X POST -H "Content-Type: application/json" https://localhost:8083/connectors/ \
-d '{"name": "datagen-pageviews",
     "config": {
       "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
       "quickstart": "pageviews",
       "name": "datagen-pageviews",
       "kafka.topic": "pageviews",
       "max.interval": "1000",
       "key.converter": "io.confluent.connect.avro.AvroConverter",
       "key.converter.schema.registry.url": "https://schemaregistry:8081",
       "key.converter.schema.registry.ssl.truststore.location": "/mnt/sslcerts/truststore.p12",
       "key.converter.schema.registry.ssl.truststore.password": "mystorepassword",
       "key.converter.basic.auth.credentials.source": "USER_INFO",
       "key.converter.basic.auth.user.info": "connectuser:connectuser",
       "value.converter": "io.confluent.connect.avro.AvroConverter",
       "value.converter.schema.registry.url": "https://schemaregistry:8081",
       "value.converter.schema.registry.ssl.truststore.location": "/mnt/sslcerts/truststore.p12",
       "value.converter.schema.registry.ssl.truststore.password": "mystorepassword",
       "value.converter.basic.auth.credentials.source": "USER_INFO",
       "value.converter.basic.auth.user.info": "connectuser:connectuser",
       "tasks.max": "1",
       "iterations": "1000000000",
       "producer.override.sasl.jaas.config": "org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username=\"connectuser\" password=\"connectuser\" metadataServerUrls=\"https://kafka:8090\";"
       }
    }'
echo "Done"
echo 
echo "------------------------------------------"
echo "Install ksqldb"
envsubst < ./ksqldb.yaml | kubectl apply -f -
echo 
ksqldb_pod_created=false
while [ $ksqldb_pod_created == false ]
do
    kubectl get po ksqldb-0 &> /dev/null
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
kubectl exec -it  ksqldb-0 --  bash -c "ksql --config-file /tmp/client-ssl.properties -u ksqluser -p ksqluser https://localhost:8088 <<EOF
SET 'auto.offset.reset'='earliest';
SET 'ksql.schema.registry.url'='https://schemaregistry:8081';
CREATE STREAM pageviews (viewtime BIGINT, userid VARCHAR, pageid VARCHAR) WITH (KAFKA_TOPIC='pageviews', REPLICAS=3, VALUE_FORMAT='AVRO');
CREATE TABLE users (userid VARCHAR PRIMARY KEY, registertime BIGINT, gender VARCHAR, regionid VARCHAR) WITH (KAFKA_TOPIC='users', VALUE_FORMAT='AVRO');
CREATE STREAM pageviews_female with (KAFKA_TOPIC='pageviews_female', REPLICAS=3) AS SELECT users.userid AS userid, pageid, regionid, gender FROM pageviews LEFT JOIN users ON pageviews.userid = users.userid WHERE gender = 'FEMALE';
CREATE STREAM pageviews_female_like_89 WITH (kafka_topic='pageviews_enriched_r8_r9', value_format='AVRO') AS SELECT * FROM pageviews_female WHERE regionid LIKE '%_8' OR regionid LIKE '%_9';
CREATE TABLE pageviews_regions with (kafka_topic='pageviews_regions', key_format='json') AS SELECT gender, regionid , COUNT(*) AS numusers FROM pageviews_female WINDOW TUMBLING (size 30 second) GROUP BY gender, regionid HAVING COUNT(*) > 1;
exit ;
EOF"
echo
echo "------------------------------------------"
echo "Install Control Center"
envsubst < ./controlcenter.yaml | kubectl apply -f -
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
