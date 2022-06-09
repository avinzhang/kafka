#! /bin/bash

echo ">>Create SA"
confluent iam service-account create avin_oa_sa --description "avin's orgadmin sa" -ojson >/tmp/cloud_oa_sa
export SA_ID="`cat /tmp/cloud_oa_sa | jq -r .id`"
echo
echo
echo ">>Create Cloud admin api key"
#confluent api-key create --service-account $SA_ID --resource "cloud" -ojson > /tmp/cloud_api_key
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
terraform init
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
    if [ $CLUSTER_STATUS == "UP" ]; then
      STARTED=true
      echo "Cluster is up"
    else
      echo "Waiting for cluster to start..."
    fi
    sleep 3
done
CLUSTER_ID=`confluent kafka cluster list -ojson|jq '.[]|select(.name == "avin-basic")'|jq -r .id`
echo ">>>>Cluster ID is $CLUSTER_ID"
echo
echo
echo ">> Create api keys for metric vieweer"
METRIC_SA_ID=`confluent iam service-account list -ojson | jq -r '.[]|select(.name|startswith("metric-importer")).id'`
confluent api-key create --resource cloud --service-account $METRIC_SA_ID -ojson > /tmp/metric_api_key

export METRIC_API_KEY="`cat /tmp/metric_api_key| jq -r .key`"
export METRIC_API_SECRET="`cat /tmp/metric_api_key| jq -r .secret`"
cat << EOF >./prometheus/prometheus.yml
global:
  scrape_interval:     15s # By default, scrape targets every 15 seconds.
  evaluation_interval: 15s # By default, scrape targets every 15 seconds.

rule_files:
  - 'alert.rules'

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
    - targets: ['localhost:9090']

  - job_name: Confluent Cloud
    scrape_interval: 1m
    scrape_timeout: 1m
    honor_timestamps: true
    static_configs:
      - targets:
        - api.telemetry.confluent.cloud
    scheme: https
    basic_auth:
      username: $METRIC_API_KEY
      password: $METRIC_API_SECRET
    metrics_path: /v2/metrics/cloud/export
    params:
      resource.kafka.id: [${CLUSTER_ID}]
      resource.connector.id: [${CCLOUD_CONNECT_LCC_IDS}]
      resource.ksql.id: [${CCLOUD_KSQL_LKSQLC_IDS}]
      resource.schema_registry.id: [${CCLOUD_SR_LSRC_IDS}]
EOF

docker-compose up -d --build --no-deps prometheus grafana
