terraform {
  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "2.34.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">=5.17.0"
    }
  }
}
