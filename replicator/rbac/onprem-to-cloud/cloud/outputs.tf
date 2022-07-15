output "cloud-cluster-id" {
  value = "${confluent_kafka_cluster.basic.id}"
}

output "cloud-cluster-rest" {
  value = "${confluent_kafka_cluster.basic.rest_endpoint}"
}
output "cloud-cluster-endpoint" {
  value = "${confluent_kafka_cluster.basic.bootstrap_endpoint}"
}

output "app-manager-api-key" {
  value = "${confluent_api_key.app-manager-kafka-api-key.id}"
}

output "app-manager-api-secret" {
  value = "${confluent_api_key.app-manager-kafka-api-key.secret}"
  sensitive = true
}

output "replicator-api-key" {
  value = "${confluent_api_key.replicator-api-key.id}"
}

output "replicator-api-secret" {
  value = "${confluent_api_key.replicator-api-key.secret}"
  sensitive = true
}



output "resource-ids" {
  value = <<-EOT

  ${confluent_service_account.replicator.display_name}:  ${confluent_service_account.replicator.id} \n

  EOT
  sensitive = true
}
