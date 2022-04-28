variable "kafka_api_key" {
  type = string
  description = "Kafka API Key"
}

variable "kafka_api_secret" {
  type = string
  description = "Kafka API Secret"
  sensitive = true  
}
