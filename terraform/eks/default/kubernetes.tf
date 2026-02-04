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

# ============================================================================
# NAMESPACES - Required for ArgoCD to deploy applications into
# ============================================================================

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

# ============================================================================
# INGRESS CLASS - Required for ALB Ingress to work
# ============================================================================

# EKS Auto Mode: IngressClass and IngressClassParams for ALB
# Using null_resource with kubectl to avoid plan-time cluster connection issues
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

# ============================================================================
# APPLICATION DEPLOYMENTS - Now managed by ArgoCD
# ============================================================================
# 
# The following resources have been removed from Terraform management:
# - helm_release.catalog
# - helm_release.carts  
# - helm_release.checkout
# - helm_release.orders
# - helm_release.ui
#
# These are now deployed via ArgoCD from:
# - GitHub: https://github.com/CloudStrings/testing-sample-devops-agent-eks-workshop-with-GitOps.git
# - Path: helm-charts/*
# - ArgoCD Apps: retail-ui, retail-catalog, retail-carts, retail-orders, retail-checkout
#
# To deploy/update applications:
# 1. Make changes to helm-charts/* in Git
# 2. Commit and push to GitHub
# 3. ArgoCD will automatically sync and deploy
#
# Infrastructure dependencies (managed by Terraform):
# - Databases: module.dependencies (RDS, DynamoDB, ElastiCache, MQ)
# - IAM Roles: module.iam_assumable_role_carts
# - Security Groups: aws_security_group.catalog, orders, checkout
# - Namespaces: kubernetes_namespace_v1.* (above)
# - IngressClass: null_resource.ingress_class (above)
#
# ============================================================================
