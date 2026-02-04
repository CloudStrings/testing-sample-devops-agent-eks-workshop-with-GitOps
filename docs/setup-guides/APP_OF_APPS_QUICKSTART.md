# App of Apps Pattern - Quick Start Guide

## What You'll Create

```
Your Git Repo:
├── helm-charts/          (already exists)
│   ├── ui/
│   ├── catalog/
│   ├── carts/
│   ├── orders/
│   └── checkout/
└── argocd-apps/          (NEW - you'll create this)
    ├── ui-app.yaml       (defines retail-ui app)
    ├── catalog-app.yaml  (defines retail-catalog app)
    ├── carts-app.yaml    (defines retail-carts app)
    ├── orders-app.yaml   (defines retail-orders app)
    ├── checkout-app.yaml (defines retail-checkout app)
    └── app-of-apps.yaml  (parent app that creates all above)
```

---

## Step-by-Step Setup

### Step 1: Create Directory Structure

```bash
# Navigate to your repo
cd sample-devops-agent-eks-workshop

# Create directory for ArgoCD app definitions
mkdir -p argocd-apps

# Verify
ls -la
# You should see: argocd-apps/ helm-charts/ terraform/ etc.
```

---

### Step 2: Create Child Application Manifests

Create a manifest for each microservice:

#### UI Application

```bash
cat > argocd-apps/ui-app.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: retail-ui
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  
  source:
    repoURL: https://github.com/YOUR_USERNAME/sample-devops-agent-eks-workshop.git
    targetRevision: main
    path: helm-charts/ui
    helm:
      valueFiles:
        - values.yaml
  
  destination:
    server: https://kubernetes.default.svc
    namespace: ui
  
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF
```

**⚠️ IMPORTANT: Replace `YOUR_USERNAME` with your actual GitHub username!**

#### Catalog Application

```bash
cat > argocd-apps/catalog-app.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: retail-catalog
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  
  source:
    repoURL: https://github.com/YOUR_USERNAME/sample-devops-agent-eks-workshop.git
    targetRevision: main
    path: helm-charts/catalog
    helm:
      valueFiles:
        - values.yaml
  
  destination:
    server: https://kubernetes.default.svc
    namespace: catalog
  
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF
```

#### Carts Application

```bash
cat > argocd-apps/carts-app.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: retail-carts
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  
  source:
    repoURL: https://github.com/YOUR_USERNAME/sample-devops-agent-eks-workshop.git
    targetRevision: main
    path: helm-charts/carts
    helm:
      valueFiles:
        - values.yaml
  
  destination:
    server: https://kubernetes.default.svc
    namespace: carts
  
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF
```

#### Orders Application

```bash
cat > argocd-apps/orders-app.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: retail-orders
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  
  source:
    repoURL: https://github.com/YOUR_USERNAME/sample-devops-agent-eks-workshop.git
    targetRevision: main
    path: helm-charts/orders
    helm:
      valueFiles:
        - values.yaml
  
  destination:
    server: https://kubernetes.default.svc
    namespace: orders
  
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF
```

#### Checkout Application

```bash
cat > argocd-apps/checkout-app.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: retail-checkout
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  
  source:
    repoURL: https://github.com/YOUR_USERNAME/sample-devops-agent-eks-workshop.git
    targetRevision: main
    path: helm-charts/checkout
    helm:
      valueFiles:
        - values.yaml
  
  destination:
    server: https://kubernetes.default.svc
    namespace: checkout
  
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF
```

---

### Step 3: Create Parent "App of Apps"

```bash
cat > argocd-apps/app-of-apps.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: retail-store-apps
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  
  source:
    repoURL: https://github.com/YOUR_USERNAME/sample-devops-agent-eks-workshop.git
    targetRevision: main
    path: argocd-apps
  
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
EOF
```

**⚠️ IMPORTANT: Replace `YOUR_USERNAME` in ALL files!**

---

### Step 4: Replace YOUR_USERNAME in All Files

```bash
# Quick find and replace (macOS/Linux)
# Replace YOUR_USERNAME with your actual GitHub username

# Option A: Using sed (one command)
find argocd-apps -name "*.yaml" -type f -exec sed -i '' 's/YOUR_USERNAME/your-actual-username/g' {} \;

# Option B: Manual replacement
# Edit each file and replace YOUR_USERNAME with your GitHub username
nano argocd-apps/ui-app.yaml
nano argocd-apps/catalog-app.yaml
nano argocd-apps/carts-app.yaml
nano argocd-apps/orders-app.yaml
nano argocd-apps/checkout-app.yaml
nano argocd-apps/app-of-apps.yaml
```

---

### Step 5: Verify Files

```bash
# Check all files were created
ls -la argocd-apps/

# Should show:
# app-of-apps.yaml
# carts-app.yaml
# catalog-app.yaml
# checkout-app.yaml
# orders-app.yaml
# ui-app.yaml

# Verify your username is in the files
grep "github.com" argocd-apps/*.yaml

# Should show your username, NOT "YOUR_USERNAME"
```

---

### Step 6: Commit to Git

```bash
# Add the new directory
git add argocd-apps/

# Commit
git commit -m "Add ArgoCD App of Apps configuration"

# Push to your fork
git push origin main

# Verify it's on GitHub
# Go to: https://github.com/YOUR_USERNAME/sample-devops-agent-eks-workshop
# You should see the argocd-apps/ directory
```

---

### Step 7: Deploy the Parent App

```bash
# Apply the parent app to your cluster
kubectl apply -f argocd-apps/app-of-apps.yaml

# You should see:
# application.argoproj.io/retail-store-apps created
```

---

### Step 8: Watch the Magic Happen

```bash
# Watch ArgoCD create all child apps
argocd app list

# You should see:
# NAME                CLUSTER                         NAMESPACE  PROJECT  STATUS  HEALTH
# retail-store-apps   https://kubernetes.default.svc  argocd     default  Synced  Healthy
# retail-ui           https://kubernetes.default.svc  ui         default  Synced  Healthy
# retail-catalog      https://kubernetes.default.svc  catalog    default  Synced  Healthy
# retail-carts        https://kubernetes.default.svc  carts      default  Synced  Healthy
# retail-orders       https://kubernetes.default.svc  orders     default  Synced  Healthy
# retail-checkout     https://kubernetes.default.svc  checkout   default  Synced  Healthy

# Get details of parent app
argocd app get retail-store-apps

# Watch sync in real-time
argocd app sync retail-store-apps --watch
```

---

### Step 9: Verify in ArgoCD UI

```bash
# Access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Open in browser
open https://localhost:8080

# You should see:
# - retail-store-apps (parent)
# - retail-ui (child)
# - retail-catalog (child)
# - retail-carts (child)
# - retail-orders (child)
# - retail-checkout (child)
```

---

### Step 10: Verify Pods are Running

```bash
# Check all namespaces
kubectl get pods --all-namespaces | grep retail

# Or check each namespace
kubectl get pods -n ui
kubectl get pods -n catalog
kubectl get pods -n carts
kubectl get pods -n orders
kubectl get pods -n checkout

# All pods should be Running
```

---

## How It Works

### The Flow

```
1. You push changes to Git
   ↓
2. Parent app (retail-store-apps) detects changes in argocd-apps/
   ↓
3. Parent app creates/updates child apps
   ↓
4. Child apps detect changes in helm-charts/
   ↓
5. Child apps sync to Kubernetes cluster
   ↓
6. Pods restart with new configuration
```

### Example: Update UI Service

```bash
# Edit UI Helm values
cd helm-charts/ui
nano values.yaml

# Change:
replicaCount: 1
# To:
replicaCount: 2

# Commit and push
git add values.yaml
git commit -m "Scale UI to 2 replicas"
git push origin main

# ArgoCD automatically:
# 1. Parent app checks argocd-apps/ (no changes)
# 2. Child retail-ui app checks helm-charts/ui (CHANGED!)
# 3. Child retail-ui app syncs
# 4. UI pods scale to 2 replicas

# Watch it happen
argocd app get retail-ui --watch
kubectl get pods -n ui -w
```

### Example: Add New Service

```bash
# Create new service manifest
cat > argocd-apps/payment-app.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: retail-payment
  namespace: argocd
spec:
  source:
    repoURL: https://github.com/YOUR_USERNAME/sample-devops-agent-eks-workshop.git
    path: helm-charts/payment
  destination:
    namespace: payment
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

# Commit and push
git add argocd-apps/payment-app.yaml
git commit -m "Add payment service"
git push origin main

# Parent app automatically creates retail-payment child app!
argocd app list | grep payment
```

---

## Troubleshooting

### Issue: Parent app not creating child apps

**Check parent app status:**
```bash
argocd app get retail-store-apps

# Look for errors in the output
```

**Check parent app logs:**
```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller | grep retail-store-apps
```

**Manual sync:**
```bash
argocd app sync retail-store-apps
```

### Issue: Child apps not syncing

**Check if repository is accessible:**
```bash
argocd repo list

# Should show your repository with CONNECTION STATUS: Successful
```

**Check child app status:**
```bash
argocd app get retail-ui

# Look for errors
```

**Manual sync:**
```bash
argocd app sync retail-ui
```

### Issue: "YOUR_USERNAME" still in files

**You forgot to replace the placeholder!**
```bash
# Check files
grep "YOUR_USERNAME" argocd-apps/*.yaml

# If found, replace:
find argocd-apps -name "*.yaml" -type f -exec sed -i '' 's/YOUR_USERNAME/your-actual-username/g' {} \;

# Commit and push
git add argocd-apps/
git commit -m "Fix GitHub username in ArgoCD apps"
git push origin main

# Sync parent app
argocd app sync retail-store-apps
```

---

## Alternative: Use the Automated Script

I created a script that does all of this for you:

```bash
# Make executable
chmod +x argocd-app-of-apps-setup.sh

# Run it
./argocd-app-of-apps-setup.sh

# It will:
# 1. Ask for your GitHub username
# 2. Create all manifests with correct username
# 3. Tell you what to do next

# Then just:
git add argocd-apps/
git commit -m "Add ArgoCD App of Apps"
git push origin main
kubectl apply -f argocd-apps/app-of-apps.yaml
```

---

## Summary

**What you created:**
- ✅ 5 child app manifests (one per microservice)
- ✅ 1 parent app manifest (manages all children)
- ✅ All stored in Git (true GitOps!)

**What happens now:**
- ✅ Changes to `helm-charts/*` → Child apps auto-sync
- ✅ Changes to `argocd-apps/*` → Parent app auto-creates/updates children
- ✅ Everything is automated!

**Next steps:**
- Make a change to a Helm chart
- Watch ArgoCD auto-deploy it
- Enjoy GitOps! 🚀

---

## Quick Reference

```bash
# View all apps
argocd app list

# View parent app
argocd app get retail-store-apps

# View child app
argocd app get retail-ui

# Sync parent (creates/updates children)
argocd app sync retail-store-apps

# Sync child (deploys to cluster)
argocd app sync retail-ui

# Delete everything
kubectl delete -f argocd-apps/app-of-apps.yaml
```

---

**You're all set! The App of Apps pattern is now managing your retail store microservices.** 🎉
