#! /bin/bash

echo ">>Create Cloud admin api key"
#confluent api-key create --resource "cloud" -ojson > /tmp/cloud_api_key
echo
echo ">>Export api key as environment variables"
export CONFLUENT_CLOUD_API_KEY="`cat /tmp/cloud_api_key | jq -r .key`"
export CONFLUENT_CLOUD_API_SECRET="`cat /tmp/cloud_api_key | jq -r .secret`"
echo
echo
echo ">> Create kafka cluster"
terraform plan -out=tfplan
terraform apply -target=confluentcloud_service_account.avin-sa -target=confluentcloud_kafka_cluster.avin-basic-cluster


STARTED=false
while [ $STARTED == false ]
do
    CLUSTER_STATUS=`confluent kafka cluster list -ojson|jq '.[]|select(.name == "avin_cluster")'|jq -r .status`
    if [ $CLUSTER_STATUS == "UP" ]; then
      STARTED=true
      echo "Cluster is up"
    else
      echo "Waiting for cluster to start..."
    fi
    sleep 3
done

CLUSTER_ID=`confluent kafka cluster list -ojson|jq '.[]|select(.name == "avin_cluster")'|jq -r .id`
echo ">>>>Cluster ID is $CLUSTER_ID"

echo
echo
echo ">>Create api-key on the cluster"
confluent api-key create --resource $CLUSTER_ID -ojson > /tmp/kafka_cluster_api_key
KAFKA_API_KEY=`cat /tmp/kafka_cluster_api_key | jq -r .key`
KAFKA_API_SECRET=`cat /tmp/kafka_cluster_api_key | jq -r .secret`
echo
echo ">>Export api key as environment variables"
export TF_VAR_kafka_api_key=$KAFKA_API_KEY
export TF_VAR_kafka_api_secret=$KAFKA_API_SECRET

terraform apply -target=confluentcloud_kafka_topic.orders -target=confluentcloud_kafka_acl.describe-orders -target=confluentcloud_kafka_acl.describe-avin-basic-cluster

echo
echo
echo ">>>Inspect created topic"
confluent kafka topic list --cluster $CLUSTER_ID
echo
echo ">>>Inspect ACLs"
confluent kafka acl list --cluster $CLUSTER_ID

# Terraform destroy --auto-approve
