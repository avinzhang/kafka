#!/bin/bash

export TAG=7.2.1.arm64

echo "----------Start Openldap---------"
docker-compose up -d --build --no-deps openldap
echo "Done"
echo
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
echo "----------Start zookeeper and broker -------------"
docker-compose up -d --build --no-deps zookeeper1 kafka1 zookeeper2 kafka2
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
docker-compose exec kafka1 bash -c 'cat << EOF > /tmp/client-rbac.properties
sasl.mechanism=OAUTHBEARER
security.protocol=SASL_SSL
ssl.truststore.location=/etc/kafka/secrets/client.truststore.jks
ssl.truststore.password=confluent
sasl.login.callback.handler.class=io.confluent.kafka.clients.plugins.auth.token.TokenUserLoginCallbackHandler
sasl.jaas.config=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username="user1" password="user1" metadataServerUrls="https://kafka1:1090";
EOF'
echo
echo "Setup config for mTls port"
docker-compose exec kafka1 bash -c 'cat << EOF > /tmp/client-ssl.properties
security.protocol=SSL
ssl.keystore.location=/etc/kafka/secrets/client.keystore.jks
ssl.keystore.password=confluent
ssl.truststore.location=/etc/kafka/secrets/client.truststore.jks
ssl.truststore.password=confluent
ssl.key.password=confluent
EOF'
echo
echo "Create rolebinding for user1 and user2 on source topic test on cluster 1"
confluent iam rbac role-binding create --kafka-cluster-id $KAFKA_CLUSTER_ID --principal User:user1 --resource Topic:test --role ResourceOwner
confluent iam rbac role-binding create --kafka-cluster-id $KAFKA_CLUSTER_ID --principal User:user2 --resource Topic:test --role ResourceOwner

echo 
MDS_STARTED=false
while [ $MDS_STARTED == false ]
do
    docker-compose logs kafka2 | grep "Started NetworkTrafficServerConnector" &> /dev/null
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
docker-compose exec kafka2 bash -c 'cat << EOF > /tmp/client-rbac-cluster2.properties
bootstrap.servers=kafka2:2093
sasl.mechanism=OAUTHBEARER
security.protocol=SASL_SSL
ssl.truststore.location=/etc/kafka/secrets/client.truststore.jks
ssl.truststore.password=confluent
sasl.login.callback.handler.class=io.confluent.kafka.clients.plugins.auth.token.TokenUserLoginCallbackHandler
sasl.jaas.config=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username="user2" password="user2" metadataServerUrls="https://kafka2:2090";
EOF'
echo
docker-compose exec kafka2 bash -c 'cat << EOF > /tmp/client-rbac-cluster1.properties
bootstrap.servers=kafka1:1093
sasl.mechanism=OAUTHBEARER
security.protocol=SASL_SSL
ssl.truststore.location=/etc/kafka/secrets/client.truststore.jks
ssl.truststore.password=confluent
sasl.login.callback.handler.class=io.confluent.kafka.clients.plugins.auth.token.TokenUserLoginCallbackHandler
sasl.jaas.config=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username="user2" password="user2" metadataServerUrls="https://kafka1:1090";
EOF'
echo "Create role binding for user2 on cluster2 on topic test"
confluent iam rbac role-binding create --kafka-cluster-id $KAFKA_CLUSTER_ID --principal User:user2 --resource Topic:test --role ResourceOwner
confluent iam rbac role-binding create --kafka-cluster-id $KAFKA_CLUSTER_ID --principal User:user2 --resource Group:mygroup --role ResourceOwner
confluent iam rbac role-binding create --kafka-cluster-id $KAFKA_CLUSTER_ID --principal User:user2 --role ClusterAdmin

echo "Create cluster link from kafka1 to kafka2"
docker-compose exec kafka2 kafka-cluster-links --bootstrap-server kafka2:2093 --command-config /tmp/client-rbac-cluster2.properties --create --link kafka-cluster-link --config-file /tmp/client-rbac-cluster1.properties
echo
echo "Create test topic on kafka1"
docker-compose exec kafka1 kafka-topics  --create --bootstrap-server kafka1:1093 --topic test --partitions 1 --replication-factor 1 --command-config /tmp/client-rbac.properties
echo "Create an mirror of test topic on kafka2"
docker-compose exec kafka2 kafka-mirrors --create --bootstrap-server kafka2:2093 --command-config /tmp/client-rbac-cluster2.properties --mirror-topic test --link kafka-cluster-link --replication-factor 1

echo
echo "Produce some messages on kafka1"
docker-compose exec kafka1 bash -c "seq 10 | kafka-console-producer --producer.config /tmp/client-rbac.properties --request-required-acks 1 --broker-list kafka1:1093 --topic test && echo 'Produced 10 messages.'"
echo
echo "Consume messages on kafka2"
docker-compose exec kafka2 bash -c "kafka-console-consumer --bootstrap-server kafka2:2093 --consumer.config /tmp/client-rbac-cluster2.properties --group mygroup --topic test --from-beginning --timeout-ms 10000"
exit
echo "---Setup role binding for c3Admin user for C3"
confluent iam rolebinding create --principal User:controlcenter --role SystemAdmin --kafka-cluster-id $KAFKA_CLUSTER_ID

echo "Done"
echo
echo ">> start C3"
docker-compose up -d --build --no-deps controlcenter
echo

echo ">> Add role binding for c3User -- c3User is Kafka ldap group"
echo "   (all Operator role)"
echo "   * Permission for Kafka cluster"
confluent iam rolebinding create --kafka-cluster-id $KAFKA_CLUSTER_ID --principal Group:kafka --role ClusterAdmin
confluent iam rolebinding create --kafka-cluster-id $KAFKA_CLUSTER_ID --principal Group:kafka --role SystemAdmin
