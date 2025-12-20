# Tableflow Demo

This is a collection of few terraform scripts that will

* Create a basic cluster on Confluent Cloud
* Create a topic in that cluster
* Create the DataGen connector that will produce dummy data to that topic
* Create an S3 bucket in AWS
* Create the Provider Integration between Confluent Cloud and the S3 bucket
* Enable Tableflow for that topic
* Provide the commands to run queries with Trino deployed in Docker against Confluent's Iceberg REST Catalog

What is not covered

* No catalog syncing
* No creation of resources on Databricks, Snowflake or any other analytics engine

## How to run

1. Create a `terraform.tfvars` file. See [terraform.demo-tfvars](terraform.demo-tfvars) to understand what information you have to provide.
2. Create the plan`terraform plan -out=planned.tfplan`
3. Check the plan
4. Apply the plan `terraform apply "planned.tfplan"`
5. Check that data is generated and Tableflow syncing works
6. Wait ca. 15 minutes after the resources have been created for Tableflow to flush the data.
7. Run `terraform output resource-ids` and follow the instructions

The output of the query should be similar to the following

![alt text](image.png)
