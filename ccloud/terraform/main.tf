terraform {
  required_providers {
    confluentcloud = {
      source  = "confluentinc/confluentcloud"
      version = "0.5.0"
    }
  }
}

provider "confluentcloud" {}

resource "confluentcloud_service_account" "avin-sa" {
  display_name = "avin_sa"
  description = "description for avin_sa"
}

#resource "confluentcloud_environment" "avin" {
#  display_name = "avin"
#}

resource "confluentcloud_kafka_cluster" "avin-basic-cluster" {
  display_name = "avin_cluster"
  availability = "SINGLE_ZONE"
  cloud = "GCP"
  region = "us-central1"
  basic {}
  environment {
    id = "env-dd6dz"
  }
}

resource "confluentcloud_kafka_topic" "orders" {
  kafka_cluster = confluentcloud_kafka_cluster.avin-basic-cluster.id
  topic_name = "orders"
  partitions_count = 4
  http_endpoint = confluentcloud_kafka_cluster.avin-basic-cluster.http_endpoint
  config = {
    "cleanup.policy" = "compact"
    "retention.ms" = "6789000"
  }
  credentials {
    key = var.kafka_api_key
    secret = var.kafka_api_secret
  }
}

resource "confluentcloud_kafka_acl" "describe-orders" {
  kafka_cluster = confluentcloud_kafka_cluster.avin-basic-cluster.id
  resource_type = "TOPIC"
  resource_name = confluentcloud_kafka_topic.orders.topic_name
  pattern_type = "LITERAL"
  principal = "User:${confluentcloud_service_account.avin-sa.id}"
  operation = "DESCRIBE"
  permission = "ALLOW"
  http_endpoint = confluentcloud_kafka_cluster.avin-basic-cluster.http_endpoint
  credentials {
    key = var.kafka_api_key
    secret = var.kafka_api_secret
  }
}

resource "confluentcloud_kafka_acl" "describe-avin-basic-cluster" {
  kafka_cluster = confluentcloud_kafka_cluster.avin-basic-cluster.id
  resource_type = "CLUSTER"
  resource_name = "kafka-cluster"
  pattern_type = "LITERAL"
  principal = "User:${confluentcloud_service_account.avin-sa.id}"
  operation = "DESCRIBE"
  permission = "ALLOW"
  http_endpoint = confluentcloud_kafka_cluster.avin-basic-cluster.http_endpoint
  credentials {
    key = var.kafka_api_key
    secret = var.kafka_api_secret
  }
}
