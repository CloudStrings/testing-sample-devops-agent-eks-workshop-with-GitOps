# Terraform & ArgoCD Separation Plan

## Current State ❌

**Terraform is managing BOTH infrastructure AND applications:**

### Infrastructure (✅ Should stay in Terraform):
- EKS cluster
- VPC, subnets, security groups
- RDS databases (catalog, orders)
- DynamoDB (carts)
- ElastiCache Redis (checkout)
- Amazon MQ (orders)
- IAM roles
- CloudWatch observability

### Applications (❌ Should move to ArgoCD):
- `helm_release.ui` - UI service
- `helm_release.catalog` - Catalog service
- `helm_release.carts` - Carts service
- `helm_release.orders` - Orders service
- `helm_release.checkout` - Checkout service

**File:** `sample-devops-agent-eks-workshop/terraform/eks/default/kubernetes.tf`

---

## Target State ✅

### Terraform Manages:
- All infrastructure resources
- Kubernetes namespaces (empty, for RBAC/policies)
- IngressClass configuration
- Security groups

### ArgoCD Manages:
- All application Helm releases
- Application deployments
- Application services
- Application ConfigMaps/Secrets

---

## Migration Steps

### Step 1: Remove Application Helm Releases from Terraform State

This tells Terraform to stop managing these resources WITHOUT deleting them:

```bash
cd /Users/kunpil/MyProjects/sample-devops-agent-eks-workshop/terraform/eks/default

# Remove application Helm releases from Terraform state
terraform state rm helm_release.ui
terraform state rm helm_release.catalog
terraform state rm helm_release.carts
terraform state rm helm_release.orders
terraform state rm helm_release.checkout

# Verify removal
terraform state list | grep helm_release
```

Expected output: Only infrastructure Helm releases should remain (cert-manager, etc.)

### Step 2: Comment Out Application Deployments in Terraform

Create a backup first:

```bash
cp kubernetes.tf kubernetes.tf.backup
```

Edit `kubernetes.tf` and comment out or remove these sections:

```terraform
# Comment out lines 83-108 (helm_release.catalog)
# Comment out lines 115-138 (helm_release.carts)
# Comment out lines 145-170 (helm_release.checkout)
# Comment out lines 176-211 (helm_release.orders)
# Comment out lines 213-243 (helm_release.ui)
```

**Keep these sections:**
- `kubernetes_namespace_v1.*` resources (lines 68-81, 110-113, 140-143, 172-175, 245-248)
- `null_resource.ingress_class` (lines 213-243)
- `time_sleep.restart_pods` and `null_resource.restart_pods` (lines 245-275)

### Step 3: Update Terraform Configuration

I'll create a modified version that only manages infrastructure:

```bash
# This will be done in the next step
```

### Step 4: Verify Terraform Plan

After removing from state and commenting out code:

```bash
terraform plan
```

Expected output:
- No changes to application resources
- Only infrastructure resources shown
- No "destroy" operations for applications

### Step 5: Delete Terraform-Managed Application Resources

Now that Terraform won't recreate them, delete the old deployments:

```bash
# Delete Terraform-managed deployments (not retail-* ones)
kubectl delete deployment ui catalog carts orders checkout \
  -n ui -n catalog -n carts -n orders -n checkout 2>/dev/null || true

# Delete Terraform-managed services (not retail-* ones)
kubectl delete service ui catalog carts orders checkout \
  -n ui -n catalog -n carts -n orders -n checkout 2>/dev/null || true

# Verify only ArgoCD-managed resources remain
kubectl get deployments,services --all-namespaces | grep -E "retail-"
```

### Step 6: Ensure ArgoCD Apps Are Synced

```bash
# Login to ArgoCD
argocd login k8s-argocd-argocdse-0fafe6a2bf-1764938714.us-east-1.elb.amazonaws.com --insecure

# Sync all apps
argocd app sync retail-ui retail-catalog retail-carts retail-orders retail-checkout

# Verify all apps are healthy
argocd app list
```

### Step 7: Test End-to-End

```bash
# Check all pods are running
kubectl get pods --all-namespaces | grep retail-

# Test application
curl -I http://k8s-ui-ui-2e4c4d4311-1005461520.us-east-1.elb.amazonaws.com
```

---

## Modified kubernetes.tf

Here's what the file should look like after modification:

```terraform
locals {
  istio_labels = {
    istio-injection = "enabled"
  }

  kubeconfig = yamlencode({
    apiVersion      = "v1"
    kind            = "Config"
    current-context = "terraform"
    clusters = [{
      name = module.retail_app_eks.eks_cluster_id
      cluster = {
        certificate-authority-data = module.retail_app_eks.cluster_certificate_authority_data
        server                     = module.retail_app_eks.cluster_endpoint
      }
    }]
    contexts = [{
      name = "terraform"
      context = {
        cluster = module.retail_app_eks.eks_cluster_id
        user    = "terraform"
      }
    }]
    users = [{
      name = "terraform"
      user = {
        token = data.aws_eks_cluster_auth.this.token
      }
    }]
  })
}

module "container_images" {
  source = "../../lib/images"

  container_image_overrides = var.container_image_overrides
}

resource "null_resource" "cluster_blocker" {
  triggers = {
    "blocker" = module.retail_app_eks.cluster_blocker_id
  }
}

resource "null_resource" "addons_blocker" {
  triggers = {
    "blocker" = module.retail_app_eks.addons_blocker_id
  }
}

resource "time_sleep" "workloads" {
  create_duration  = "30s"
  destroy_duration = "60s"

  depends_on = [
    null_resource.addons_blocker
  ]
}

# Create namespaces for applications (ArgoCD will deploy into these)
resource "kubernetes_namespace_v1" "catalog" {
  depends_on = [
    time_sleep.workloads
  ]

  metadata {
    name = "catalog"
    labels = var.istio_enabled ? local.istio_labels : {}
  }
}

resource "kubernetes_namespace_v1" "carts" {
  depends_on = [
    time_sleep.workloads
  ]

  metadata {
    name = "carts"
    labels = var.istio_enabled ? local.istio_labels : {}
  }
}

resource "kubernetes_namespace_v1" "checkout" {
  depends_on = [
    time_sleep.workloads
  ]

  metadata {
    name = "checkout"
    labels = var.istio_enabled ? local.istio_labels : {}
  }
}

resource "kubernetes_namespace_v1" "orders" {
  depends_on = [
    time_sleep.workloads
  ]

  metadata {
    name = "orders"
    labels = var.istio_enabled ? local.istio_labels : {}
  }
}

resource "kubernetes_namespace_v1" "ui" {
  depends_on = [
    time_sleep.workloads
  ]

  metadata {
    name = "ui"
    labels = var.istio_enabled ? local.istio_labels : {}
  }
}

# EKS Auto Mode: IngressClass and IngressClassParams for ALB
resource "null_resource" "ingress_class" {
  depends_on = [
    time_sleep.workloads
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = base64encode(local.kubeconfig)
    }

    command = <<-EOT
      cat <<EOF | kubectl apply --kubeconfig <(echo $KUBECONFIG | base64 -d) -f -
apiVersion: eks.amazonaws.com/v1
kind: IngressClassParams
metadata:
  name: alb
spec:
  scheme: internet-facing
---
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: alb
  annotations:
    ingressclass.kubernetes.io/is-default-class: "true"
spec:
  controller: eks.amazonaws.com/alb
  parameters:
    apiGroup: eks.amazonaws.com
    kind: IngressClassParams
    name: alb
EOF
    EOT
  }
}

# Note: Application deployments are now managed by ArgoCD
# See: /Users/kunpil/MyProjects/sample-devops-agent-eks-workshop/argocd-apps/
# and: /Users/kunpil/MyProjects/sample-devops-agent-eks-workshop/helm-charts/
```

---

## Verification Checklist

After completing all steps:

- [ ] Terraform state has no `helm_release` for applications
- [ ] `terraform plan` shows no changes to applications
- [ ] Only `retail-*` deployments exist in cluster
- [ ] All ArgoCD apps show "Synced" and "Healthy"
- [ ] Application is accessible via ALB
- [ ] All services have 2 replicas (after scaling)
- [ ] No duplicate deployments or services

---

## Rollback Plan

If something goes wrong:

```bash
# Restore Terraform configuration
cp kubernetes.tf.backup kubernetes.tf

# Re-import resources into Terraform state
terraform import helm_release.ui ui/ui
terraform import helm_release.catalog catalog/catalog
# ... etc

# Or delete ArgoCD apps and let Terraform recreate
argocd app delete retail-ui retail-catalog retail-carts retail-orders retail-checkout --cascade
terraform apply
```

---

## Benefits of This Separation

✅ **Clear Ownership**:
- Infrastructure team manages Terraform
- Application team manages ArgoCD/Git

✅ **GitOps Workflow**:
- Application changes via Git commits
- Automatic deployment via ArgoCD
- Easy rollbacks via Git revert

✅ **No Conflicts**:
- Terraform won't overwrite ArgoCD changes
- ArgoCD won't conflict with Terraform

✅ **Scalability**:
- Add new services via Git
- No Terraform changes needed for app updates

✅ **Disaster Recovery**:
- Terraform recreates infrastructure
- ArgoCD automatically redeploys apps
