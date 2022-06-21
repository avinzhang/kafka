#! /bin/bash

confluent login --save
echo ">>Create SA"
confluent iam service-account create avin_oa_sa --description "avin's orgadmin sa" -ojson >/tmp/cloud_oa_sa
export SA_ID="`cat /tmp/cloud_oa_sa | jq -r .id`"
echo
echo
echo ">>Create Cloud admin api key"
confluent api-key create --service-account $SA_ID --resource "cloud" -ojson > /tmp/cloud_api_key
echo
echo
echo ">>Assign OrganizationAdmin role to SA"
confluent iam rbac role-binding create --principal User:$SA_ID --role OrganizationAdmin
echo
echo
echo ">>Export api key as environment variables"
export CONFLUENT_CLOUD_API_KEY="`cat /tmp/cloud_api_key | jq -r .key`"
export CONFLUENT_CLOUD_API_SECRET="`cat /tmp/cloud_api_key | jq -r .secret`"
echo
echo
echo ">>Setup API key as terraform env variable"
export TF_VAR_confluent_cloud_api_key=$CONFLUENT_CLOUD_API_KEY
export TF_VAR_confluent_cloud_api_secret=$CONFLUENT_CLOUD_API_SECRET
echo
echo ">> Create kafka cluster"
terraform init -upgrade
terraform plan -out=tfplan
terraform apply --auto-approve
echo
echo ">> Set environment"
confluent environment use `confluent environment list -ojson | jq -r '.[]|select(.name == "avin").id'`
echo
echo
STARTED=false
while [ $STARTED == false ]
do
   
    CLUSTER_STATUS=`confluent kafka cluster list -ojson|jq '.[]|select(.name == "avin-dedicated")'|jq -r .status`
    if [ $CLUSTER_STATUS == "UP" ]; then
      STARTED=true
      echo "Cluster is up"
    else
      echo "Waiting for cluster to start..."
    fi
    sleep 3
done
exit
CLUSTER_ID=`confluent kafka cluster list -ojson|jq '.[]|select(.name == "avin-dedicated")'|jq -r .id`
echo ">>>>Cluster ID is $CLUSTER_ID"
echo
echo "Cluster-link API Key: `terraform output -json | jq -r '."cluster-link-api-key"."value"'`"
echo "Cluster-link API Secret: `terraform output -json | jq -r '."cluster-link-api-secret"."value"'`"
