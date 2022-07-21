#!/bin/bash 

confluent login --save
echo ">>Create SA"
confluent iam service-account create avin_oa_sa --description "avin's orgadmin sa" -ojson >./cloud_OrgAdmin_sa
export SA_ID="`cat ./cloud_OrgAdmin_sa | jq -r .id`"
echo
echo
echo ">>Create Cloud admin api key"
confluent api-key create --service-account $SA_ID --resource "cloud" -ojson > ./cloud_api_key
echo
echo
echo ">>Assign OrganizationAdmin role to SA"
confluent iam rbac role-binding create --principal User:$SA_ID --role OrganizationAdmin
echo
echo
echo ">>Export api key as environment variables"
export TF_VAR_confluent_cloud_api_key=`cat ./cloud_api_key | jq -r .key`
export TF_VAR_confluent_cloud_api_secret=`cat ./cloud_api_key | jq -r .secret`
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
   
    CLUSTER_STATUS=`confluent kafka cluster list -ojson|jq '.[]|select(.name == "avin-basic")'|jq -r .status`
    if [ "$CLUSTER_STATUS" == "UP" ]; then
      STARTED=true
      echo "Cluster is up"
    else
      echo "Waiting for cluster to start..."
    fi
    sleep 3
done


