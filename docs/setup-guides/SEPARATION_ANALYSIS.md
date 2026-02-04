# Terraform & ArgoCD Separation Analysis

## Executive Summary

✅ **GOOD NEWS**: Your codebase separation is **ALMOST COMPLETE** but needs final cleanup.

### Current State

**Terraform (`kubernetes.tf`):**
- ❌ Still contains ALL 5 application Helm releases (ui, catalog, carts, orders, checkout)
- ✅ Manages infrastructure (namespaces, IngressClass, databases, IAM, security groups)
- ⚠️ Will RECREATE applications on next `terraform apply` unless code is removed

**ArgoCD:**
- ✅ Successfully deployed 5 applications (retail-ui, retail-catalog, retail-carts, retail-orders, retail-checkout)
- ✅ Apps are running with 2 replicas each
- ⚠️ Missing infrastructure values (database endpoints, IAM roles, etc.)

**Terraform State:**
- ✅ Application Helm releases removed from state (you ran `terraform state rm`)
- ✅ Terraform won't try to manage existing ArgoCD deployments
- ⚠️ But code still exists, so `terraform plan` shows it will CREATE them

---

## Critical Issue: Duplicate Deployment Risk

### The Problem

You have this in `kubernetes.tf` (lines 83-243):

```terraform
resource "helm_release" "catalog" {
  name       = "catalog"
  repository = "oci://public.ecr.aws/aws-containers"
  chart      = "retail-store-sample-catalog-chart"
  version    = "1.3.0"
  namespace  = kubernetes_namespace_v1.catalog.metadata[0].name
  values     = [templatefile("${path.module}/values/catalog.yaml", {...})]
}

resource "helm_release" "carts" { ... }
resource "helm_release" "checkout" { ... }
resource "helm_release" "orders" { ... }
resource "helm_release" "ui" { ... }
```

### What Happens If You Run `terraform apply` Now?

```bash
$ terraform plan

Terraform will perform the following actions:

  # helm_release.catalog will be created
  + resource "helm_release" "catalog" {
      + name       = "catalog"
      + namespace  = "catalog"
      ...
    }

  # helm_release.carts will be created
  + resource "helm_release" "carts" { ... }

  # helm_release.checkout will be created
  + resource "helm_release" "checkout" { ... }

  # helm_release.orders will be created
  + resource "helm_release" "orders" { ... }

  # helm_release.ui will be created
  + resource "helm_release" "ui" { ... }

Plan: 5 to add, 0 to change, 0 to destroy.
```

**Result**: Terraform will create NEW Helm releases with name "catalog", "carts", etc., causing:
1. Duplicate deployments (Terraform's "catalog" + ArgoCD's "retail-catalog")
2. Resource conflicts
3. Service routing confusion
4. Wasted resources

---

## Solution: Replace kubernetes.tf

### Step 1: Backup Current File

```bash
cd /Users/kunpil/MyProjects/sample-devops-agent-eks-workshop/terraform/eks/default
cp kubernetes.tf kubernetes.tf.backup
```

### Step 2: Replace with ArgoCD-Compatible Version

```bash
# Replace the file
cp kubernetes.tf.argocd kubernetes.tf
```

### Step 3: Verify Terraform Plan

```bash
terraform plan
```

**Expected Output:**
```
No changes. Your infrastructure matches the configuration.

Terraform has compared your real infrastructure against your configuration
and found no differences, so no changes are needed.
```

**If you see any "will be created" for applications, STOP and investigate.**

---

## Infrastructure Values Missing in ArgoCD Helm Charts

Your ArgoCD Helm charts are using **default/in-memory values** instead of real infrastructure:

### Catalog Service

**Current (ArgoCD):**
```yaml
app:
  persistence:
    provider: in-memory  # ❌ Should be "mysql"
    endpoint: ""         # ❌ Missing RDS endpoint
```

**Should Be (from Terraform):**
```yaml
app:
  persistence:
    provider: mysql
    endpoint: "catalog-db.xxxxx.us-east-1.rds.amazonaws.com:3306"
    secret:
      username: catalog_user
      password: <from-terraform-output>
```

### Carts Service

**Current (ArgoCD):**
```yaml
app:
  persistence:
    provider: in-memory  # ❌ Should be "dynamodb"
    dynamodb:
      tableName: Items   # ❌ Should be actual DynamoDB table name
```

**Should Be (from Terraform):**
```yaml
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/retail-carts-role

app:
  persistence:
    provider: dynamodb
    dynamodb:
      tableName: retail-carts-table  # From Terraform output
```

### Orders Service (CrashLoopBackOff Root Cause!)

**Current (ArgoCD):**
```yaml
app:
  persistence:
    provider: 'in-memory'  # ❌ Should be "postgres"
    endpoint: ''           # ❌ Missing RDS endpoint
    
  messaging:
    provider: 'in-memory'  # ❌ Should be "rabbitmq"
    rabbitmq:
      addresses: []        # ❌ Missing MQ endpoint
```

**Should Be (from Terraform):**
```yaml
app:
  persistence:
    provider: 'postgres'
    endpoint: 'orders-db.xxxxx.us-east-1.rds.amazonaws.com:5432'
    database: 'orders'
    secret:
      username: orders_user
      password: <from-terraform-output>
      
  messaging:
    provider: 'rabbitmq'
    rabbitmq:
      addresses: ["b-xxxxx.mq.us-east-1.amazonaws.com:5671"]
      secret:
        username: admin
        password: <from-terraform-output>
```

**This is why orders is crashing!** It's trying to use in-memory storage but the code expects real databases.

---

## Complete Separation Checklist

### ✅ Already Done

- [x] Removed Terraform Helm releases from state
- [x] Deleted old Terraform-managed `ui` deployment and service
- [x] Updated ingress to point to ArgoCD service `retail-ui`
- [x] ArgoCD apps deployed and running (with 2 replicas)
- [x] Created `kubernetes.tf.argocd` with infrastructure-only code

### ❌ Still Need To Do

- [ ] **Replace `kubernetes.tf` with `kubernetes.tf.argocd`**
- [ ] **Get Terraform infrastructure outputs** (database endpoints, IAM roles, etc.)
- [ ] **Update ArgoCD Helm chart values** with real infrastructure values
- [ ] **Commit and push Helm chart changes** to GitHub
- [ ] **Sync ArgoCD apps** to apply new values
- [ ] **Verify all apps are Healthy** (especially orders)
- [ ] **Run `terraform plan`** to confirm no application resources will be created

---

## Step-by-Step Action Plan

### Phase 1: Replace Terraform Configuration (5 minutes)

```bash
cd /Users/kunpil/MyProjects/sample-devops-agent-eks-workshop/terraform/eks/default

# Backup
cp kubernetes.tf kubernetes.tf.backup

# Replace
cp kubernetes.tf.argocd kubernetes.tf

# Verify
terraform plan
# Should show: "No changes. Your infrastructure matches the configuration."
```

### Phase 2: Get Infrastructure Values (5 minutes)

```bash
# Get all Terraform outputs
terraform output -json > /tmp/terraform-outputs.json

# View outputs
cat /tmp/terraform-outputs.json | jq '.'

# Key outputs needed:
# - catalog_db_endpoint
# - catalog_db_username
# - catalog_db_password
# - carts_dynamodb_table_name
# - carts_iam_role_arn
# - orders_db_endpoint
# - orders_db_username
# - orders_db_password
# - mq_broker_endpoint
# - mq_username
# - mq_password
# - checkout_elasticache_endpoint
```

### Phase 3: Update ArgoCD Helm Charts (15 minutes)

Update each service's `values.yaml` with real infrastructure values:

**File: `helm-charts/catalog/values.yaml`**
```yaml
app:
  persistence:
    provider: mysql
    endpoint: "<catalog-db-endpoint>:3306"
    database: "catalog"
    secret:
      create: true
      name: catalog-db
      username: <catalog-db-username>
      password: "<catalog-db-password>"
```

**File: `helm-charts/carts/values.yaml`**
```yaml
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: <carts-iam-role-arn>

app:
  persistence:
    provider: dynamodb
    dynamodb:
      tableName: <carts-dynamodb-table-name>
      createTable: false
```

**File: `helm-charts/orders/values.yaml`**
```yaml
app:
  persistence:
    provider: 'postgres'
    endpoint: '<orders-db-endpoint>:5432'
    database: 'orders'
    secret:
      create: true
      name: orders-db
      username: <orders-db-username>
      password: "<orders-db-password>"
      
  messaging:
    provider: 'rabbitmq'
    rabbitmq:
      addresses: ["<mq-broker-endpoint>"]
      secret:
        create: true
        name: orders-rabbitmq
        username: <mq-username>
        password: "<mq-password>"
```

**File: `helm-charts/checkout/values.yaml`**
```yaml
app:
  persistence:
    provider: redis
    endpoint: "<checkout-elasticache-endpoint>"
    port: 6379
```

**File: `helm-charts/ui/values.yaml`**
```yaml
app:
  endpoints:
    catalog: http://retail-catalog.catalog.svc:80
    carts: http://retail-carts.carts.svc:80
    orders: http://retail-orders.orders.svc:80
    checkout: http://retail-checkout.checkout.svc:80
```

### Phase 4: Deploy Changes (10 minutes)

```bash
cd /Users/kunpil/MyProjects/sample-devops-agent-eks-workshop

# Commit changes
git add helm-charts/*/values.yaml
git commit -m "Configure Helm charts with Terraform infrastructure values"
git push origin main

# Sync ArgoCD apps
argocd app sync retail-catalog retail-carts retail-orders retail-checkout retail-ui

# Watch sync progress
argocd app wait retail-catalog retail-carts retail-orders retail-checkout retail-ui --health

# Verify all apps are Healthy
argocd app list
```

### Phase 5: Verify (5 minutes)

```bash
# Check all pods are running
kubectl get pods --all-namespaces | grep retail-

# Check orders is no longer crashing
kubectl logs -n orders -l app.kubernetes.io/name=orders --tail=50

# Test application
curl -I http://k8s-argocd-argocdse-0fafe6a2bf-1764938714.us-east-1.elb.amazonaws.com
```

---

## Why This Separation Matters

### Before (Current State)

```
┌─────────────────────────────────────────────────────────────┐
│                        Terraform                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │ Infrastructure│  │ Applications │  │ Observability│     │
│  │   (EKS, RDS) │  │ (Helm Charts)│  │  (Prometheus)│     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
└─────────────────────────────────────────────────────────────┘
                            ↓
                    ❌ PROBLEM:
                    - Terraform manages everything
                    - No GitOps workflow
                    - Hard to update apps
                    - Conflicts with ArgoCD
```

### After (Target State)

```
┌─────────────────────────────────────────────────────────────┐
│                        Terraform                            │
│  ┌──────────────┐  ┌──────────────┐                        │
│  │ Infrastructure│  │ Observability│                        │
│  │   (EKS, RDS) │  │  (Prometheus)│                        │
│  └──────────────┘  └──────────────┘                        │
└─────────────────────────────────────────────────────────────┘
                            ↓
                    Provides: DB endpoints, IAM roles, etc.
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                         ArgoCD                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │   UI App     │  │ Catalog App  │  │  Carts App   │     │
│  │ (Helm Chart) │  │ (Helm Chart) │  │ (Helm Chart) │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
└─────────────────────────────────────────────────────────────┘
                            ↑
                    Syncs from Git
                            ↑
┌─────────────────────────────────────────────────────────────┐
│                         GitHub                              │
│  helm-charts/ui/values.yaml                                 │
│  helm-charts/catalog/values.yaml                            │
│  helm-charts/carts/values.yaml                              │
└─────────────────────────────────────────────────────────────┘

✅ BENEFITS:
- Clear separation of concerns
- GitOps workflow for apps
- Easy app updates via Git
- No Terraform/ArgoCD conflicts
- Infrastructure team owns Terraform
- App team owns Helm charts
```

---

## FAQ

### Q: Will removing Helm releases from Terraform break ArgoCD deployments?

**A: NO.** ArgoCD deployments are completely independent. They only need:
1. Kubernetes namespaces (Terraform creates these)
2. Infrastructure resources (databases, IAM roles - Terraform provides these)
3. Helm charts in Git (you have these)

### Q: What if I run `terraform apply` before replacing kubernetes.tf?

**A: BAD.** Terraform will create duplicate deployments:
- Terraform's "catalog" deployment
- ArgoCD's "retail-catalog" deployment

Both will run simultaneously, causing conflicts.

### Q: Can I keep some apps in Terraform and some in ArgoCD?

**A: NOT RECOMMENDED.** This creates confusion about ownership. Pick one:
- **Option 1**: All apps in ArgoCD (recommended for GitOps)
- **Option 2**: All apps in Terraform (not recommended, no GitOps)

### Q: How do I update applications after this separation?

**A: GitOps workflow:**
1. Edit `helm-charts/*/values.yaml` in Git
2. Commit and push to GitHub
3. ArgoCD automatically syncs and deploys
4. No Terraform changes needed

### Q: What if I need to change infrastructure (add a database)?

**A: Terraform workflow:**
1. Edit Terraform configuration
2. Run `terraform apply`
3. Get new infrastructure outputs
4. Update ArgoCD Helm chart values with new endpoints
5. Commit and push to Git
6. ArgoCD syncs and deploys

---

## Next Steps

1. **Replace kubernetes.tf** (CRITICAL - prevents duplicate deployments)
2. **Get Terraform outputs** (needed for Helm chart values)
3. **Update Helm chart values** (fixes orders CrashLoopBackOff)
4. **Commit and push** (triggers ArgoCD sync)
5. **Verify all apps Healthy** (confirms separation works)

Ready to proceed? Let me know and I'll help you execute each step!
