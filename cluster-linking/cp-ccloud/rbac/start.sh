#!/bin/bash

export TAG=7.1.1.arm64

echo "----------Start zookeeper" 
docker-compose up -d --build --no-deps zookeeper1 zookeeper2 zookeeper3 
echo
echo
echo "----------Start Openldap---------"
docker-compose up -d --build --no-deps openldap
STARTED=false
while [ $STARTED == false ]
do
    docker-compose logs openldap | grep "started" &> /dev/null
    if [ $? -eq 0 ]; then
      STARTED=true
      echo "Openldap is started and ready"
    else
      echo "Waiting for Openldap to start..."
    fi
    sleep 5
done
echo
echo
echo "-----------Start brokers"
docker-compose up -d --build --no-deps kafka1 kafka2 kafka3
echo "Done"
echo
echo
MDS_STARTED=false
while [ $MDS_STARTED == false ]
do
    docker-compose logs kafka1 | grep "Started NetworkTrafficServerConnector" &> /dev/null
    if [ $? -eq 0 ]; then
      MDS_STARTED=true
      echo "MDS is started and ready"
    else
      echo "Waiting for MDS to start..."
    fi
    sleep 5
done
echo
OUTPUT=$(
  expect <<END
    log_user 1
    spawn confluent login --url https://localhost:1090 --ca-cert-path ./secrets/ca.crt
    expect "Username: "
    send "mds\r";
    expect "Password: "
    send "mds\r";
    expect "Logged in as "
    set result $expect_out(buffer)
END
)

KAFKA_CLUSTER_ID=`curl -sik https://localhost:1090/v1/metadata/id |grep id |jq -r ".id"`
if [ -z "$KAFKA_CLUSTER_ID" ]; then
    echo "Failed to retrieve kafka cluster id from MDS"
    exit 1
fi
echo "****Cluster ID is $KAFKA_CLUSTER_ID"
echo
echo ">>>Check metadata API endpoint"
curl -k -u mds:mds https://localhost:1090/security/1.0/authenticate
echo
echo ">>>Setup config file for token port"
docker-compose exec kafka1 bash -c 'cat << EOF > /tmp/client-rbac.properties
sasl.mechanism=OAUTHBEARER
security.protocol=SASL_SSL
ssl.truststore.location=/etc/kafka/secrets/user1.truststore.jks
ssl.truststore.password=confluent
sasl.login.callback.handler.class=io.confluent.kafka.clients.plugins.auth.token.TokenUserLoginCallbackHandler
sasl.jaas.config=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username="user1" password="user1" metadataServerUrls="https://kafka1:1090";
EOF'
echo
echo 
echo "---- Setup Rest Proxy ---"
confluent iam rbac role-binding create --principal User:restproxy --role DeveloperRead --resource Topic:_confluent-command --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rbac role-binding create --principal User:restproxy --role DeveloperWrite --resource Topic:_confluent-command --kafka-cluster-id $KAFKA_CLUSTER_ID
echo

echo
echo "----Setup Schema Registry ----"
echo
echo ">> Adding role binding for user schemaregistry"
confluent iam rbac role-binding create \
    --principal User:schemaregistry \
    --role SecurityAdmin \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --schema-registry-cluster-id schema-registry

confluent iam rbac role-binding create \
    --principal User:schemaregistry \
    --role ClusterAdmin \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

for resource in Topic:_schemas Topic:_confluent-command Topic:_confluent-license Group:schema-registry
do
    confluent iam rbac role-binding create \
        --principal User:schemaregistry \
        --role ResourceOwner \
        --resource $resource \
        --kafka-cluster-id $KAFKA_CLUSTER_ID
done
echo
echo ">> Starting up schema registry"
docker-compose up -d --build --no-deps schemaregistry &>/dev/null
echo
echo
echo "-------------------------------------------------------------------"
echo
echo
echo "----Setup Kafka Connect------------"
echo
echo ">> Download datagen connector"
mkdir -p ./jar/datagen
ls ./jar/datagen/confluentinc-kafka-connect-datagen/lib/kafka-connect-datagen-*.jar || confluent-hub install  --component-dir ./jar/datagen confluentinc/kafka-connect-datagen:latest --no-prompt
echo "Done"
echo ">> Download replicator connector"
ls ./jar/confluentinc-kafka-connect-replicator/lib/replicator-rest-extension-*.jar || confluent-hub install --no-prompt --component-dir ./jar confluentinc/kafka-connect-replicator:latest
echo
echo ">> Adding role binding for connectAdmin"
confluent iam rbac role-binding create --principal User:connectAdmin --role SecurityAdmin --kafka-cluster-id $KAFKA_CLUSTER_ID --connect-cluster-id connect-cluster
# ResourceOwner for groups and topics on broker
declare -a ConnectResources=(
    "Topic:connect-configs"
    "Topic:connect-offsets"
    "Topic:connect-status"
    "Group:connect-cluster"
    "Topic:_confluent-monitoring"
    "Topic:_confluent-secrets"
    "Topic:_confluent-command"
    "Group:secret-registry"
)
for resource in ${ConnectResources[@]}
do
    confluent iam rbac role-binding create \
        --principal User:connectAdmin \
        --role ResourceOwner \
        --resource $resource \
        --kafka-cluster-id $KAFKA_CLUSTER_ID
done

echo
echo
echo ">> Starting up Kafka connect"
docker-compose up -d --build --no-deps connect
echo
echo
CONNECT_STARTED=false
while [ $CONNECT_STARTED == false ]
do
    docker-compose logs connect | grep "Herder started" &> /dev/null
    if [ $? -eq 0 ]; then
      CONNECT_STARTED=true
      echo "Kafka connect is started and ready"
    else
      echo "Waiting for Kafka Connect..."
    fi
    sleep 5
done

echo ">> Add role binding for connectUser for managing connectors"
confluent iam rbac role-binding create --principal User:connectUser --role ResourceOwner --resource Connector:datagen-users --kafka-cluster-id $KAFKA_CLUSTER_ID --connect-cluster-id connect-cluster
confluent iam rbac role-binding create --principal User:connectUser --role ResourceOwner --resource Connector:datagen-pageviews --kafka-cluster-id $KAFKA_CLUSTER_ID --connect-cluster-id connect-cluster

#Idempotent producers require cluster write
confluent iam rbac role-binding create --principal User:connectUser --role DeveloperWrite --resource Cluster:kafka-cluster --kafka-cluster-id $KAFKA_CLUSTER_ID

#confluent iam rbac role-binding create --principal User:connectUser --role ResourceOwner --resource Group:connect-datagen-users --kafka-cluster-id $KAFKA_CLUSTER_ID
#confluent iam rbac role-binding create --principal User:connectUser --role ResourceOwner --resource Group:connect-datagen-pageviews --kafka-cluster-id $KAFKA_CLUSTER_ID
#for connector to access topic, subject
confluent iam rbac role-binding create --principal User:connectUser --role ResourceOwner --resource Topic:users --kafka-cluster-id $KAFKA_CLUSTER_ID --prefix
confluent iam rbac role-binding create --principal User:connectUser --role ResourceOwner --resource Topic:pageviews --kafka-cluster-id $KAFKA_CLUSTER_ID --prefix
confluent iam rbac role-binding create --principal User:connectUser --role ResourceOwner --resource Subject:users --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id schema-registry --prefix
confluent iam rbac role-binding create --principal User:connectUser --role ResourceOwner --resource Subject:pageviews --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id schema-registry --prefix


# User to check all connector status
#confluent iam rbac role-binding create --principal User:connectorViewer --role ResourceOwner --resource 'Connector:*' --kafka-cluster-id $KAFKA_CLUSTER_ID --connect-cluster-id connect-cluster
#confluent iam rbac role-binding create --principal User:connectorViewer --role ResourceOwner --resource 'Topic:*' --kafka-cluster-id $KAFKA_CLUSTER_ID --prefix
#confluent iam rbac role-binding create --principal User:connectorViewer --role ResourceOwner --resource 'Subject:*' --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id schema-registry

echo
echo

echo ">> Add connector: datagen-users"
curl -i -X POST \
    --cacert ./secrets/ca.crt \
    -u connectUser:connectUser \
    -H "Accept:application/json" \
    -H  "Content-Type:application/json" \
   https://localhost:8083/connectors/ -d '
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
           "value.converter.schema.registry.url": "https://schemaregistry:8081",
           "value.converter.schema.registry.ssl.truststore.location": "/etc/kafka/secrets/connect.truststore.jks",
           "value.converter.schema.registry.ssl.truststore.password": "confluent",
           "value.converter.basic.auth.credentials.source": "USER_INFO",
           "value.converter.basic.auth.user.info": "connectUser:connectUser",
           "tasks.max": "1",
           "iterations": "1000000000",
           "producer.override.sasl.jaas.config": "org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username=\"connectUser\" password=\"connectUser\" metadataServerUrls=\"https://kafka1:1090\";"
       }
   }'
echo
echo ">> Check connector status"
echo "Datagen-users: `curl -s --cacert ./secrets/ca.crt -u connectUser:connectUser https://localhost:8083/connectors/datagen-users/status`"
echo
echo
echo ">> Add connector: datagen-pageviews"
curl -i -X POST \
    --cacert ./secrets/ca.crt \
    --cert ./secrets/connect.certificate.pem --key ./secrets/connect.key \
    -u connectUser:connectUser \
    -H "Accept:application/json" \
    -H  "Content-Type:application/json" \
   https://localhost:8083/connectors/ -d '
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
           "value.converter.schema.registry.url": "https://schemaregistry:8081",
           "value.converter.schema.registry.ssl.truststore.location": "/etc/kafka/secrets/connect.truststore.jks",
           "value.converter.schema.registry.ssl.truststore.password": "confluent",
           "value.converter.basic.auth.credentials.source": "USER_INFO",
           "value.converter.basic.auth.user.info": "connectUser:connectUser",
           "tasks.max": "1",
           "iterations": "1000000000",
           "producer.override.sasl.jaas.config": "org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username=\"connectUser\" password=\"connectUser\" metadataServerUrls=\"https://kafka1:1090\";"
       }
   }'

echo
echo ">> Check connector status"
echo "Datagen-pageviews: `curl -s --cacert ./secrets/ca.crt -u connectUser:connectUser https://localhost:8083/connectors/datagen-pageviews/status`"
echo
echo
echo "Login Confluent Cloud"
confluent login --save
echo ">> Set cloud environment"
export CLOUD_ENV=`confluent environment list -ojson | jq -r '.[]|select(.name == "avin").id'`
confluent environment use $CLOUD_ENV
echo
echo ">> Set cloud cluster ID "
confluent kafka cluster use `terraform -chdir=./cloud output -json | jq -r '."cloud-cluster-id"."value"'`
echo
echo ">> Get cluster link api key"
export CL_API_KEY=`terraform -chdir=../cloud output -json | jq -r '."cluster-link-api-key"."value"'`
export CL_API_SECRET=`terraform -chdir=../cloud output -json | jq -r '."cluster-link-api-secret"."value"'`

echo
echo
echo ">> Create config file for cluster link on cloud cluster"
cat << EOF > /tmp/cluterlink-dst.config
link.mode=DESTINATION
connection.mode=INBOUND
auto.create.mirror.topics.enable=true
auto.create.mirror.topics.filters={ "topicFilters": [ {"name": "user",  "patternType": "PREFIXED",  "filterType": "INCLUDE"} ] }
EOF
echo
export CLOUD_CLUSTER_ID=`terraform -chdir=../cloud output -json | jq -r '."cloud-cluster-id"."value"'`
export CP_CLUSTER_ID=`curl -sk  https://localhost:1090/v1/metadata/id  | grep id |jq -r ".id"`
echo "Create cluster link on Cloud cluster"
confluent kafka link create from-on-prem-link --cluster $CLOUD_CLUSTER_ID --source-cluster-id $CP_CLUSTER_ID --config-file /tmp/cluterlink-dst.config
echo
echo ">> List link on cloud"
confluent kafka link list --cluster $CLOUD_CLUSTER_ID
confluent kafka link describe from-on-prem-link 
echo
echo
echo
echo ">> Create CP source config"
export CLOUD_ENDPOINT=`terraform -chdir=../cloud output -json | jq -r '".cloud-cluster-endpoint"."value"'`
docker-compose exec kafka1 bash -c "cat <<EOF > /tmp/clusterlink-cp-src.config
link.mode=SOURCE
connection.mode=OUTBOUND

bootstrap.servers=$CLOUD_ENDPOINT
ssl.endpoint.identification.algorithm=https
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username='$CL_API_KEY' password='$CL_API_SECRET';

local.listener.name=TOKEN
local.security.protocol=SASL_SSL
local.sasl.mechanism=OAUTHBEARER
local.ssl.truststore.location=/etc/kafka/secrets/user1.truststore.jks
local.ssl.truststore.password=confluent
local.sasl.login.callback.handler.class=io.confluent.kafka.clients.plugins.auth.token.TokenUserLoginCallbackHandler
local.sasl.jaas.config=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username='user1' password='user1' metadataServerUrls='https://kafka1:1090';
EOF"
echo
echo
confluent logout
cat << EOF > ~/.netrc
machine confluent-cli:mds-username-password:login-mds-https://localhost:1090?cacertpath=./secrets/ca.crt
  login mds
  password mds
EOF
confluent login --url https://localhost:1090 --ca-cert-path ./secrets/ca.crt --save
echo ">>Add permission for user1 user on source cluster"
confluent iam rbac role-binding create --principal User:user1 --role DeveloperRead --resource Topic:users --prefix --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rbac role-binding create --principal User:user1 --role DeveloperRead --resource Subject:users --prefix --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id schema-registry
confluent iam rbac role-binding create --principal User:user1 --role DeveloperManage --resource Topic:users --prefix --kafka-cluster-id $KAFKA_CLUSTER_ID 
#Sync consumer offsets
confluent iam rbac role-binding create --principal User:user1 --role DeveloperManage --resource Topic:users --prefix --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rbac role-binding create --kafka-cluster-id $KAFKA_CLUSTER_ID --principal User:user1 --role ClusterAdmin

echo ">>Create link on source cluster"
docker-compose exec kafka1 bash -c "kafka-cluster-links --bootstrap-server kafka1:1093,kafka2:2093,kafka3:3093 --create --link from-on-prem-link --config-file /tmp/clusterlink-cp-src.config --cluster-id $CLOUD_CLUSTER_ID --command-config /tmp/client-rbac.properties"
echo
echo ">>Link link on source cluster"
docker-compose exec kafka1 bash -c "kafka-cluster-links --list --bootstrap-server kafka1:1093 --command-config /tmp/client-rbac.properties"
echo

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
