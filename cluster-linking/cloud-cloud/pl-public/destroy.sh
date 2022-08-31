confluent login --save

echo ">>Export api key as environment variables"
export TF_VAR_confluent_cloud_api_key=`cat ./cloud_api_key | jq -r .key`
export TF_VAR_confluent_cloud_api_secret=`cat ./cloud_api_key | jq -r .secret`
export TF_VAR_ec2_ip=`terraform -chdir=./ec2 output -json | jq -r '."ec2-ip"."value"'`
export TF_VAR_vpc_id=`terraform -chdir=./ec2 output -json | jq -r '."vpc-id"."value"'`
export TF_VAR_subnets_to_privatelink=`terraform -chdir=./ec2 output -json | jq -r '."cloudsub"."value"'`
terraform destroy --auto-approve

echo ">> Delete SA"
for SA in `confluent iam service-account list -ojson | jq -r '.[]|select(.name|startswith("avin")).id'`
  do
      confluent iam service-account delete $SA
  echo "Deleted $SA"
done
echo
echo ">> Delete Cloud API key"
for CONFLUENT_CLOUD_API_KEY in `confluent api-key list  -ojson | jq -r '.[]|select(.owner_email|startswith("avin+cops")).key'`
  do 
    confluent api-key delete $CONFLUENT_CLOUD_API_KEY
    echo "Deleted api-key $CONFLUENT_CLOUD_API_KEY"
done

rm terraform.tfstate* cloud_api_key cloud_OrgAdmin_sa tfplan ec2/terraform.tfstate* ec2/tfplan
