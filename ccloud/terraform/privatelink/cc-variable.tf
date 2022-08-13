variable "confluent_cloud_api_key" {
  type = string
  description = "Confluent Cloud API Key"
}

variable "confluent_cloud_api_secret" {
  type = string
  description = "Confluent Cloud API Secret"
  sensitive = true  
}


variable "confluent_env_id" {
  type = string
  description = "Confluent Cloud env id"
  default = "env-dd6dz"
}

variable "aws_region" {
  type = string
  description = "AWS region to be used"
  default = "ap-southeast-2"
}

variable "aws_account_id" {
  type = string
}
