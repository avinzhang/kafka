#!/bin/bash

export TAG=7.0.1

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
echo "----------Start zookeeper and broker -------------"
docker-compose up -d --build --no-deps zookeeper1 kafka1 
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
ssl.truststore.location=/etc/kafka/secrets/client.truststore.jks
ssl.truststore.password=confluent
sasl.login.callback.handler.class=io.confluent.kafka.clients.plugins.auth.token.TokenUserLoginCallbackHandler
sasl.jaas.config=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username="user1" password="user1" metadataServerUrls="https://kafka1:1090";
EOF'
echo
echo ">>>Setup config for mTls port"
docker-compose exec kafka1 bash -c 'cat << EOF > /tmp/client-ssl.properties
security.protocol=SSL
ssl.keystore.location=/etc/kafka/secrets/client.keystore.jks
ssl.keystore.password=confluent
ssl.truststore.location=/etc/kafka/secrets/client.truststore.jks
ssl.truststore.password=confluent
ssl.key.password=confluent
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
echo "-----setup Rest Proxy"
for role in DeveloperRead DeveloperWrite
do
    confluent iam rbac role-binding create --principal User:restproxy --role $role --resource Topic:_confluent-license --kafka-cluster-id $KAFKA_CLUSTER_ID
done

docker-compose up -d --build --no-deps restproxy &>/dev/null
echo
echo ">> Grant role permission to user1 for viewing topics"
confluent iam rbac role-binding create --principal User:user1 --role ResourceOwner --resource Topic:test --kafka-cluster-id $KAFKA_CLUSTER_ID 
confluent iam rbac role-binding create --principal User:user1 --role ResourceOwner --resource Topic:_confluent-command --kafka-cluster-id $KAFKA_CLUSTER_ID 
echo
echo ">> verify permission"
curl -v --cacert ./secrets/ca.crt -u user1:user1 -X POST \
     -H "Content-Type: application/json" \
     -d "{\"topic_name\":\"test\",\"partitions_count\":1,\"replication_factor\":1,\"configs\":[]}" \
     "https://localhost:8082/v3/clusters/${KAFKA_CLUSTER_ID}/topics" 

