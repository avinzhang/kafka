confluent login --save

echo ">>Export api key as environment variables"
export TF_VAR_confluent_cloud_api_key=`cat /tmp/cloud_api_key | jq -r .key`
export TF_VAR_confluent_cloud_api_secret=`cat /tmp/cloud_api_key | jq -r .secret`
terraform destroy --auto-approve

echo ">> Delete SA"
confluent iam service-account delete `confluent iam service-account list -ojson | jq -r '.[]|select(.name|startswith("avin")).id'`
echo
echo ">> Delete Cloud API key"
for CONFLUENT_CLOUD_API_KEY in `confluent api-key list  -ojson | jq -r '.[]|select(.owner_email|startswith("avin+cops")).key'`
  do 
    confluent api-key delete $CONFLUENT_CLOUD_API_KEY
    echo "Deleted api-key $CONFLUENT_CLOUD_API_KEY"
done



rm terraform.tfstate* tfplan prometheus/prometheus.yml
