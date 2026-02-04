# Cleanup Guide: Remove Terraform-Managed Applications

## Current State Analysis

You have **DUPLICATE DEPLOYMENTS** running:

### Terraform-Managed (11 days old):
- `ui` deployment (was 2 replicas) - **DELETED** ✅
- `catalog` deployment (2 replicas, 0 ready) ❌
- `carts` deployment (2 replicas) ❌
- `orders` deployment (2 replicas, 0 ready) ❌
- `checkout` deployment (2 replicas) ❌

### ArgoCD-Managed (10 days old):
- `retail-ui` deployment (1 replica) ✅
- `retail-catalog` deployment (1 replica) ✅
- `retail-carts` deployment (1 replica) ✅
- `retail-orders` deployment (1 replica) ✅
- `retail-checkout` deployment (1 replica) ✅

## Problem

Both Terraform and ArgoCD are managing the same applications, causing:
1. Resource conflicts
2. Duplicate pods consuming resources
3. Service routing confusion
4. Inconsistent replica counts

## Solution: Clean Separation

**Terraform manages**: Infrastructure (EKS, VPC, RDS, DynamoDB, ElastiCache, etc.)
**ArgoCD manages**: Applications (UI, Catalog, Carts, Orders, Checkout)

---

## Step 1: Delete Terraform-Managed Application Resources

### Option A: Delete via kubectl (Recommended - Faster)

```bash
# Delete all Terraform-managed application deployments
kubectl delete deployment catalog -n catalog
kubectl delete deployment carts -n carts
kubectl delete deployment orders -n orders
kubectl delete deployment checkout -n checkout

# Delete all Terraform-managed services
kubectl delete service catalog -n catalog
kubectl delete service carts -n carts
kubectl delete service orders -n orders
kubectl delete service checkout -n checkout

# Verify deletion
kubectl get deployments,services -n catalog -n carts -n orders -n checkout
```

### Option B: Remove from Terraform State (Cleaner - Prevents re-creation)

This tells Terraform to stop managing these resources without deleting them:

```bash
cd /Users/kunpil/MyProjects/sample-devops-agent-eks-workshop/terraform/eks/default

# List all Terraform-managed resources
terraform state list | grep -E "helm_release|kubernetes_"

# Remove application Helm releases from Terraform state
terraform state rm 'module.eks_blueprints_addons.helm_release.this["retail-store-sample-app"]'

# Or remove individual Kubernetes resources if they exist
terraform state rm 'kubernetes_deployment.catalog'
terraform state rm 'kubernetes_deployment.carts'
terraform state rm 'kubernetes_deployment.orders'
terraform state rm 'kubernetes_deployment.checkout'
```

Then delete the resources:
```bash
kubectl delete deployment,service catalog -n catalog
kubectl delete deployment,service carts -n carts
kubectl delete deployment,service orders -n orders
kubectl delete deployment,service checkout -n checkout
```

---

## Step 2: Update Ingress to Point to ArgoCD Services

You already fixed the UI ingress. Now check if other services have ingresses:

```bash
# Check all ingresses
kubectl get ingress --all-namespaces

# If there are ingresses for other services, update them
kubectl patch ingress <ingress-name> -n <namespace> --type='json' \
  -p='[{"op": "replace", "path": "/spec/rules/0/http/paths/0/backend/service/name", "value":"retail-<service>"}]'
```

---

## Step 3: Scale Up ArgoCD-Managed Applications

Your ArgoCD apps are running with only 1 replica. Let's increase them for production readiness:

```bash
cd /Users/kunpil/MyProjects/sample-devops-agent-eks-workshop
```

### Update Helm Chart Values

Edit each service's `values.yaml`:

```bash
# UI
vim helm-charts/ui/values.yaml
# Change: replicaCount: 1 → replicaCount: 2

# Catalog
vim helm-charts/catalog/values.yaml
# Change: replicaCount: 1 → replicaCount: 2

# Carts
vim helm-charts/carts/values.yaml
# Change: replicaCount: 1 → replicaCount: 2

# Orders
vim helm-charts/orders/values.yaml
# Change: replicaCount: 1 → replicaCount: 2

# Checkout
vim helm-charts/checkout/values.yaml
# Change: replicaCount: 1 → replicaCount: 2
```

### Commit and Push Changes

```bash
git add helm-charts/*/values.yaml
git commit -m "Scale applications to 2 replicas for HA"
git push origin main
```

### Sync ArgoCD Apps

```bash
# Sync all apps to apply new replica counts
argocd app sync retail-ui retail-catalog retail-carts retail-orders retail-checkout

# Watch the sync progress
argocd app wait retail-ui retail-catalog retail-carts retail-orders retail-checkout --health
```

---

## Step 4: Verify Clean State

```bash
# Check deployments - should only see retail-* versions
kubectl get deployments --all-namespaces | grep -E "ui|catalog|carts|orders|checkout"

# Check services - should only see retail-* versions
kubectl get services --all-namespaces | grep -E "ui|catalog|carts|orders|checkout"

# Check replica counts - should all be 2/2
kubectl get deployments -n ui -n catalog -n carts -n orders -n checkout

# Check ArgoCD app status - should all be Synced and Healthy
argocd app list
```

Expected output:
```
NAME                      CLUSTER                         NAMESPACE  PROJECT  STATUS  HEALTH   SYNCPOLICY  CONDITIONS
argocd/retail-ui          https://kubernetes.default.svc  ui         default  Synced  Healthy  Auto-Prune  <none>
argocd/retail-catalog     https://kubernetes.default.svc  catalog    default  Synced  Healthy  Auto-Prune  <none>
argocd/retail-carts       https://kubernetes.default.svc  carts      default  Synced  Healthy  Auto-Prune  <none>
argocd/retail-orders      https://kubernetes.default.svc  orders     default  Synced  Healthy  Auto-Prune  <none>
argocd/retail-checkout    https://kubernetes.default.svc  checkout   default  Synced  Healthy  Auto-Prune  <none>
```

---

## Step 5: Fix Orders Service (CrashLoopBackOff)

The orders service is crashing. Let's investigate:

```bash
# Check orders pod logs
kubectl logs -n orders -l app.kubernetes.io/name=orders --tail=100

# Check orders pod events
kubectl describe pod -n orders -l app.kubernetes.io/name=orders

# Common issues:
# 1. Database connection failure (RDS/PostgreSQL)
# 2. RabbitMQ connection failure
# 3. Missing environment variables
```

Check if the database and RabbitMQ are accessible:

```bash
# Check if PostgreSQL StatefulSet is running
kubectl get statefulset -n orders

# Check if RabbitMQ StatefulSet is running
kubectl get statefulset -n orders

# Check security groups allow pod-to-database communication
```

---

## Step 6: Prevent Terraform from Re-creating Apps

To ensure Terraform doesn't try to recreate the applications on next `terraform apply`:

### Option 1: Comment out application deployment in Terraform

Edit your Terraform configuration:

```bash
cd /Users/kunpil/MyProjects/sample-devops-agent-eks-workshop/terraform/eks/default
```

Find and comment out the Helm release for the retail store app (likely in `main.tf` or a separate file).

### Option 2: Use Terraform variables to disable app deployment

If the Terraform module has a variable to control app deployment, set it to false:

```hcl
# In terraform.tfvars
deploy_sample_app = false
```

---

## Summary

After cleanup, you should have:

✅ **Terraform manages**:
- EKS cluster
- VPC, subnets, security groups
- RDS databases
- DynamoDB tables
- ElastiCache Redis
- Amazon MQ
- IAM roles
- CloudWatch logs
- Observability stack

✅ **ArgoCD manages**:
- UI deployment (2 replicas)
- Catalog deployment (2 replicas)
- Carts deployment (2 replicas)
- Orders deployment (2 replicas)
- Checkout deployment (2 replicas)
- All Kubernetes services
- ConfigMaps and Secrets (application-level)

✅ **Benefits**:
- No duplicate resources
- Clear ownership boundaries
- GitOps workflow for applications
- Infrastructure as Code for infrastructure
- Easy rollbacks via Git
- Automated sync with ArgoCD

---

## Troubleshooting

### Issue: ArgoCD apps show "OutOfSync"
```bash
argocd app sync <app-name> --force
```

### Issue: Pods not starting after scaling
```bash
kubectl describe pod -n <namespace> <pod-name>
kubectl logs -n <namespace> <pod-name>
```

### Issue: Terraform tries to recreate apps
```bash
# Remove from state
terraform state rm <resource>

# Or comment out in Terraform code
```

### Issue: Service endpoints empty
```bash
kubectl get endpoints -n <namespace>
# If empty, check if pods are ready and have correct labels
```

---

## Next Steps

1. ✅ Delete Terraform-managed app resources
2. ✅ Scale ArgoCD apps to 2 replicas
3. ✅ Fix orders service crash
4. ✅ Verify all apps are Synced and Healthy
5. ✅ Test application end-to-end
6. ✅ Document the GitOps workflow for your team
