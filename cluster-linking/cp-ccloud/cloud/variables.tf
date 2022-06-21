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
