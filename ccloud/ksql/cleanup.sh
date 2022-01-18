#!/bin/bash

echo ">>>Get datagen users connector id"
datagen_users_id=`confluent connect list -ojson |jq '.[]|select(.name == "datagen_ccloud_users")'| jq -r .id`

echo ">>>Get datagen pageviews connector id"
datagen_pageviews_id=`confluent connect list -ojson |jq '.[]|select(.name == "datagen_ccloud_pageviews")'| jq -r .id`

confluent connect delete $datagen_users_id
confluent connect delete $datagen_pageviews_id

ccloud_ksql_id=`confluent ksql app list -ojson | jq '.[]|select(.name == "aksqlapp")'|jq -r .id`
confluent ksql app delete $ccloud_ksql_id

ccloud_kafka_id=`confluent kafka cluster list -ojson | jq '.[]|select(.name == "akafka")'|jq -r .id`
confluent kafka cluster delete $ccloud_kafka_id
