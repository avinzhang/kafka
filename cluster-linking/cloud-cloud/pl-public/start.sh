#!/bin/bash 
echo "Create VPC and EC2 in AWS"
terraform -chdir=./ec2 init -upgrade
terraform -chdir=./ec2 plan -out=tfplan
terraform -chdir=./ec2 apply --auto-approve
echo
export TF_VAR_vpc_id=`terraform -chdir=./ec2 output -json | jq -r '."vpc-id"."value"'`
export TF_VAR_subnets_to_privatelink=`terraform -chdir=./ec2 output -json | jq -r '."cloudsub"."value"'`
export TF_VAR_ec2_ip=`terraform -chdir=./ec2 output -json | jq -r '."ec2-ip"."value"'`
confluent login --save
echo ">>Create SA"
ls ./cloud_OrgAdmin_sa || confluent iam service-account create avin_oa_sa --description "avin's orgadmin sa" -ojson >./cloud_OrgAdmin_sa
export SA_ID="`cat ./cloud_OrgAdmin_sa | jq -r .id`"
echo
echo
echo ">>Create Cloud admin api key"
ls ./cloud_api_key || confluent api-key create --service-account $SA_ID --resource "cloud" -ojson > ./cloud_api_key
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
echo "EC2 public IP: "`terraform -chdir=./ec2 output -json | jq -r '."ec2-ip"."value"'`
echo
echo ">> Set environment"
confluent environment use `confluent environment list -ojson | jq -r '.[]|select(.name == "avin").id'`
echo
echo
STARTED=false
while [ $STARTED == false ]
do
   
    CLUSTER_STATUS=`confluent kafka cluster list -ojson|jq '.[]|select(.name == "avin-dedicated")'|jq -r .status`
    if [ "$CLUSTER_STATUS" == "UP" ]; then
      STARTED=true
      echo "Cluster is up"
    else
      echo "Waiting for cluster to start..."
    fi
    sleep 3
done

echo 
echo 
echo ">> Create cluster link"
echo
echo ">>>> Create public half of the link config"
cat << EOF > /tmp/public-dest-link.config
link.mode=DESTINATION
connection.mode=INBOUND
EOF
echo 
PUB_CLUSTER_ID=`terraform output -json |jq -r '."pub-cluster-id"."value"'`
PL_CLUSTER_ID=`terraform output -json |jq -r '."pl-cluster-id"."value"'`
echo ">>>> Create the link"
confluent kafka link create pl-to-public --cluster $PUB_CLUSTER_ID --config-file /tmp/public-dest-link.config --source-cluster-id $PL_CLUSTER_ID
echo
echo
PUB_API_KEY=`terraform output -json |jq -r '."pub-app-manager-api-key"."value"'`
PUB_API_SECRET=`terraform output -json |jq -r '."pub-app-manager-api-secret"."value"'`
PL_API_KEY=`terraform output -json |jq -r '."pl-app-manager-api-key"."value"'`
PL_API_SECRET=`terraform output -json |jq -r '."pl-app-manager-api-secret"."value"'`
echo ">>> Create privatelink half of the link config"
cat << EOF > /tmp/private-source-link.config 
link.mode=SOURCE
connection.mode=OUTBOUND

security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username='$PUB_API_KEY' password='$PUB_API_SECRET';

local.security.protocol=SASL_SSL
local.sasl.mechanism=PLAIN
local.sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username='$PL_API_KEY' password='$PL_API_SECRET';
EOF
echo
PUB_CLUSTER_ENDPOINT=`terraform output -json |jq -r '."pub-cluster-endpoint"."value"'`
echo ">>> Create cluster link on the PrivateLink cluster"
confluent kafka link create pl-to-public \
  --cluster $PL_CLUSTER_ID \
  --destination-cluster-id $PUB_CLUSTER_ID \
  --destination-bootstrap-server $PUB_CLUSTER_ENDPOINT \
  --config-file /tmp/private-source-link.config

echo
echo ">>> Create topic mirrors"
confluent kafka mirror create orders --link pl-to-public --cluster $PUB_CLUSTER_ID



