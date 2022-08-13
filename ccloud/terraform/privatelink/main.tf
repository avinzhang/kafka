terraform {
  required_version = ">= 0.14.0"

  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "1.0.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "= 4.25.0"
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


resource "confluent_network" "private-link" {
  display_name     = "Private Link Network"
  cloud            = "AWS"
  region           = var.aws_region
  connection_types = ["PRIVATELINK"]
  environment {
    id = var.confluent_env_id
  }
}

resource "confluent_private_link_access" "aws" {
  display_name = "AWS Private Link Access"
  aws {
    account = var.aws_account_id
  }
  environment {
    id = var.confluent_env_id
  }
  network {
    id = confluent_network.private-link.id
  }
}

resource "confluent_kafka_cluster" "dedicated" {
  display_name = "avin-dedicated"
  availability = "SINGLE_ZONE"
  cloud        = "AWS"
  region       = var.aws_region
  dedicated {
    cku = 1
  }
  environment {
    id = var.confluent_env_id
  }
  network {
    id = confluent_network.private-link.id
  }
}

# The following part requires proxy to be setup and cluster endpoints is added to DNS
# Comment all out for the first run
#resource "confluent_service_account" "app-manager" {
#  display_name = "app-manager"
#  description  = "Service account to manage Kafka cluster"
#}
#
#resource "confluent_role_binding" "app-manager-kafka-cluster-admin" {
#  principal   = "User:${confluent_service_account.app-manager.id}"
#  role_name   = "CloudClusterAdmin"
#  crn_pattern = confluent_kafka_cluster.dedicated.rbac_crn
#}
#
#resource "confluent_api_key" "app-manager-kafka-api-key" {
#  display_name = "app-manager-kafka-api-key"
#  description  = "Kafka API Key that is owned by 'app-manager' service account"
#  owner {
#    id          = confluent_service_account.app-manager.id
#    api_version = confluent_service_account.app-manager.api_version
#    kind        = confluent_service_account.app-manager.kind
#  }
#
#  managed_resource {
#    id          = confluent_kafka_cluster.dedicated.id
#    api_version = confluent_kafka_cluster.dedicated.api_version
#    kind        = confluent_kafka_cluster.dedicated.kind
#
#    environment {
#      id = var.confluent_env_id
#    }
#  }
#
#  depends_on = [
#    confluent_role_binding.app-manager-kafka-cluster-admin,
#    confluent_private_link_access.aws,
#    aws_vpc_endpoint.privatelink,
#    aws_route53_record.privatelink,
#    aws_route53_record.privatelink-zonal,
#  ]
#}
