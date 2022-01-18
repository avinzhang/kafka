#!/bin/bash

echo ">>Create env"
confluent environment create avin
echo
echo ">>Get env id"
confluent environment list -ojson| jq '.[]|select(.name == "avin")'|jq -r .id
ccloud_env=`confluent environment list -ojson| jq '.[]|select(.name == "avin")'|jq -r .id`

echo ">>Create kafka cluster"
confluent kafka cluster create akafka --type basic --cloud aws --region ap-southeast-2 --environment $ccloud_env

echo ">>Get kafka cluster id"
confluent kafka cluster list -ojson | jq '.[]|select(.name == "akafka")'|jq -r .id
ccloud_kafka_id=`confluent kafka cluster list -ojson | jq '.[]|select(.name == "akafka")'|jq -r .id`

echo ">>Get kafka cluster endpoint"
confluent kafka cluster describe $ccloud_kafka_id -ojson|jq -r .endpoint
ccloud_kafka_endpoint=`confluent kafka cluster describe $ccloud_kafka_id -ojson|jq -r .endpoint`


echo
echo ">>>>Checking if kafka cluster is ready"
ccloud_kafka_status=`confluent kafka cluster describe $ccloud_kafka_id -ojson|jq -r .status`

while [ $ccloud_kafka_status != 'UP' ]
do
  sleep 5
  ccloud_kafka_status=`confluent kafka cluster describe $ccloud_kafka_id -ojson|jq -r .status`
done

echo ">>>Get service account"
ccloud_sa_id=`confluent iam service-account list -ojson|jq '.[]|select(.name == "avin")'| jq -r .id`

echo ">>Create api key on kafka cluster"
confluent api-key create --resource $ccloud_kafka_id --service-account $ccloud_sa_id -ojson > /tmp/kafka_api_key
echo
kafka_api_key=`cat /tmp/kafka_api_key | jq -r .key`
kafka_api_secret=`cat /tmp/kafka_api_key | jq -r .secret`

echo ">>Create ksqldb app"
confluent ksql app create --api-key $kafka_api_key --api-secret $kafka_api_secret --cluster $ccloud_kafka_id aksqlapp

echo ">>Get ksqldb cluster id"
ccloud_ksql_id=`confluent ksql app list -ojson | jq '.[]|select(.name == "aksqlapp")'|jq -r .id`

echo
echo ">>>>Checking if ksqldb cluster is ready"
ccloud_ksql_status=`confluent ksql app describe $ccloud_ksql_id -o json | jq -r .status`

echo 
echo ">>>>Create api key for ksqldb cluster"
confluent api-key create --resource $ccloud_ksql_id -ojson > /tmp/ksql_api_key
echo 
ksql_api_key=`cat /tmp/ksql_api_key | jq -r .key`
kql_api_secret=`cat /tmp/ksql_api_key | jq -r .secret`


echo ">>>Create connector json"
cat << EOF > /tmp/users.json
{
    "name" : "datagen_ccloud_users",
    "connector.class": "DatagenSource",
    "kafka.auth.mode": "SERVICE_ACCOUNT",
    "kafka.service.account.id": "$ccloud_sa_id",
    "kafka.topic" : "users",
    "output.data.format" : "JSON",
    "quickstart" : "USERS",
    "max.interval": "500",
    "iterations": "1000000000",
    "tasks.max" : "1"
}
EOF

echo ">>>Setup permission for the service account"
confluent kafka acl create --allow --service-account $ccloud_sa_id --operation CREATE --prefix --topic users
confluent kafka acl create --allow --service-account $ccloud_sa_id --operation READ --prefix --topic users
confluent kafka acl create --allow --service-account $ccloud_sa_id --operation WRITE --prefix --topic users

echo ">>>Create connector"
confluent connect create --cluster $ccloud_kafka_id --config /tmp/users.json

echo ">>>Create connector datagen_ccloud_pageviews json"
cat << EOF > /tmp/pageviews.json
{
    "name" : "datagen_ccloud_pageviews",
    "connector.class": "DatagenSource",
    "kafka.auth.mode": "SERVICE_ACCOUNT",
    "kafka.service.account.id": "$ccloud_sa_id",
    "kafka.topic" : "pageviews",
    "output.data.format" : "JSON",
    "quickstart" : "PAGEVIEWS",
    "max.interval": "500",
    "iterations": "1000000000",
    "tasks.max" : "1"
}
EOF

echo ">>>Setup permission for the service account"
confluent kafka acl create --allow --service-account $ccloud_sa_id --operation CREATE --prefix --topic pageviews
confluent kafka acl create --allow --service-account $ccloud_sa_id --operation READ --prefix --topic pageviews
confluent kafka acl create --allow --service-account $ccloud_sa_id --operation WRITE --prefix --topic pageviews

echo ">>>Create connector"
confluent connect create --cluster $ccloud_kafka_id --config /tmp/pageviews.json

echo ">>>Get datagen users connector id"
datagen_users_id=`confluent connect list -ojson |jq '.[]|select(.name == "datagen_ccloud_users")'| jq -r .id`

echo ">>>Get datagen pageviews connector id"
datagen_pageviews_id=`confluent connect list -ojson |jq '.[]|select(.name == "datagen_ccloud_pageviews")'| jq -r .id`

echo "Datagen users connector status: `confluent connect describe $datagen_users_id --cluster $ccloud_kafka_id -ojson|jq -r .connector.status`"
echo "Datagen pageviews connector status: `confluent connect describe $datagen_pageviews_id --cluster $ccloud_kafka_id -ojson|jq -r .connector.status`"


