output "configure_kubectl" {
  description = "Command to update kubeconfig for this cluster"
  value       = module.retail_app_eks.configure_kubectl
}

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = local.cluster_name
}

output "region" {
  description = "AWS region where the cluster is deployed"
  value       = var.region
}

output "retail_app_url" {
  description = "URL to access the retail store application via ALB"
  value = try(
    "http://${data.kubernetes_ingress_v1.ui_ingress.status[0].load_balancer[0].ingress[0].hostname}",
    "ALB provisioning - run: kubectl get ingress -n ui ui"
  )
}

output "alb_logs_bucket" {
  description = "S3 bucket for ALB access logs"
  value       = aws_s3_bucket.alb_logs.id
}

# ============================================================================
# Infrastructure Outputs for ArgoCD Helm Charts
# ============================================================================

# Catalog Database (MySQL/RDS)
output "catalog_db_endpoint" {
  description = "Catalog database endpoint"
  value       = module.dependencies.catalog_db_endpoint
}

output "catalog_db_port" {
  description = "Catalog database port"
  value       = module.dependencies.catalog_db_port
}

output "catalog_db_username" {
  description = "Catalog database username"
  value       = module.dependencies.catalog_db_master_username
  sensitive   = true
}

output "catalog_db_password" {
  description = "Catalog database password"
  value       = module.dependencies.catalog_db_master_password
  sensitive   = true
}

output "catalog_db_name" {
  description = "Catalog database name"
  value       = module.dependencies.catalog_db_database_name
}

# Carts DynamoDB and IAM Role
output "carts_dynamodb_table_name" {
  description = "Carts DynamoDB table name"
  value       = module.dependencies.carts_dynamodb_table_name
}

output "carts_iam_role_arn" {
  description = "IAM role ARN for carts service to access DynamoDB"
  value       = module.iam_assumable_role_carts.iam_role_arn
}

# Orders Database (PostgreSQL/RDS)
output "orders_db_endpoint" {
  description = "Orders database endpoint"
  value       = module.dependencies.orders_db_endpoint
}

output "orders_db_port" {
  description = "Orders database port"
  value       = module.dependencies.orders_db_port
}

output "orders_db_username" {
  description = "Orders database username"
  value       = module.dependencies.orders_db_master_username
  sensitive   = true
}

output "orders_db_password" {
  description = "Orders database password"
  value       = module.dependencies.orders_db_master_password
  sensitive   = true
}

output "orders_db_name" {
  description = "Orders database name"
  value       = module.dependencies.orders_db_database_name
}

# RabbitMQ (Amazon MQ)
output "mq_broker_endpoint" {
  description = "RabbitMQ broker endpoint"
  value       = module.dependencies.mq_broker_endpoint
}

output "mq_username" {
  description = "RabbitMQ username"
  value       = module.dependencies.mq_user
}

output "mq_password" {
  description = "RabbitMQ password"
  value       = module.dependencies.mq_password
  sensitive   = true
}

# Checkout ElastiCache (Redis)
output "checkout_elasticache_endpoint" {
  description = "Checkout Redis endpoint"
  value       = module.dependencies.checkout_elasticache_primary_endpoint
}

output "checkout_elasticache_port" {
  description = "Checkout Redis port"
  value       = module.dependencies.checkout_elasticache_port
}
