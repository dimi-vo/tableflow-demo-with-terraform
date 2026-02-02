provider "confluent" {
  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}

provider "azuread" {
  tenant_id = var.azure_tenant_id
}

provider "azurerm" {
  features {
    
  }
  tenant_id       = var.azure_tenant_id
  subscription_id = var.subscription_id
}