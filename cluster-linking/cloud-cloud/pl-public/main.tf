terraform {
  required_version = ">= 0.14.0"

  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "1.3.0"
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

resource "confluent_kafka_cluster" "pl-dedicated" {
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
resource "confluent_service_account" "pl-app-manager" {
  display_name = "pl-app-manager"
  description  = "Service account to manage privatelink Kafka cluster"
}

resource "confluent_role_binding" "pl-app-manager-kafka-cluster-admin" {
  principal   = "User:${confluent_service_account.pl-app-manager.id}"
  role_name   = "CloudClusterAdmin"
  crn_pattern = confluent_kafka_cluster.pl-dedicated.rbac_crn
}

resource "confluent_api_key" "pl-app-manager-kafka-api-key" {
  display_name = "pl-app-manager-kafka-api-key"
  description  = "Kafka API Key that is owned by 'pl-app-manager' service account"
  owner {
    id          = confluent_service_account.pl-app-manager.id
    api_version = confluent_service_account.pl-app-manager.api_version
    kind        = confluent_service_account.pl-app-manager.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.pl-dedicated.id
    api_version = confluent_kafka_cluster.pl-dedicated.api_version
    kind        = confluent_kafka_cluster.pl-dedicated.kind

    environment {
      id = var.confluent_env_id
    }
  }

  depends_on = [
    confluent_role_binding.pl-app-manager-kafka-cluster-admin,
    confluent_private_link_access.aws,
  ]
}

resource "confluent_kafka_topic" "orders" {
  kafka_cluster {
    id = confluent_kafka_cluster.pl-dedicated.id
  }
  topic_name    = "orders"
  rest_endpoint = confluent_kafka_cluster.pl-dedicated.rest_endpoint
  credentials {
    key    = confluent_api_key.pl-app-manager-kafka-api-key.id
    secret = confluent_api_key.pl-app-manager-kafka-api-key.secret
  }
}

#Create cluster with public endpoint
resource "confluent_kafka_cluster" "pub-dedicated" {
  display_name = "pub-dedicated"
  availability = "SINGLE_ZONE"
  cloud        = "AWS"
  region       = var.aws_region
  dedicated {
    cku = 1
  }
  environment {
    id = var.confluent_env_id
  }
}
resource "confluent_service_account" "pub-app-manager" {
  display_name = "pub-app-manager"
  description  = "Service account to manage 'pub-dedicated' Kafka cluster"
}

resource "confluent_role_binding" "pub-app-manager-kafka-cluster-admin" {
  principal   = "User:${confluent_service_account.pub-app-manager.id}"
  role_name   = "CloudClusterAdmin"
  crn_pattern = confluent_kafka_cluster.pub-dedicated.rbac_crn
}

resource "confluent_api_key" "pub-app-manager-kafka-api-key" {
  display_name = "pub-app-manager-kafka-api-key"
  description  = "Kafka API Key that is owned by 'app-manager' service account"
  owner {
    id          = confluent_service_account.pub-app-manager.id
    api_version = confluent_service_account.pub-app-manager.api_version
    kind        = confluent_service_account.pub-app-manager.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.pub-dedicated.id
    api_version = confluent_kafka_cluster.pub-dedicated.api_version
    kind        = confluent_kafka_cluster.pub-dedicated.kind

    environment {
      id = var.confluent_env_id
    }
  }
}
