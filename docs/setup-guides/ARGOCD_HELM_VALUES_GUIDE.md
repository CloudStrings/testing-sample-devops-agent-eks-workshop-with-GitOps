# ArgoCD Helm Values Configuration Guide

## What ArgoCD Needs from Terraform

ArgoCD applications need access to infrastructure resources created by Terraform. Here's what each service requires:

### 1. Catalog Service
**Needs:**
- ✅ Namespace: `catalog` (Terraform creates)
- ✅ MySQL Database endpoint & credentials (Terraform creates)
- ✅ Security group for database access (Terraform creates)

**Your Helm Chart Must Configure:**
```yaml
# helm-charts/catalog/values.yaml
app:
  persistence:
    provider: mysql
    endpoint: "<RDS_ENDPOINT>:3306"  # Get from Terraform output
    secret:
      username: "<DB_USERNAME>"       # Get from Terraform output
      password: "<DB_PASSWORD>"       # Get from Terraform output
```

### 2. Carts Service
**Needs:**
- ✅ Namespace: `carts` (Terraform creates)
- ✅ DynamoDB table (Terraform creates)
- ✅ IAM role for service account (Terraform creates)

**Your Helm Chart Must Configure:**
```yaml
# helm-charts/carts/values.yaml
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: "<CARTS_IAM_ROLE_ARN>"  # Get from Terraform

app:
  persistence:
    provider: dynamodb
    dynamodb:
      tableName: "<DYNAMODB_TABLE_NAME>"  # Get from Terraform output
```

### 3. Orders Service
**Needs:**
- ✅ Namespace: `orders` (Terraform creates)
- ✅ PostgreSQL RDS endpoint & credentials (Terraform creates)
- ✅ RabbitMQ (Amazon MQ) endpoint & credentials (Terraform creates)
- ✅ Security group for database access (Terraform creates)

**Your Helm Chart Must Configure:**
```yaml
# helm-charts/orders/values.yaml
app:
  database:
    endpoint: "<RDS_ENDPOINT>:<PORT>"
    name: "<DB_NAME>"
    username: "<DB_USERNAME>"
    password: "<DB_PASSWORD>"
  
  rabbitmq:
    endpoint: "<MQ_ENDPOINT>"
    username: "<MQ_USERNAME>"
    password: "<MQ_PASSWORD>"
```

### 4. Checkout Service
**Needs:**
- ✅ Namespace: `checkout` (Terraform creates)
- ✅ ElastiCache Redis endpoint (Terraform creates)
- ✅ Security group for Redis access (Terraform creates)

**Your Helm Chart Must Configure:**
```yaml
# helm-charts/checkout/values.yaml
app:
  persistence:
    provider: redis
    redis:
      endpoint: "<ELASTICACHE_ENDPOINT>:6379"  # Get from Terraform output
```

### 5. UI Service
**Needs:**
- ✅ Namespace: `ui` (Terraform creates)
- ✅ IngressClass for ALB (Terraform creates)
- ✅ S3 bucket for ALB logs (Terraform creates)
- ✅ Backend service endpoints (catalog, carts, orders, checkout)

**Your Helm Chart Must Configure:**
```yaml
# helm-charts/ui/values.yaml
app:
  endpoints:
    catalog: http://retail-catalog.catalog.svc:80   # ArgoCD service name
    carts: http://retail-carts.carts.svc:80         # ArgoCD service name
    orders: http://retail-orders.orders.svc:80      # ArgoCD service name
    checkout: http://retail-checkout.checkout.svc:80 # ArgoCD service name

ingress:
  enabled: true
  className: alb  # Terraform creates this IngressClass
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/load-balancer-attributes: access_logs.s3.enabled=true,access_logs.s3.bucket=<S3_BUCKET>,access_logs.s3.prefix=ui-alb
```

---

## How to Get Terraform Outputs for ArgoCD

Run these commands to get the values you need:

```bash
cd /Users/kunpil/MyProjects/sample-devops-agent-eks-workshop/terraform/eks/default

# Get all outputs
terraform output

# Get specific values
terraform output -raw catalog_db_endpoint
terraform output -raw catalog_db_username
terraform output -raw catalog_db_password

terraform output -raw orders_db_endpoint
terraform output -raw orders_db_username
terraform output -raw orders_db_password

terraform output -raw carts_dynamodb_table_name
terraform output -raw carts_iam_role_arn

terraform output -raw checkout_redis_endpoint

terraform output -raw mq_broker_endpoint
terraform output -raw mq_username
terraform output -raw mq_password

terraform output -raw alb_logs_bucket
```

---

## Option 1: Manual Configuration (Current State)

Update each Helm chart's `values.yaml` with Terraform outputs:

```bash
cd /Users/kunpil/MyProjects/sample-devops-agent-eks-workshop

# Edit each values file
vim helm-charts/catalog/values.yaml
vim helm-charts/carts/values.yaml
vim helm-charts/orders/values.yaml
vim helm-charts/checkout/values.yaml
vim helm-charts/ui/values.yaml

# Commit and push
git add helm-charts/*/values.yaml
git commit -m "Configure Helm charts with Terraform infrastructure values"
git push origin main

# Sync ArgoCD
argocd app sync retail-catalog retail-carts retail-orders retail-checkout retail-ui
```

---

## Option 2: Use Kubernetes Secrets (Recommended for Sensitive Data)

Create Kubernetes secrets from Terraform outputs, then reference them in Helm charts:

```bash
# Create secrets for each service
kubectl create secret generic catalog-db-credentials \
  -n catalog \
  --from-literal=endpoint=$(terraform output -raw catalog_db_endpoint) \
  --from-literal=username=$(terraform output -raw catalog_db_username) \
  --from-literal=password=$(terraform output -raw catalog_db_password)

kubectl create secret generic orders-db-credentials \
  -n orders \
  --from-literal=endpoint=$(terraform output -raw orders_db_endpoint) \
  --from-literal=username=$(terraform output -raw orders_db_username) \
  --from-literal=password=$(terraform output -raw orders_db_password)

kubectl create secret generic orders-mq-credentials \
  -n orders \
  --from-literal=endpoint=$(terraform output -raw mq_broker_endpoint) \
  --from-literal=username=$(terraform output -raw mq_username) \
  --from-literal=password=$(terraform output -raw mq_password)

kubectl create secret generic checkout-redis-config \
  -n checkout \
  --from-literal=endpoint=$(terraform output -raw checkout_redis_endpoint)
```

Then update Helm charts to use secrets:

```yaml
# helm-charts/catalog/values.yaml
app:
  persistence:
    provider: mysql
    endpoint:
      valueFrom:
        secretKeyRef:
          name: catalog-db-credentials
          key: endpoint
```

---

## Option 3: Terraform Creates Secrets (Best Practice)

Add to your `kubernetes.tf`:

```terraform
# Create Kubernetes secrets for ArgoCD-managed apps
resource "kubernetes_secret_v1" "catalog_db" {
  metadata {
    name      = "catalog-db-credentials"
    namespace = kubernetes_namespace_v1.catalog.metadata[0].name
  }

  data = {
    endpoint = "${module.dependencies.catalog_db_endpoint}:${module.dependencies.catalog_db_port}"
    username = module.dependencies.catalog_db_master_username
    password = module.dependencies.catalog_db_master_password
  }

  type = "Opaque"
}

resource "kubernetes_secret_v1" "orders_db" {
  metadata {
    name      = "orders-db-credentials"
    namespace = kubernetes_namespace_v1.orders.metadata[0].name
  }

  data = {
    endpoint = "${module.dependencies.orders_db_endpoint}:${module.dependencies.orders_db_port}"
    database = module.dependencies.orders_db_database_name
    username = module.dependencies.orders_db_master_username
    password = module.dependencies.orders_db_master_password
  }

  type = "Opaque"
}

resource "kubernetes_secret_v1" "orders_mq" {
  metadata {
    name      = "orders-mq-credentials"
    namespace = kubernetes_namespace_v1.orders.metadata[0].name
  }

  data = {
    endpoint = module.dependencies.mq_broker_endpoint
    username = module.dependencies.mq_user
    password = module.dependencies.mq_password
  }

  type = "Opaque"
}

resource "kubernetes_secret_v1" "checkout_redis" {
  metadata {
    name      = "checkout-redis-config"
    namespace = kubernetes_namespace_v1.checkout.metadata[0].name
  }

  data = {
    endpoint = "${module.dependencies.checkout_elasticache_primary_endpoint}:${module.dependencies.checkout_elasticache_port}"
  }

  type = "Opaque"
}

resource "kubernetes_config_map_v1" "carts_dynamodb" {
  metadata {
    name      = "carts-dynamodb-config"
    namespace = kubernetes_namespace_v1.carts.metadata[0].name
  }

  data = {
    tableName = module.dependencies.carts_dynamodb_table_name
  }
}
```

---

## Summary: What Terraform Manages vs ArgoCD

### Terraform Manages (Infrastructure):
- ✅ EKS cluster
- ✅ VPC, subnets, security groups
- ✅ RDS databases (catalog, orders)
- ✅ DynamoDB table (carts)
- ✅ ElastiCache Redis (checkout)
- ✅ Amazon MQ (orders)
- ✅ IAM roles for service accounts
- ✅ Kubernetes namespaces
- ✅ IngressClass configuration
- ✅ **Kubernetes secrets with infrastructure credentials** (Option 3)

### ArgoCD Manages (Applications):
- ✅ Application deployments
- ✅ Application services
- ✅ Application ConfigMaps (app-level config)
- ✅ Ingress resources
- ✅ HPA (Horizontal Pod Autoscaler)
- ✅ PDB (Pod Disruption Budget)

### Shared Responsibility:
- **Secrets**: Can be managed by either Terraform (infrastructure credentials) or ArgoCD (application secrets)
- **ConfigMaps**: Infrastructure config (Terraform) vs application config (ArgoCD)

---

## Next Steps

1. ✅ Replace `kubernetes.tf` with the ArgoCD-compatible version
2. ✅ Add Kubernetes secret resources to Terraform (Option 3 - recommended)
3. ✅ Update Helm charts to reference secrets
4. ✅ Run `terraform plan` to verify no application Helm releases
5. ✅ Run `terraform apply` to create secrets
6. ✅ Sync ArgoCD apps
7. ✅ Verify all pods are running and healthy
