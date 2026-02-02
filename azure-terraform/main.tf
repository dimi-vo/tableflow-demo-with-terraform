resource "confluent_environment" "main" {
  display_name = "${var.prefix}-env"

  stream_governance {
    package = "ESSENTIALS"
  }
}

data "confluent_schema_registry_cluster" "essentials" {
  environment {
    id = confluent_environment.main.id
  }

  depends_on = [
    confluent_kafka_cluster.main
  ]
}

resource "confluent_kafka_cluster" "main" {
  display_name = "${var.prefix}-cluster"
  availability = "SINGLE_ZONE"
  cloud        = "AZURE"
  region       = var.cc_region
  standard {}
  environment {
    id = confluent_environment.main.id
  }
}

resource "confluent_provider_integration_setup" "azure" {
  environment {
    id = confluent_environment.main.id
  }

  display_name = "${var.prefix}-azure-integration"
  cloud        = "AZURE"
}

resource "confluent_provider_integration_authorization" "azure" {
  provider_integration_id = confluent_provider_integration_setup.azure.id

  environment {
    id = confluent_environment.main.id
  }

  azure {
    customer_azure_tenant_id = var.azure_tenant_id
  }
}

# The next three resources create a service account with
# CloudClusterAdmin role and an API key owned by that service account.
# This API key will be used to create Kafka topics and ACLs.
# SA --> Role Binding for that SA --> API Key for that SA
resource "confluent_service_account" "app_manager" {
  display_name = "${var.prefix}-app_manager-sa"
  description  = "Service account to manage 'inventory' Kafka cluster"
}

resource "confluent_role_binding" "app_manager_kafka_cluster_admin" {
  principal   = "User:${confluent_service_account.app_manager.id}"
  role_name   = "CloudClusterAdmin"
  crn_pattern = confluent_kafka_cluster.main.rbac_crn
}

resource "confluent_api_key" "app_manager_kafka_api_key" {
  display_name = "${var.prefix}-app_manager-kafka-api-key"
  owner {
    id          = confluent_service_account.app_manager.id
    api_version = confluent_service_account.app_manager.api_version
    kind        = confluent_service_account.app_manager.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.main.id
    api_version = confluent_kafka_cluster.main.api_version
    kind        = confluent_kafka_cluster.main.kind

    environment {
      id = confluent_environment.main.id
    }
  }

  # The goal is to ensure that confluent_role_binding.app_manager_kafka_cluster_admin is created before
  # confluent_api_key.app_manager_kafka_api_key is used to create instances of
  # confluent_kafka_topic, confluent_kafka_acl resources.

  # 'depends_on' meta-argument is specified in confluent_api_key.app_manager_kafka_api_key to avoid having
  # multiple copies of this definition in the configuration which would happen if we specify it in
  # confluent_kafka_topic, confluent_kafka_acl resources instead.
  depends_on = [
    confluent_role_binding.app_manager_kafka_cluster_admin
  ]
}

# Create a Service Principal in Azure AD for Confluent to access resources in the customer's Azure subscription
resource "azuread_service_principal" "confluent" {
  client_id    = confluent_provider_integration_authorization.azure.azure[0].confluent_multi_tenant_app_id
  use_existing = true

  depends_on = [
    confluent_provider_integration_authorization.azure
  ]
}

resource "azurerm_resource_group" "confluent" {
  name     = "${var.prefix}-rg"
  location = var.cc_region
}

resource "azurerm_storage_account" "adls" {
  name                     = "${var.prefix}adls"
  resource_group_name      = azurerm_resource_group.confluent.name
  location                 = azurerm_resource_group.confluent.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  # This enables Azure Data Lake Storage Gen2
  is_hns_enabled = true
}

resource "azurerm_storage_container" "confluent_data" {
  name = "${var.prefix}-container"
  # storage_account_name  = azurerm_storage_account.adls.name # This is marked as deprecated
  storage_account_id    = azurerm_storage_account.adls.id
  container_access_type = "private"
}

# Give the Confluent Service Principal the "Storage Blob Data Contributor" role on the ADLS account to allow it to read and write data
resource "azurerm_role_assignment" "blob_contributor" {
  scope                = azurerm_storage_account.adls.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.confluent.object_id
}

# Not sure why/if this is needed in addition to the above role assignment
resource "azurerm_role_assignment" "reader" {
  scope                = azurerm_storage_account.adls.id
  role_definition_name = "Reader"
  principal_id         = azuread_service_principal.confluent.object_id
}


resource "confluent_service_account" "app_consumer" {
  display_name = "${var.prefix}-app_consumer-sa"
  description  = "Service account to consume from 'orders' topic of 'inventory' Kafka cluster"
}

resource "confluent_api_key" "app_consumer_kafka_api_key" {
  display_name = "${var.prefix}-app_consumer-kafka-api-key"
  description  = "Kafka API Key that is owned by 'app-consumer' service account"
  owner {
    id          = confluent_service_account.app_consumer.id
    api_version = confluent_service_account.app_consumer.api_version
    kind        = confluent_service_account.app_consumer.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.main.id
    api_version = confluent_kafka_cluster.main.api_version
    kind        = confluent_kafka_cluster.main.kind

    environment {
      id = confluent_environment.main.id
    }
  }
}

resource "confluent_kafka_acl" "app_producer_write_on_topic" {
  kafka_cluster {
    id = confluent_kafka_cluster.main.id
  }
  resource_type = "TOPIC"
  resource_name = confluent_kafka_topic.orders.topic_name
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app_producer.id}"
  host          = "*"
  operation     = "WRITE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.main.rest_endpoint
  credentials {
    key    = confluent_api_key.app_manager_kafka_api_key.id
    secret = confluent_api_key.app_manager_kafka_api_key.secret
  }
}

resource "confluent_service_account" "app_producer" {
  display_name = "${var.prefix}-app_producer-sa"
  description  = "Service account to produce to 'orders' topic of 'inventory' Kafka cluster"
}

resource "confluent_api_key" "app_producer_kafka_api_key" {
  display_name = "${var.prefix}-app_producer-kafka-api-key"
  description  = "Kafka API Key that is owned by 'app-producer' service account"
  owner {
    id          = confluent_service_account.app_producer.id
    api_version = confluent_service_account.app_producer.api_version
    kind        = confluent_service_account.app_producer.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.main.id
    api_version = confluent_kafka_cluster.main.api_version
    kind        = confluent_kafka_cluster.main.kind

    environment {
      id = confluent_environment.main.id
    }
  }
}


resource "confluent_kafka_acl" "app_consumer_read_on_topic" {
  kafka_cluster {
    id = confluent_kafka_cluster.main.id
  }
  resource_type = "TOPIC"
  resource_name = confluent_kafka_topic.orders.topic_name
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app_consumer.id}"
  host          = "*"
  operation     = "READ"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.main.rest_endpoint
  credentials {
    key    = confluent_api_key.app_manager_kafka_api_key.id
    secret = confluent_api_key.app_manager_kafka_api_key.secret
  }
}

resource "confluent_kafka_acl" "app_consumer_read_on_group" {
  kafka_cluster {
    id = confluent_kafka_cluster.main.id
  }
  resource_type = "GROUP"

  resource_name = "confluent_cli_consumer_"
  pattern_type  = "PREFIXED"
  principal     = "User:${confluent_service_account.app_consumer.id}"
  host          = "*"
  operation     = "READ"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.main.rest_endpoint
  credentials {
    key    = confluent_api_key.app_manager_kafka_api_key.id
    secret = confluent_api_key.app_manager_kafka_api_key.secret
  }
}

resource "confluent_service_account" "connector" {
  display_name = "${var.prefix}-datagen-connector-sa"
}

resource "confluent_api_key" "connector_kafka_api_key" {
  display_name = "${var.prefix}-datagen-connector-kafka-api-key"
  owner {
    id          = confluent_service_account.connector.id
    api_version = confluent_service_account.connector.api_version
    kind        = confluent_service_account.connector.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.main.id
    api_version = confluent_kafka_cluster.main.api_version
    kind        = confluent_kafka_cluster.main.kind

    environment {
      id = confluent_environment.main.id
    }
  }
}

resource "confluent_api_key" "connector_schema_registry_api_key" {
  display_name = "${var.prefix}-datagen-connector-schema-registry-api-key"
  owner {
    id          = confluent_service_account.connector.id
    api_version = confluent_service_account.connector.api_version
    kind        = confluent_service_account.connector.kind
  }

  managed_resource {
    id          = data.confluent_schema_registry_cluster.essentials.id
    api_version = data.confluent_schema_registry_cluster.essentials.api_version
    kind        = data.confluent_schema_registry_cluster.essentials.kind

    environment {
      id = confluent_environment.main.id
    }
  }
}

resource "confluent_kafka_acl" "connector_write_on_stocks_topic" {
  kafka_cluster {
    id = confluent_kafka_cluster.main.id
  }
  resource_type = "TOPIC"
  resource_name = confluent_kafka_topic.stocks.topic_name
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.connector.id}"
  host          = "*"
  operation     = "WRITE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.main.rest_endpoint
  credentials {
    key    = confluent_api_key.app_manager_kafka_api_key.id
    secret = confluent_api_key.app_manager_kafka_api_key.secret
  }
}

resource "confluent_service_account" "tableflow" {
  display_name = "${var.prefix}-tableflow-sa"
  description  = "Service account for Tableflow operations"
}

# Is this needed in addition to the EnvironmentAdmin role binding below?
resource "confluent_role_binding" "tableflow_kafka_cluster_admin" {
  principal   = "User:${confluent_service_account.tableflow.id}"
  role_name   = "CloudClusterAdmin"
  crn_pattern = confluent_kafka_cluster.main.rbac_crn
}

resource "confluent_role_binding" "tableflow_environment_admin" {
  principal   = "User:${confluent_service_account.tableflow.id}"
  role_name   = "EnvironmentAdmin"
  crn_pattern = confluent_environment.main.resource_name
}

# Is this needed in addition to the EnvironmentAdmin role binding above?
resource "confluent_role_binding" "tableflow_schema_registry_developer_read" {
  principal   = "User:${confluent_service_account.tableflow.id}"
  role_name   = "DeveloperRead"
  crn_pattern = "${data.confluent_schema_registry_cluster.essentials.resource_name}/subject=*"

  depends_on = [
    data.confluent_schema_registry_cluster.essentials
  ]
}

resource "confluent_api_key" "tableflow_api_key" {
  display_name = "${var.prefix}-tableflow-api-key"
  owner {
    id          = confluent_service_account.tableflow.id
    api_version = confluent_service_account.tableflow.api_version
    kind        = confluent_service_account.tableflow.kind
  }

  managed_resource {
    id          = "tableflow"
    api_version = "tableflow/v1"
    kind        = "Tableflow"

    environment {
      id = confluent_environment.main.id
    }
  }

  # Ensure role bindings are created before the API key
  depends_on = [
    confluent_role_binding.tableflow_kafka_cluster_admin,
    confluent_role_binding.tableflow_schema_registry_developer_read
  ]
}

resource "confluent_kafka_topic" "orders" {
  kafka_cluster {
    id = confluent_kafka_cluster.main.id
  }
  topic_name    = "orders"
  rest_endpoint = confluent_kafka_cluster.main.rest_endpoint
  credentials {
    key    = confluent_api_key.app_manager_kafka_api_key.id
    secret = confluent_api_key.app_manager_kafka_api_key.secret
  }
}

resource "confluent_kafka_topic" "stocks" {
  kafka_cluster {
    id = confluent_kafka_cluster.main.id
  }
  topic_name    = "stocks"
  rest_endpoint = confluent_kafka_cluster.main.rest_endpoint
  credentials {
    key    = confluent_api_key.app_manager_kafka_api_key.id
    secret = confluent_api_key.app_manager_kafka_api_key.secret
  }
}

resource "confluent_connector" "datagen_stocks" {
  environment {
    id = confluent_environment.main.id
  }
  kafka_cluster {
    id = confluent_kafka_cluster.main.id
  }
  status = "RUNNING"
  config_nonsensitive = {
    "connector.class"          = "DatagenSource"
    "kafka.auth.mode"          = "SERVICE_ACCOUNT"
    "kafka.service.account.id" = confluent_service_account.connector.id
    "kafka.topic"              = confluent_kafka_topic.stocks.topic_name
    "name"                     = "${var.prefix}-datagen-stocks-connector"
    "output.data.format"       = "AVRO"
    "quickstart"               = "stock_trades"
    "tasks.max"                = "1"
  }
  depends_on = [
    confluent_kafka_topic.stocks,
    confluent_kafka_acl.connector_write_on_stocks_topic,
    confluent_api_key.connector_kafka_api_key,
    confluent_api_key.connector_schema_registry_api_key
  ]
}

resource "confluent_tableflow_topic" "DatagenConnectorTopic" {
  environment {
    id = confluent_environment.main.id
  }
  kafka_cluster {
    id = confluent_kafka_cluster.main.id
  }
  credentials {
    key    = confluent_api_key.tableflow_api_key.id
    secret = confluent_api_key.tableflow_api_key.secret
  }
  display_name  = confluent_kafka_topic.stocks.topic_name
  table_formats = ["ICEBERG"]
  azure_data_lake_storage_gen_2 {
    provider_integration_id = confluent_provider_integration_authorization.azure.id
    container_name          = azurerm_storage_container.confluent_data.name
    storage_account_name    = azurerm_storage_account.adls.name
  }

  # Ensure Azure integration and storage resources are ready before creating Tableflow topic
  depends_on = [
    confluent_provider_integration_authorization.azure,
    azurerm_storage_account.adls,
    azurerm_storage_container.confluent_data,
    azurerm_role_assignment.blob_contributor,
    azurerm_role_assignment.reader,
    azuread_service_principal.confluent,
    confluent_connector.datagen_stocks,
    confluent_role_binding.tableflow_environment_admin
  ]
}
