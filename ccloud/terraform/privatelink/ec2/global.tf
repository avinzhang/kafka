terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws",
      version = "= 4.25.0"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  region = "ap-southeast-2"
  availability_zones = sort(data.aws_availability_zones.available.names)
}

provider "aws" {
  region = local.region
}
