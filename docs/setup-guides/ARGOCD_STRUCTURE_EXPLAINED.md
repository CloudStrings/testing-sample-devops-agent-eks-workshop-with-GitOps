# ArgoCD Structure Explained

## Two Different Directories - Different Purposes

### Directory 1: `argocd-apps/` (ArgoCD Application Manifests)

**Location**: `/Users/kunpil/MyProjects/sample-devops-agent-eks-workshop/argocd-apps/`

**Purpose**: These are **ArgoCD Application definitions** that tell ArgoCD:
- WHAT to deploy (which Helm chart)
- WHERE to get it from (GitHub repo + path)
- WHERE to deploy it (namespace)
- HOW to sync it (automated, prune, selfHeal)

**Files**:
```
argocd-apps/
├── app-of-apps.yaml          # Parent app that deploys all child apps
├── ui-app.yaml               # ArgoCD Application for UI
├── catalog-app.yaml          # ArgoCD Application for Catalog
├── carts-app.yaml            # ArgoCD Application for Carts
├── orders-app.yaml           # ArgoCD Application for Orders
└── checkout-app.yaml         # ArgoCD Application for Checkout
```

**Example - `ui-app.yaml`**:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: retail-ui
  namespace: argocd
spec:
  source:
    repoURL: https://github.com/CloudStrings/testing-sample-devops-agent-eks-workshop-with-GitOps.git
    targetRevision: main
    path: helm-charts/ui  # ← Points to Helm chart directory
    helm:
      valueFiles:
        - values.yaml     # ← Uses this values file
  
  destination:
    namespace: ui         # ← Deploys to this namespace
```

**Key Point**: These files are **pointers** that reference the actual Helm charts.

---

### Directory 2: `helm-charts/` (Actual Helm Charts)

**Location**: `/Users/kunpil/MyProjects/sample-devops-agent-eks-workshop/helm-charts/`

**Purpose**: These are the **actual Helm charts** that contain:
- Kubernetes manifests (Deployment, Service, ConfigMap, etc.)
- Default values
- Templates

**Files**:
```
helm-charts/
├── ui/
│   ├── Chart.yaml            # Helm chart metadata
│   ├── values.yaml           # ← THIS is what I was analyzing
│   └── templates/
│       ├── deployment.yaml
│       ├── service.yaml
│       ├── configmap.yaml
│       └── ingress.yaml
├── catalog/
│   ├── Chart.yaml
│   ├── values.yaml           # ← THIS needs infrastructure values
│   └── templates/
├── carts/
│   ├── Chart.yaml
│   ├── values.yaml           # ← THIS needs IAM role ARN
│   └── templates/
├── orders/
│   ├── Chart.yaml
│   ├── values.yaml           # ← THIS needs DB + MQ endpoints
│   └── templates/
└── checkout/
    ├── Chart.yaml
    ├── values.yaml
    └── templates/
```

**Example - `helm-charts/ui/values.yaml`**:
```yaml
replicaCount: 2

image:
  repository: public.ecr.aws/aws-containers/retail-store-sample-ui
  tag: latest

app:
  endpoints:
    catalog: http://catalog.catalog.svc:80  # ← Application configuration
    carts: http://carts.carts.svc:80
    orders: http://orders.orders.svc:80
```

**Key Point**: These files contain the **actual configuration** that gets deployed.

---

## How They Work Together

```
┌─────────────────────────────────────────────────────────────────┐
│                         GitHub Repository                       │
│  https://github.com/CloudStrings/testing-sample-devops-...     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  argocd-apps/                    helm-charts/                  │
│  ├── app-of-apps.yaml            ├── ui/                       │
│  ├── ui-app.yaml ────────────────┼──> values.yaml              │
│  ├── catalog-app.yaml ───────────┼──> catalog/values.yaml     │
│  ├── carts-app.yaml ─────────────┼──> carts/values.yaml       │
│  ├── orders-app.yaml ────────────┼──> orders/values.yaml      │
│  └── checkout-app.yaml ──────────┼──> checkout/values.yaml    │
│                                  │                              │
│  (ArgoCD Application Manifests)  │  (Actual Helm Charts)       │
│  (Pointers/References)           │  (Real Configuration)       │
└─────────────────────────────────────────────────────────────────┘
                            ↓
                    ArgoCD reads both
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│                         ArgoCD                                  │
│                                                                 │
│  1. Reads argocd-apps/ui-app.yaml                              │
│  2. Sees: "Deploy from helm-charts/ui"                         │
│  3. Reads helm-charts/ui/values.yaml                           │
│  4. Renders Helm templates with values                         │
│  5. Deploys to Kubernetes namespace "ui"                       │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│                      Kubernetes Cluster                         │
│                                                                 │
│  Namespace: ui                                                  │
│  ├── Deployment: retail-ui (2 replicas)                        │
│  ├── Service: retail-ui                                        │
│  ├── ConfigMap: retail-ui-config                               │
│  └── Ingress: retail-ui-ingress                                │
└─────────────────────────────────────────────────────────────────┘
```

---

## What I Was Analyzing

When I said "your ArgoCD Helm charts are using in-memory values", I was referring to:

**File**: `helm-charts/orders/values.yaml` (NOT `argocd-apps/orders-app.yaml`)

```yaml
# Current content in helm-charts/orders/values.yaml
app:
  persistence:
    provider: 'in-memory'  # ❌ Wrong - should be 'postgres'
    endpoint: ''           # ❌ Missing - needs RDS endpoint
    
  messaging:
    provider: 'in-memory'  # ❌ Wrong - should be 'rabbitmq'
    rabbitmq:
      addresses: []        # ❌ Missing - needs MQ endpoint
```

This is why orders is crashing - it's trying to use in-memory storage but the application code expects real databases.

---

## What Needs To Be Updated

### ❌ DO NOT MODIFY: `argocd-apps/*.yaml`

These are already correct. They point to the right Helm charts and have the right sync policies.

### ✅ MUST MODIFY: `helm-charts/*/values.yaml`

These need infrastructure values from Terraform:

**File**: `helm-charts/catalog/values.yaml`
```yaml
app:
  persistence:
    provider: mysql  # ← Change from "in-memory"
    endpoint: "catalog-db.xxxxx.us-east-1.rds.amazonaws.com:3306"  # ← Add from Terraform
    secret:
      username: catalog_user  # ← Add from Terraform
      password: "xxxxx"       # ← Add from Terraform
```

**File**: `helm-charts/carts/values.yaml`
```yaml
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/retail-carts  # ← Add from Terraform

app:
  persistence:
    provider: dynamodb  # ← Change from "in-memory"
    dynamodb:
      tableName: retail-carts-table  # ← Add from Terraform
```

**File**: `helm-charts/orders/values.yaml`
```yaml
app:
  persistence:
    provider: 'postgres'  # ← Change from "in-memory"
    endpoint: 'orders-db.xxxxx.us-east-1.rds.amazonaws.com:5432'  # ← Add from Terraform
    database: 'orders'
    secret:
      username: orders_user  # ← Add from Terraform
      password: "xxxxx"      # ← Add from Terraform
      
  messaging:
    provider: 'rabbitmq'  # ← Change from "in-memory"
    rabbitmq:
      addresses: ["b-xxxxx.mq.us-east-1.amazonaws.com:5671"]  # ← Add from Terraform
      secret:
        username: admin  # ← Add from Terraform
        password: "xxxxx"  # ← Add from Terraform
```

---

## Workflow After Updates

1. **Edit**: `helm-charts/*/values.yaml` (add infrastructure values)
2. **Commit**: `git add helm-charts/*/values.yaml`
3. **Push**: `git push origin main`
4. **ArgoCD**: Automatically detects changes in GitHub
5. **Sync**: ArgoCD syncs and redeploys with new values
6. **Result**: Orders pod starts successfully with real databases

---

## Summary

| Directory | Purpose | Modify? | Why? |
|-----------|---------|---------|------|
| `argocd-apps/` | ArgoCD Application definitions (pointers) | ❌ No | Already correct |
| `helm-charts/` | Actual Helm charts with configuration | ✅ Yes | Need infrastructure values |

**The files I was analyzing**: `helm-charts/*/values.yaml`
**The files you mentioned**: `argocd-apps/*.yaml` (these are fine, don't touch them)

Does this clarify the structure? The key takeaway: you need to update `helm-charts/*/values.yaml` with Terraform infrastructure outputs, NOT the `argocd-apps/*.yaml` files.
