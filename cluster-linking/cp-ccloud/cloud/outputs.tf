output "cloud-cluster-id" {
  value = "${confluent_kafka_cluster_v2.dedicated.id}"
}

output "cloud-cluster-rest" {
  value = "${confluent_kafka_cluster_v2.dedicated.rest_endpoint}"
}
output "cloud-cluster-endpoint" {
  value = "${confluent_kafka_cluster_v2.dedicated.bootstrap_endpoint}"
}

output "cluster-link-api-key" {
  value = "${confluent_api_key_v2.cluster-link-api-key.id}"
}

output "cluster-link-api-secret" {
  value = "${confluent_api_key_v2.cluster-link-api-key.secret}"
  sensitive = true
}

output "cluster-link-sa" {
  value = "${confluent_service_account_v2.cluster-link.id}"
}


output "resource-ids" {
  value = <<-EOT
  Kafka Cluster ID: ${confluent_kafka_cluster_v2.dedicated.id}

  Service Accounts and API Keys
  ${confluent_service_account_v2.cluster-link.display_name}:  ${confluent_service_account_v2.cluster-link.id}
  ${confluent_service_account_v2.cluster-link.display_name}:'s API Key:  "${confluent_api_key_v2.cluster-link-api-key.id}"
  ${confluent_service_account_v2.cluster-link.display_name}:'s API secret: "${confluent_api_key_v2.cluster-link-api-key.secret}"

  ${confluent_service_account_v2.app-consumer.display_name}:  ${confluent_service_account_v2.app-consumer.id}
  ${confluent_service_account_v2.app-consumer.display_name}:'s API Key:  "${confluent_api_key_v2.app-consumer-kafka-api-key.id}"
  ${confluent_service_account_v2.app-consumer.display_name}:'s API secret: "${confluent_api_key_v2.app-consumer-kafka-api-key.secret}"


  EOT
  sensitive = true
}
