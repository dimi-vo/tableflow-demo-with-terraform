variable "confluent_cloud_api_key" {
  description = "Confluent Cloud API Key (also referred as Cloud API ID)"
  type        = string
}

variable "confluent_cloud_api_secret" {
  description = "Confluent Cloud API Secret"
  type        = string
  sensitive   = true
}

variable "cc_region" {
  type        = string
  description = "The region where our CC cluster resides"
}

variable "bucket_name" {
  type = string
}

variable "prefix" {
  description = "Prefix for resources"
  type        = string
  default     = "your-name"
}

variable "tags" {
  type = map(string)
  default = {
    Project = "your-name-demo"
  }
}

variable "customer_region" {
  type = string
}

variable "aws_account_id" {
  description = "The AWS account ID of the customer VPC to peer with."
  type        = string
}

variable "cloud_provider" {
  description = "The cloud provider for the Kafka cluster."
  type        = string
  default     = "AWS"
}

variable "tableflow_table_format" {
  description = "Defines the format of the Tableflow tables, ICEBERG or DELTA"
  type        = list(string)
}

variable "iam-username" {
  type = string
  description = "Your IAM username"
}
