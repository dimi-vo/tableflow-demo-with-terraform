# Tableflow Demo

This is a collection of few terraform scripts that will

* Create a basic cluster on Confluent Cloud
* Create a topic in that cluster
* Create the DataGen connector that will produce dummy data to that topic
* Create a container in ADLS
* Create the Provider Integration between Confluent Cloud and Azure
* Enable Tableflow for that topic

What is not covered

* No catalog syncing
* No creation of resources on Databricks, Snowflake or any other analytics engine

## How to run

1. Create a `terraform.tfvars` file. See [terraform.tfvars.example](terraform.tfvars.example) to understand what information you have to provide.
2. Create the plan`terraform plan -out=planned.tfplan`
3. Check the plan
4. Apply the plan `terraform apply "planned.tfplan"`
5. Check that data is generated and Tableflow syncing works
6. Wait a few minutes after the resources have been created for the data to be flushed.

### Prerequisites

The following information is required.

```tf
prefix = "your-prefix"

cc_region = "germanywestcentral"

# Azure
azure_tenant_id = "00000000-0000-0000-0000-000000000000"
subscription_id = "00000000-0000-0000-0000-000000000000"

# Confluent Cloud
confluent_cloud_api_key    = "API_KEY_HERE"
confluent_cloud_api_secret = "API_SECRET_HERE"
```
