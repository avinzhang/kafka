echo ">>Export api key as environment variables"
export CONFLUENT_CLOUD_API_KEY="`cat /tmp/cloud_api_key | jq -r .key`"
export CONFLUENT_CLOUD_API_SECRET="`cat /tmp/cloud_api_key | jq -r .secret`"

terraform destroy --auto-approve

confluent api-key delete $CONFLUENT_CLOUD_API_KEY

rm terraform.tfstate* tfplan
