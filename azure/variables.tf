variable "prefix" {
  description = "Prefix for resources"
  type        = string
}

variable "cc_region" {
  type        = string
  description = "The region where our CC cluster resides"
}

variable "azure_tenant_id" {
  type        = string
}

variable "subscription_id" {
  description = "The Subscription ID. Go to Resource Manager > Subscriptions to find it"
  type        = string
}

variable "confluent_cloud_api_key" {
  description = "Confluent Cloud API Key (also referred as Cloud API ID)"
  type        = string
}

variable "confluent_cloud_api_secret" {
  description = "Confluent Cloud API Secret"
  type        = string
  sensitive   = true
}
