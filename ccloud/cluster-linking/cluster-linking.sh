#!/bin/bash

echo ">>Create env"
confluent environment create avin
echo 
echo ">>Get env id"
confluent environment list -ojson| jq '.[]|select(.name == "avin")'|jq -r .id
ccloud_env=`confluent environment list -ojson| jq '.[]|select(.name == "avin")'|jq -r .id`

echo ">>Create source cluster in us-west-2 region"
confluent kafka cluster create ClusterLinkingSource --type basic --cloud aws --region us-west-2 --environment $ccloud_env
echo 
echo ">>Create dest cluster in us-east-1 region"
confluent kafka cluster create ClusterLinkingDestination --type dedicated --cloud aws --region us-east-1 --cku 1 --availability single-zone --environment $ccloud_env
echo
echo ">>Get source cluster id"
confluent kafka cluster list -ojson | jq '.[]|select(.name == "ClusterLinkingSource")'|jq -r .id
ccloud_src_id=`confluent kafka cluster list -ojson | jq '.[]|select(.name == "ClusterLinkingSource")'|jq -r .id`
echo 
echo ">>Get source cluster endpoint"
confluent kafka cluster describe $ccloud_src_id -ojson|jq -r .endpoint
ccloud_src_endpoint=`confluent kafka cluster describe $ccloud_src_id -ojson|jq -r .endpoint`
echo 
echo ">>Get dest cluster id"
confluent kafka cluster list -ojson | jq '.[]|select(.name == "ClusterLinkingDestination")'|jq -r .id
ccloud_dest_id=`confluent kafka cluster list -ojson | jq '.[]|select(.name == "ClusterLinkingDestination")'|jq -r .id`

echo 
echo ">>>>Checking if dest cluster is ready"
ccloud_dest_status=`confluent kafka cluster describe $ccloud_dest_id -ojson|jq -r .status`

while [ $ccloud_dest_status != 'UP' ]
do
  sleep 5
  ccloud_dest_status=`confluent kafka cluster describe $ccloud_dest_id -ojson|jq -r .status`
done

echo ">>>>Dest cluster is UP"
echo 
echo 
echo ">>Create api key on src cluster"
confluent api-key create --resource $ccloud_src_id -ojson > /tmp/src_api_key
echo
src_api_key=`cat /tmp/src_api_key | jq -r .key`
src_api_secret=`cat /tmp/src_api_key | jq -r .secret`

echo
echo ">>Create cluster link on source cluster"
confluent kafka link create my-link --cluster $ccloud_dest_id \
    --source-cluster-id $ccloud_src_id \
    --source-bootstrap-server $ccloud_src_endpoint \
    --source-api-key $src_api_key --source-api-secret $src_api_secret

echo
echo ">>Create source topic"
confluent kafka topic create src-topic --cluster $ccloud_src_id --partitions 1
echo
echo ">>>>Produce some data to the src-topic"
seq 1 10 | confluent kafka topic produce src-topic --cluster $ccloud_src_id --api-key $src_api_key --api-secret $src_api_secret
echo
echo ">>Create mirror topic on dest cluster"
confluent kafka mirror create dest-topic --cluster $ccloud_dest_id --link my-link
echo
echo ">>Create api key on dest cluster"
confluent api-key create --resource $ccloud_dest_id -ojson > /tmp/dest_api_key
echo 
dest_api_key=`cat /tmp/dest_api_key | jq -r .key`
dest_api_secret=`cat /tmp/dest_api_key | jq -r .secret`
echo 
echo ">>Consume from dest cluster"
confluent kafka topic consume src-topic --cluster $ccloud_dest_id --api-key $dest_api_key --api-secret $dest_api_secret --from-beginning


# Teardown
#confluent kafka topic delete src-topic --cluster $ccloud_dest_id
#confluent kafka topic delete src-topic --cluster $ccloud_src_id
#confluent kafka link delete my-link --cluster $ccloud_dest_id
#confluent kafka cluster delete $ccloud_dest_id
#onfluent kafka cluster delete $ccloud_src_id

