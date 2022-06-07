echo ">>Export api key as environment variables"
#export CONFLUENT_CLOUD_API_KEY="`cat /tmp/cloud_api_key | jq -r .key`"
#export CONFLUENT_CLOUD_API_SECRET="`cat /tmp/cloud_api_key | jq -r .secret`"

terraform destroy --auto-approve

for CONFLUENT_CLOUD_API_KEY in `confluent api-key list  -ojson | jq -r '.[]|select(.owner_email|startswith("avin+cops")).key'`
  do 
    confluent api-key delete $CONFLUENT_CLOUD_API_KEY
done

rm terraform.tfstate* tfplan
