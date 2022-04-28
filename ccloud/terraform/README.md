# Deploy a cluster 
  * create ccloud api key
  ```
  confluent api-key create --resource "cloud"
  ```

  * Export api key as variables
  export CONFLUENT_CLOUD_API_KEY="<cloud_api_key>"
  export CONFLUENT_CLOUD_API_SECRET="<cloud_api_secret>"

  * Deply cluster with main.tf
  ```
  terraform init
  terraform plan
  terraform apply
  ```
    a cluster should be deployed in Confluent Cloud.

# Display other resources within the cluster
  * Get cluster id.  Cluster id can be obtained with confluent cli
  ```
  confluent kafka cluster list
  ```

  * Get environment id, by using the display_name in main.tf
  ```
  confluent environment list | grep env_display_name
  ```

  * Create cluster api key
  ```
  confluent api-key create --resource <cluster_id> --environment <env_id>
  ```

  * Setup environment variables for api key
  export TF_VAR_kafka_api_key=" "
  expport TF_VAR_kafka_api_secret=""

  

  


