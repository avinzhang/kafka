#! /bin/bash

CLUSTER_ID=`terraform output -json -state=./cloud/terraform.tfstate| jq -r '."cloud-cluster-id"."value"'`

CCLOUD_CONNECT_LCC_IDS=terraform output -json -state=./cloud/terraform.tfstate| jq -r '."connector-id"."value"'`

echo ">> Create api keys for metric vieweer"
METRIC_SA_ID=`terraform output -json -state=./cloud/terraform.tfstate| jq -r '."metric-importer-sa"."value"'`
confluent api-key create --resource cloud --service-account $METRIC_SA_ID -ojson > ./metric_api_key

export METRIC_API_KEY="`cat ./metric_api_key| jq -r .key`"
export METRIC_API_SECRET="`cat ./metric_api_key| jq -r .secret`"
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
