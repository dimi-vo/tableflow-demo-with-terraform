terraform {
  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "2.58.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}
