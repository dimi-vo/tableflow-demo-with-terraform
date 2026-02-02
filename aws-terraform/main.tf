# Create new environment
resource "confluent_environment" "staging" {
  display_name = "${var.prefix}-tf"

  stream_governance {
    package = "ESSENTIALS"
  }
}

# Get reference of Schema Registry Cluster
data "confluent_schema_registry_cluster" "sr-cluster" {
  environment {
    id = confluent_environment.staging.id
  }

  depends_on = [
    confluent_kafka_cluster.standard
  ]
}

# Create standard Cluster
resource "confluent_kafka_cluster" "standard" {
  display_name = "${var.prefix}-cluster"
  availability = "SINGLE_ZONE"
  cloud        = var.cloud_provider
  region       = var.cc_region
  standard {}
  environment {
    id = confluent_environment.staging.id
  }
}

# Create an SA to manage the cluster
resource "confluent_service_account" "app-manager" {
  display_name = "${var.prefix}-app-manager"
  description  = "Service account to manage Kafka cluster"
}

# Role Binding for interacting with the Kafka cluster
resource "confluent_role_binding" "app-manager-kafka-cluster-admin" {
  principal   = "User:${confluent_service_account.app-manager.id}"
  role_name   = "CloudClusterAdmin"
  crn_pattern = confluent_kafka_cluster.standard.rbac_crn
}

# Role binding for managing the provider integration
resource "confluent_role_binding" "app-manager-provider-integration-resource-owner" {
  principal = "User:${confluent_service_account.app-manager.id}"
  role_name = "ResourceOwner"
  // TODO: add resource_name attribute to confluent_provider_integration
  crn_pattern = "${confluent_environment.staging.resource_name}/provider-integration=${confluent_provider_integration.main.id}"
}

# Confluent API Key for the app-manager SA
resource "confluent_api_key" "app-manager-kafka-api-key" {
  display_name = "${var.prefix}-app-manager-kafka-api-key"
  description  = "Kafka API Key that is owned by 'app-manager' service account"
  owner {
    id          = confluent_service_account.app-manager.id
    api_version = confluent_service_account.app-manager.api_version
    kind        = confluent_service_account.app-manager.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.standard.id
    api_version = confluent_kafka_cluster.standard.api_version
    kind        = confluent_kafka_cluster.standard.kind

    environment {
      id = confluent_environment.staging.id
    }
  }

  depends_on = [
    confluent_role_binding.app-manager-kafka-cluster-admin
  ]
}

# Create the purchase topic
resource "confluent_kafka_topic" "purchase" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  topic_name    = "purchase"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-kafka-api-key.id
    secret = confluent_api_key.app-manager-kafka-api-key.secret
  }
}

# SA for the producer - This way we can produce via the CLI
resource "confluent_service_account" "app-producer" {
  display_name = "${var.prefix}-app-producer"
  description  = "Service account to produce to 'purchase' topic of 'inventory' Kafka cluster"
}

# API Key for the producer SA
resource "confluent_api_key" "app-producer-kafka-api-key" {
  display_name = "${var.prefix}-app-producer-kafka-api-key"
  description  = "Kafka API Key that is owned by 'app-producer' service account"
  owner {
    id          = confluent_service_account.app-producer.id
    api_version = confluent_service_account.app-producer.api_version
    kind        = confluent_service_account.app-producer.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.standard.id
    api_version = confluent_kafka_cluster.standard.api_version
    kind        = confluent_kafka_cluster.standard.kind

    environment {
      id = confluent_environment.staging.id
    }
  }
}

# Manage access via ACLs
resource "confluent_kafka_acl" "app-producer-write-on-topic" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  resource_type = "TOPIC"
  resource_name = confluent_kafka_topic.purchase.topic_name
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app-producer.id}"
  host          = "*"
  operation     = "WRITE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-kafka-api-key.id
    secret = confluent_api_key.app-manager-kafka-api-key.secret
  }
}

# SA for managing the environment. Needed to create the schema
resource "confluent_service_account" "env-manager" {
  display_name = "${var.prefix}-env-manager"
  description  = "Service account to manage 'Staging' environment"
}

# Grant Environment Admin role to the SA
resource "confluent_role_binding" "env-manager-environment-admin" {
  principal   = "User:${confluent_service_account.env-manager.id}"
  role_name   = "EnvironmentAdmin"
  crn_pattern = confluent_environment.staging.resource_name
}

# Create API Key for the env-manager SA
resource "confluent_api_key" "env-manager-schema-registry-api-key" {
  display_name = "${var.prefix}-env-manager-schema-registry-api-key"
  description  = "Schema Registry API Key that is owned by 'env-manager' service account"
  owner {
    id          = confluent_service_account.env-manager.id
    api_version = confluent_service_account.env-manager.api_version
    kind        = confluent_service_account.env-manager.kind
  }

  managed_resource {
    id          = data.confluent_schema_registry_cluster.sr-cluster.id
    api_version = data.confluent_schema_registry_cluster.sr-cluster.api_version
    kind        = data.confluent_schema_registry_cluster.sr-cluster.kind

    environment {
      id = confluent_environment.staging.id
    }
  }

  depends_on = [
    confluent_role_binding.env-manager-environment-admin
  ]
}

# API Key for creating Tableflow topics. Assumed by the app-manager SA
resource "confluent_api_key" "app-manager-tableflow-api-key" {
  display_name = "${var.prefix}-app-manager-tableflow-api-key"
  description  = "Tableflow API Key that is owned by 'app-manager' service account"
  owner {
    id          = confluent_service_account.app-manager.id
    api_version = confluent_service_account.app-manager.api_version
    kind        = confluent_service_account.app-manager.kind
  }

  managed_resource {
    id          = "tableflow"
    api_version = "tableflow/v1"
    kind        = "Tableflow"

    environment {
      id = confluent_environment.staging.id
    }
  }

  depends_on = [
    confluent_role_binding.app-manager-provider-integration-resource-owner,
  ]
}


# SA for the query engine
resource "confluent_service_account" "trino" {
  display_name = "${var.prefix}-trino-query-engine"
  description  = "Service account to query the Iceberg tables with Trino"
}

# Grant Environment Admin role to the SA
resource "confluent_role_binding" "trino-developer-read-topics" {
  principal   = "User:${confluent_service_account.trino.id}"
  role_name   = "DeveloperRead"
  crn_pattern = "${confluent_kafka_cluster.standard.rbac_crn}/kafka=${confluent_kafka_cluster.standard.id}/topic=${confluent_kafka_topic.purchase.topic_name}"
}
# Grant Environment Admin role to the SA
resource "confluent_role_binding" "trino-developer-read-schemas" {
  principal   = "User:${confluent_service_account.trino.id}"
  role_name   = "DeveloperRead"
  crn_pattern = "${data.confluent_schema_registry_cluster.sr-cluster.resource_name}/subject=*"

}

# API Key for querying Tableflow topics
resource "confluent_api_key" "trino-tableflow-api-key" {
  display_name = "${var.prefix}-trino-tableflow-api-key"
  description  = "Tableflow API Key that is owned by 'trino' service account"
  owner {
    id          = confluent_service_account.trino.id
    api_version = confluent_service_account.trino.api_version
    kind        = confluent_service_account.trino.kind
  }

  managed_resource {
    id          = "tableflow"
    api_version = "tableflow/v1"
    kind        = "Tableflow"

    environment {
      id = confluent_environment.staging.id
    }
  }

  depends_on = [
    confluent_role_binding.trino-developer-read-schemas,
    confluent_role_binding.trino-developer-read-topics
  ]
}

# Define which topic needs to be synced to Tableflow
resource "confluent_tableflow_topic" "purchase" {
  environment {
    id = confluent_environment.staging.id
  }
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  display_name = confluent_kafka_topic.purchase.topic_name
  # Write both formats
  table_formats = var.tableflow_table_format

  // Use BYOB AWS storage
  byob_aws {
    bucket_name             = var.bucket_name
    provider_integration_id = confluent_provider_integration.main.id
  }

  credentials {
    key    = confluent_api_key.app-manager-tableflow-api-key.id
    secret = confluent_api_key.app-manager-tableflow-api-key.secret
  }

  depends_on = [
    confluent_connector.source,
    module.s3_access_role,
  ]
}

data "aws_caller_identity" "current" {}

locals {
  customer_s3_access_role_name = "ConfluentTableflowS3AccessRole"
  customer_s3_access_role_arn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.customer_s3_access_role_name}"
}

resource "confluent_provider_integration" "main" {
  display_name = "${var.prefix}-s3_tableflow_integration"
  environment {
    id = confluent_environment.staging.id
  }
  aws {
    # During the creation of confluent_provider_integration.main, the S3 role does not yet exist.
    # The role will be created after confluent_provider_integration.main is provisioned
    # by the s3_access_role module using the specified target name.
    # Note: This is a workaround to avoid updating an existing role or creating a circular dependency.
    customer_role_arn = local.customer_s3_access_role_arn
  }
}

module "s3_access_role" {
  source                           = "./iam_role_module"
  s3_bucket_name                   = var.bucket_name
  provider_integration_role_arn    = confluent_provider_integration.main.aws[0].iam_role_arn
  provider_integration_external_id = confluent_provider_integration.main.aws[0].external_id
  customer_role_name               = local.customer_s3_access_role_name
}

# Create the service account for the DataGen Connector
resource "confluent_service_account" "app-connector" {
  display_name = "${var.prefix}-SA-datagen-connector"
  description  = "Service account of S3 Sink Connector to consume from 'purchase' topic of 'inventory' Kafka cluster"
}

resource "confluent_kafka_acl" "app-connector-describe-on-cluster" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  resource_type = "CLUSTER"
  resource_name = "kafka-cluster"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app-connector.id}"
  host          = "*"
  operation     = "DESCRIBE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-kafka-api-key.id
    secret = confluent_api_key.app-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "app-connector-write-on-target-topic" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  resource_type = "TOPIC"
  resource_name = confluent_kafka_topic.purchase.topic_name
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app-connector.id}"
  host          = "*"
  operation     = "WRITE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-kafka-api-key.id
    secret = confluent_api_key.app-manager-kafka-api-key.secret
  }
}

resource "confluent_connector" "source" {
  environment {
    id = confluent_environment.staging.id
  }
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }

  // Block for custom *sensitive* configuration properties that are labelled with "Type: password" under "Configuration Properties" section in the docs:
  // https://docs.confluent.io/cloud/current/connectors/cc-datagen-source.html#configuration-properties
  config_sensitive = {}

  // Block for custom *nonsensitive* configuration properties that are *not* labelled with "Type: password" under "Configuration Properties" section in the docs:
  // https://docs.confluent.io/cloud/current/connectors/cc-datagen-source.html#configuration-properties
  config_nonsensitive = {
    "connector.class"          = "DatagenSource"
    "name"                     = "DatagenSourceConnector_0"
    "kafka.auth.mode"          = "SERVICE_ACCOUNT"
    "kafka.service.account.id" = confluent_service_account.app-connector.id
    "kafka.topic"              = confluent_kafka_topic.purchase.topic_name
    "output.data.format"       = "AVRO"
    "quickstart"               = "PURCHASES"
    "tasks.max"                = "1"
  }

  depends_on = [
    confluent_kafka_acl.app-connector-describe-on-cluster,
    confluent_kafka_acl.app-connector-write-on-target-topic
  ]
}

data "confluent_organization" "main" {}


# Replace with your actual IAM username
resource "aws_iam_access_key" "my_user_key" {
  user = "${var.iam-username}"
}