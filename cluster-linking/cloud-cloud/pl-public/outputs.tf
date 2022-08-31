output "pl-cluster-id" {
  value = "${confluent_kafka_cluster.pl-dedicated.id}"
}


output "pl-cluster-endpoint" {
  value = "${confluent_kafka_cluster.pl-dedicated.bootstrap_endpoint}"
}

output "pub-cluster-id" {
  value = "${confluent_kafka_cluster.pub-dedicated.id}"
}

output "pub-cluster-endpoint" {
  value = "${confluent_kafka_cluster.pub-dedicated.bootstrap_endpoint}"
}

output "pub-app-manager-api-key" {
  value = "${confluent_api_key.pub-app-manager-kafka-api-key.id}"
}
output "pub-app-manager-api-secret" {
  value = "${confluent_api_key.pub-app-manager-kafka-api-key.secret}"
  sensitive = true
}

# Below needs proxy and DNS to be setup first 
output "pl-app-manager-api-key" {
  value = "${confluent_api_key.pl-app-manager-kafka-api-key.id}"
}
output "pl-app-manager-api-secret" {
  value = "${confluent_api_key.pl-app-manager-kafka-api-key.secret}"
  sensitive = true
}
