terraform {
  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "0.11.0"
    }
  }
}

provider "confluent" {
  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}

#resource "confluent_environment" "avin" {
#  display_name = "avin"
#}

resource "confluent_kafka_cluster_v2" "dedicated" {
  display_name = "avin-dedicated"
  availability = "SINGLE_ZONE"
  cloud        = "AWS"
  region       = "ap-southeast-2"
  dedicated {
    cku = 1
  }
  environment {
    id = var.confluent_env_id
  }
}

resource "confluent_service_account_v2" "cluster-link" {
  display_name = "avin-cluster-link-SA"
  description  = "Service account to Kafka cluster linking"
}

resource "confluent_role_binding_v2" "cluster-link-admin" {
  principal   = "User:${confluent_service_account_v2.cluster-link.id}"
  role_name   = "CloudClusterAdmin"
  crn_pattern = confluent_kafka_cluster_v2.dedicated.rbac_crn
}

resource "confluent_api_key_v2" "cluster-link-api-key" {
  display_name = "avin-cluster-link-api-key"
  description  = "Kafka API Key that is owned by 'cluster-link' service account"
  owner {
    id          = confluent_service_account_v2.cluster-link.id
    api_version = confluent_service_account_v2.cluster-link.api_version
    kind        = confluent_service_account_v2.cluster-link.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster_v2.dedicated.id
    api_version = confluent_kafka_cluster_v2.dedicated.api_version
    kind        = confluent_kafka_cluster_v2.dedicated.kind

    environment {
      id = var.confluent_env_id
    }
  }

  depends_on = [
    confluent_role_binding_v2.cluster-link-admin
  ]
}


resource "confluent_service_account_v2" "app-consumer" {
  display_name = "avin-app-consumer"
  description  = "Service account to consume topics of Kafka cluster"
}

resource "confluent_api_key_v2" "app-consumer-kafka-api-key" {
  display_name = "avin-app-consumer-kafka-api-key"
  description  = "Kafka API Key that is owned by 'app-consumer' service account"
  owner {
    id          = confluent_service_account_v2.app-consumer.id
    api_version = confluent_service_account_v2.app-consumer.api_version
    kind        = confluent_service_account_v2.app-consumer.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster_v2.dedicated.id
    api_version = confluent_kafka_cluster_v2.dedicated.api_version
    kind        = confluent_kafka_cluster_v2.dedicated.kind

    environment {
      id = var.confluent_env_id
    }
  }
}



