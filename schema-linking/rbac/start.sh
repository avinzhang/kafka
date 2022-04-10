#!/bin/bash

export TAG=7.1.0

echo "----------Start Openldap---------"
docker compose up -d --build --no-deps openldap
echo "Done"
echo
STARTED=false
while [ $STARTED == false ]
do
    docker compose logs openldap | grep "started" &> /dev/null
    if [ $? -eq 0 ]; then
      STARTED=true
      echo "Openldap is started and ready"
    else
      echo "Waiting for Openldap to start..."
    fi
    sleep 5
done
echo
echo "----------Start zookeeper and broker -------------"
docker compose up -d --build --no-deps zookeeper1 kafka1 zookeeper2 kafka2 
echo "Done"
echo
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
echo "Cluster ID is $KAFKA_CLUSTER_ID"
echo
echo "Setup config file for token port"
docker compose exec kafka1 bash -c 'cat << EOF > /tmp/client-rbac.properties
sasl.mechanism=OAUTHBEARER
security.protocol=SASL_SSL
ssl.truststore.location=/etc/kafka/secrets/client.truststore.jks
ssl.truststore.password=confluent
sasl.login.callback.handler.class=io.confluent.kafka.clients.plugins.auth.token.TokenUserLoginCallbackHandler
sasl.jaas.config=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username="user1" password="user1" metadataServerUrls="https://kafka1:1090";
EOF'
echo
echo "Setup config for mTls port"
docker compose exec kafka1 bash -c 'cat << EOF > /tmp/client-ssl.properties
security.protocol=SSL
ssl.keystore.location=/etc/kafka/secrets/client.keystore.jks
ssl.keystore.password=confluent
ssl.truststore.location=/etc/kafka/secrets/client.truststore.jks
ssl.truststore.password=confluent
ssl.key.password=confluent
EOF'
echo
echo "----Setup Schema Registry1 ----"
echo
echo ">> Adding role binding for user schemaregistry1"
confluent iam rbac role-binding create \
    --principal User:schemaregistry1 \
    --role SecurityAdmin \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --schema-registry-cluster-id schema-registry

confluent iam rbac role-binding create \
    --principal User:schemaregistry1 \
    --role ClusterAdmin \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

for resource in Topic:_schemas Topic:_confluent-command Topic:_confluent-license Topic:_exporter_configs Topic:_exporter_states Group:schema-registry
do
    confluent iam rbac role-binding create \
        --principal User:schemaregistry1 \
        --role ResourceOwner \
        --resource $resource \
        --kafka-cluster-id $KAFKA_CLUSTER_ID
done
echo
echo ">> Starting up schema registry"
docker compose up -d --build --no-deps schemaregistry1 &>/dev/null
echo
echo
STARTED=false
while [ $STARTED == false ]
do
    docker compose logs schemaregistry1 | grep "Server started" &> /dev/null
    if [ $? -eq 0 ]; then
      STARTED=true
      echo "SR1 is started and ready"
    else
      echo "Waiting for SR1 to start..."
    fi
    sleep 5
done

echo "Create rolebinding for user1 for schema registry 1"
confluent iam rbac role-binding create --principal User:user1 --role ResourceOwner --resource 'Subject:*' --schema-registry-cluster-id schema-registry --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rbac role-binding create --principal User:user1 --role ResourceOwner --resource Topic:_exporter_configs --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rbac role-binding create --principal User:user1 --role ResourceOwner --resource Topic:_exporter_states --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rbac role-binding create --principal User:user1 --role ResourceOwner --resource Topic:__consumer_offsets --kafka-cluster-id $KAFKA_CLUSTER_ID

echo 
MDS_STARTED=false
while [ $MDS_STARTED == false ]
do
    docker compose logs kafka2 | grep "Started NetworkTrafficServerConnector" &> /dev/null
    if [ $? -eq 0 ]; then
      MDS_STARTED=true
      echo "MDS is started and ready"
    else
      echo "Waiting for MDS to start..."
    fi
    sleep 5
done


OUTPUT=$(
  expect <<END
    log_user 1
    spawn confluent login --url https://localhost:2090 --ca-cert-path ./secrets/ca.crt
    expect "Username: "
    send "mds\r";
    expect "Password: "
    send "mds\r";
    expect "Logged in as "
    set result $expect_out(buffer)
END
)

KAFKA_CLUSTER_ID=`curl -sik https://localhost:2090/v1/metadata/id |grep id |jq -r ".id"`
if [ -z "$KAFKA_CLUSTER_ID" ]; then
    echo "Failed to retrieve kafka cluster id from MDS"
    exit 1
fi
echo "Cluster ID is $KAFKA_CLUSTER_ID"
echo
echo "Setup config file for token port"
docker compose exec kafka2 bash -c 'cat << EOF > /tmp/client-rbac-cluster2.properties
bootstrap.servers=kafka2:2093
sasl.mechanism=OAUTHBEARER
security.protocol=SASL_SSL
ssl.truststore.location=/etc/kafka/secrets/client.truststore.jks
ssl.truststore.password=confluent
sasl.login.callback.handler.class=io.confluent.kafka.clients.plugins.auth.token.TokenUserLoginCallbackHandler
sasl.jaas.config=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username="user2" password="user2" metadataServerUrls="https://kafka2:2090";
EOF'
echo
docker compose exec kafka2 bash -c 'cat << EOF > /tmp/client-rbac-cluster1.properties
bootstrap.servers=kafka1:1093
sasl.mechanism=OAUTHBEARER
security.protocol=SASL_SSL
ssl.truststore.location=/etc/kafka/secrets/client.truststore.jks
ssl.truststore.password=confluent
sasl.login.callback.handler.class=io.confluent.kafka.clients.plugins.auth.token.TokenUserLoginCallbackHandler
sasl.jaas.config=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username="user2" password="user2" metadataServerUrls="https://kafka1:1090";
EOF'
echo
echo
echo "----Setup Schema Registry2 ----"
echo
echo ">> Adding role binding for user schemaregistry"
confluent iam rbac role-binding create \
    --principal User:schemaregistry2 \
    --role SecurityAdmin \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --schema-registry-cluster-id schema-registry

confluent iam rbac role-binding create \
    --principal User:schemaregistry2 \
    --role ClusterAdmin \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

for resource in Topic:_schemas Topic:_confluent-command Topic:_confluent-license Topic:_exporter_configs Topic:_exporter_states Topic:__consumer_offsets Group:schema-registry
do
    confluent iam rbac role-binding create \
        --principal User:schemaregistry2 \
        --role ResourceOwner \
        --resource $resource \
        --kafka-cluster-id $KAFKA_CLUSTER_ID
done
echo
echo ">> Starting up schema registry"
docker compose up -d --build --no-deps schemaregistry2 &>/dev/null
echo
STARTED=false
while [ $STARTED == false ]
do
    docker compose logs schemaregistry2 | grep "Server started" &> /dev/null
    if [ $? -eq 0 ]; then
      STARTED=true
      echo "SR2 is started and ready"
    else
      echo "Waiting for SR2 to start..."
    fi
    sleep 5
done
echo
echo "Create rolebinding for user2 for schema registry 2"
confluent iam rbac role-binding create --principal User:user2 --role ResourceOwner --resource 'Subject:*' --schema-registry-cluster-id schema-registry --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rbac role-binding create --principal User:user2 --role ResourceOwner --resource Topic:_exporter_configs --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rbac role-binding create --principal User:user2 --role ResourceOwner --resource Topic:_exporter_states --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rbac role-binding create --principal User:user2 --role ResourceOwner --resource Topic:__consumer_offsets --kafka-cluster-id $KAFKA_CLUSTER_ID
echo
echo
echo ">>Register schemas on schemaregistry1"
curl -s -u user1:user1 --cacert ./secrets/ca.crt -X POST -H "Content-Type: application/json" --data '{"schema": "{\"type\":\"record\",\"name\":\"Users\",\"fields\":[{\"name\":\"Name\",\"type\":\"string\"},{\"name\":\"Age\",\"type\":\"int\"},{\"name\":\"Phone\",\"type\":\"int\"}]}"}' https://localhost:1081/subjects/:.people:users/versions
echo
echo
echo
cat << EOF > /tmp/test.avro
{
      "schema":
        "{
               \"type\": \"record\",
               \"connect-name\": \"myname\",
               \"connect-donuts\": \"mydonut\",
               \"name\": \"test\",
               \"doc\": \"some doc info\",
                 \"fields\":
                   [
                     {
                       \"type\": \"string\",
                       \"doc\": \"doc for field1\",
                       \"name\": \"field1\"
                     },
                     {
                       \"type\": \"int\",
                       \"doc\": \"doc for field2\",
                       \"name\": \"field2\"
                     }
                   ]
               }"
     }
EOF
curl -s -u user1:user1 --cacert ./secrets/ca.crt -X POST -H "Content-Type: application/json" --data @/tmp/test.avro https://localhost:1081/subjects/donuts/versions
echo
echo ">>Check schema subjects on SR1"
curl --silent -u user1:user1 --cacert ./secrets/ca.crt -X GET https://localhost:1081/subjects?subjectPrefix=":*:" | jq
echo
echo
echo ">> Create configure for exporter"
cat << EOF > /tmp/exporter.txt
{
  "name": "myschemalink",
  "subjects": [":*:"],
  "contextType": "CUSTOM",
  "context": "myschemalink",
  "config": {
    "schema.registry.url": "https://schemaregistry2:2081",
    "schema.registry.ssl.truststore.location": "/etc/kafka/secrets/schemaregistry1.truststore.jks",
    "schema.registry.ssl.trustsotre.password": "confluent",
    "basic.auth.credentials.source": "USER_INFO",
    "basic.auth.user.info": "user2:user2"
  }
}
EOF
echo
echo ">> Post exporter to SR1"
curl -u user1:user1 --cacert ./secrets/ca.crt -H "Content-Type:application/json" -X POST https://localhost:1081/exporters --data @/tmp/exporter.txt


#echo ">>Create config for SR2"
#docker compose exec schemaregistry1 bash -c 'cat << EOF > /tmp/config.txt
#schema.registry.url=https://schemaregistry2:2081
#schema.registry.ssl.truststore.location=/etc/kafka/secrets/schemaregistry1.truststore.jks
#schema.registry.ssl.trustsotre.password=confluent
#basic.auth.credentials.source=USER_INFO
#basic.auth.user.info=user2:user2
#EOF'
#docker compose exec schemaregistry1 bash -c 'SCHEMA_REGISTRY_OPTS="-Djavax.net.ssl.trustStore=/etc/kafka/secrets/client.truststore.jks -Djavax.net.ssl.trustStorePassword=confluent" schema-exporter --create --name myschemalink --subjects ":*:" --schema.registry.url https://schemaregistry1:1081/ --basic.auth.user.info user1:user1 --basic.auth.credentials.source USER_INFO --config-file /tmp/config.txt'
#docker compose exec schemaregistry1 bash -c "schema-exporter --create --name myschemalink --subjects ":*:" --schema.registry.url https://schemaregistry1:1081/ --basic.auth.user.info user1:user1 --basic.auth.credentials.source USER_INFO --config-file /tmp/config.txt"
#SCHEMA_REGISTRY_OPTS="-Djavax.net.ssl.trustStore.location=./secrets/schemaregistry1.truststore.jks -Djavax.net.ssl.trustStore.password=confluent" schema-exporter --create --name myschemalink --subjects ":*:" --schema.registry.url https://localhost:1081/ --basic.auth.user.info user1:user1 --basic.auth.credentials.source USER_INFO --config-file /tmp/config.txt
echo

echo
echo ">>List schema exporter"
curl -u user1:user1 --cacert ./secrets/ca.crt https://localhost:1081/exporters
#docker compose exec schemaregistry1 schema-exporter --list --schema.registry.url https://schemaregistry1:1081 --basic.auth.user.info user1:user1 --basic.auth.credentials.source USER_INFO

sleep 5
echo
echo ">> Check schema subjects on SR2"
curl --silent -u user2:user2 --cacert ./secrets/ca.crt -X GET https://localhost:2081/subjects\?subjectPrefix=":*:" | jq
