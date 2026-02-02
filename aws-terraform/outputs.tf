output "resource-ids" {
  value = <<-EOT
  Environment ID:   ${confluent_environment.staging.id}
  Kafka Cluster ID: ${confluent_kafka_cluster.standard.id}

  Use the following properties to set up the Trino query engine.
  Update the tableflow.properties file with:

connector.name=iceberg
iceberg.catalog.type=rest
iceberg.rest-catalog.oauth2.credential=${confluent_api_key.trino-tableflow-api-key.id}:${confluent_api_key.trino-tableflow-api-key.secret}
iceberg.rest-catalog.security=OAUTH2
iceberg.rest-catalog.uri=https://tableflow.${var.cc_region}.aws.confluent.cloud/iceberg/catalog/organizations/${data.confluent_organization.main.id}/environments/${confluent_environment.staging.id}
iceberg.rest-catalog.vended-credentials-enabled=true
fs.native-s3.enabled=true
s3.region=${var.customer_region}
iceberg.security=read_only

  Then start the trino container

docker run -d \
  --name trino \
  -p 8080:8080 \
  -v $PWD:/etc/trino/catalog \
  -e AWS_PROFILE=default \
  -e AWS_REGION=${var.customer_region} \
  -e AWS_ACCESS_KEY_ID=${aws_iam_access_key.my_user_key.id} \
  -e AWS_SECRET_ACCESS_KEY=${aws_iam_access_key.my_user_key.secret} \
  trinodb/trino

  # Exec into the container
docker exec -it trino trino

  # Query the data
SELECT * FROM tableflow."${confluent_kafka_cluster.standard.id}".${confluent_kafka_topic.purchase.topic_name};

  EOT

  sensitive = true
}
