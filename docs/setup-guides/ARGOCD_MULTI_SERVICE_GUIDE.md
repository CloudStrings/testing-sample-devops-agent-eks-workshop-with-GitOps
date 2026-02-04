# ArgoCD Multi-Service Deployment Guide

## Question: One App or Multiple Apps?

For the retail store with 5 microservices (ui, catalog, carts, orders, checkout), you have three options:

---

## Option 1: Separate Application per Service ⭐ RECOMMENDED

### Architecture
```
ArgoCD UI View:
├── retail-ui       [Synced] [Healthy]
├── retail-catalog  [Synced] [Healthy]
├── retail-carts    [Synced] [Healthy]
├── retail-orders   [Synced] [Healthy]
└── retail-checkout [Synced] [Healthy]
```

### Setup

**Via CLI (Quick):**
```bash
SERVICES=("ui" "catalog" "carts" "orders" "checkout")

for service in "${SERVICES[@]}"; do
  argocd app create retail-$service \
    --repo https://github.com/YOUR_USERNAME/sample-devops-agent-eks-workshop.git \
    --path helm-charts/$service \
    --dest-server https://kubernetes.default.svc \
    --dest-namespace $service \
    --sync-policy automated \
    --auto-prune \
    --self-heal \
    --sync-option CreateNamespace=true
done
```

**Via UI:**
Repeat 5 times (once per service):
1. Applications → + New App
2. Name: `retail-ui` (then catalog, carts, etc.)
3. Path: `helm-charts/ui` (then catalog, carts, etc.)
4. Namespace: `ui` (then catalog, carts, etc.)
5. Sync Policy: Automatic

### Pros & Cons

✅ **Pros:**
- Independent deployments (update UI without touching catalog)
- Granular control (different sync policies per service)
- Clear visibility (see each service health separately)
- Selective rollback (rollback orders without affecting ui)
- Team ownership (each team owns their ArgoCD app)

❌ **Cons:**
- More apps to manage (5 total)
- Slightly more initial setup

### When to Use
- ✅ Production environments
- ✅ Microservices architecture
- ✅ Multiple teams
- ✅ Services with different release cycles

---

## Option 2: Single Application (All Services) ❌ NOT RECOMMENDED

### Architecture
```
ArgoCD UI View:
└── retail-store [Synced] [Healthy]
    ├── ui namespace
    ├── catalog namespace
    ├── carts namespace
    ├── orders namespace
    └── checkout namespace
```

### Why Not Recommended

❌ **All-or-nothing deployment**
- Can't update just the UI
- One bad change breaks everything

❌ **Poor visibility**
- Can't see individual service health
- Harder to debug which service is failing

❌ **Slower syncs**
- ArgoCD processes all 5 services every time
- Even if you only changed one

❌ **Requires repo restructuring**
- Need umbrella Helm chart or kustomize
- More complex than separate apps

### When to Use
- Simple demos
- Tightly coupled monolithic apps
- All services must deploy together

---

## Option 3: App of Apps Pattern ⭐⭐ BEST FOR SCALE

### Architecture
```
ArgoCD UI View:
└── retail-store-apps (parent) [Synced] [Healthy]
    ├── retail-ui (child)       [Synced] [Healthy]
    ├── retail-catalog (child)  [Synced] [Healthy]
    ├── retail-carts (child)    [Synced] [Healthy]
    ├── retail-orders (child)   [Synced] [Healthy]
    └── retail-checkout (child) [Synced] [Healthy]
```

### How It Works

1. **Parent app** watches `argocd-apps/` directory in your Git repo
2. **Child app manifests** are stored in `argocd-apps/` as YAML files
3. **Parent creates/updates** child apps automatically
4. **GitOps all the way** - even ArgoCD apps are managed by Git

### Setup

**Step 1: Create directory structure**
```bash
mkdir -p argocd-apps
```

**Step 2: Create child app manifests**

Create `argocd-apps/ui-app.yaml`:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: retail-ui
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/YOUR_USERNAME/sample-devops-agent-eks-workshop.git
    targetRevision: main
    path: helm-charts/ui
  destination:
    server: https://kubernetes.default.svc
    namespace: ui
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

Repeat for catalog, carts, orders, checkout.

**Step 3: Create parent app**

Create `argocd-apps/app-of-apps.yaml`:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: retail-store-apps
  namespace: argocd
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
```

**Step 4: Commit to Git**
```bash
git add argocd-apps/
git commit -m "Add ArgoCD App of Apps configuration"
git push origin main
```

**Step 5: Deploy parent app**
```bash
kubectl apply -f argocd-apps/app-of-apps.yaml
```

**Step 6: Watch magic happen**
```bash
# Parent app creates all child apps automatically
argocd app list

# Watch parent app
argocd app get retail-store-apps
```

### Pros & Cons

✅ **Pros:**
- All benefits of separate apps (independence, visibility, control)
- Centralized management (one parent app to rule them all)
- GitOps for ArgoCD itself (apps defined in Git)
- Easy to add services (just add YAML file, parent creates it)
- Scalable (works for 5 or 500 services)

❌ **Cons:**
- More complex initial setup
- Requires understanding of the pattern
- Extra directory in your repo

### When to Use
- ✅ Production environments
- ✅ Many microservices (5+)
- ✅ True GitOps approach
- ✅ Teams that want everything in Git

---

## Comparison Table

| Feature | Separate Apps | Single App | App of Apps |
|---------|--------------|------------|-------------|
| **Independent deployments** | ✅ Yes | ❌ No | ✅ Yes |
| **Granular control** | ✅ Yes | ❌ No | ✅ Yes |
| **Clear visibility** | ✅ Yes | ❌ No | ✅ Yes |
| **Easy to add services** | ⚠️ Manual | ⚠️ Manual | ✅ Automatic |
| **GitOps for apps** | ❌ No | ❌ No | ✅ Yes |
| **Setup complexity** | ⭐ Easy | ⭐⭐ Medium | ⭐⭐⭐ Advanced |
| **Best for** | Getting started | Demos | Production |

---

## Recommendation for Your Retail Store

### Phase 1: Start with Separate Apps (Option 1)
```bash
# Quick setup - 5 minutes
for service in ui catalog carts orders checkout; do
  argocd app create retail-$service \
    --repo https://github.com/YOUR_USERNAME/sample-devops-agent-eks-workshop.git \
    --path helm-charts/$service \
    --dest-namespace $service \
    --sync-policy automated
done
```

**Why:** Easy to understand, quick to set up, all benefits of microservices.

### Phase 2: Migrate to App of Apps (Option 3)
```bash
# After you're comfortable with ArgoCD
./argocd-app-of-apps-setup.sh
git add argocd-apps/
git commit -m "Migrate to App of Apps pattern"
git push origin main
kubectl apply -f argocd-apps/app-of-apps.yaml
```

**Why:** Scales better, true GitOps, easier to manage long-term.

---

## Real-World Example: Making a Change

### With Separate Apps (Option 1)

```bash
# Update UI service
cd helm-charts/ui
nano values.yaml  # Change replicaCount: 2

git commit -am "Scale UI to 2 replicas"
git push origin main

# ArgoCD syncs ONLY retail-ui app
# Other services (catalog, carts, orders, checkout) unaffected
```

### With App of Apps (Option 3)

```bash
# Same as above - child apps are independent
cd helm-charts/ui
nano values.yaml

git commit -am "Scale UI to 2 replicas"
git push origin main

# Parent app detects no changes to argocd-apps/
# Child retail-ui app syncs independently
```

### Adding a New Service

**With Separate Apps:**
```bash
# Manual: Create new ArgoCD app via CLI or UI
argocd app create retail-payment --path helm-charts/payment ...
```

**With App of Apps:**
```bash
# Automatic: Just add manifest to Git
cat > argocd-apps/payment-app.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: retail-payment
  namespace: argocd
spec:
  source:
    path: helm-charts/payment
  # ... rest of config
EOF

git add argocd-apps/payment-app.yaml
git commit -m "Add payment service"
git push origin main

# Parent app automatically creates retail-payment child app!
```

---

## Quick Start Script

I've created `argocd-app-of-apps-setup.sh` for you. To use it:

```bash
# Make executable
chmod +x argocd-app-of-apps-setup.sh

# Run it
./argocd-app-of-apps-setup.sh

# Follow the prompts
# It will create all manifests in argocd-apps/

# Commit to Git
git add argocd-apps/
git commit -m "Add ArgoCD App of Apps"
git push origin main

# Deploy parent app
kubectl apply -f argocd-apps/app-of-apps.yaml

# Watch it work
argocd app list
```

---

## Summary

**Answer: Yes, create separate applications for each service.**

**Start with:** Option 1 (Separate Apps) - Easy and effective
**Upgrade to:** Option 3 (App of Apps) - When you want true GitOps

Both give you independent deployments, which is what you want for microservices!

---

**Need help choosing? Start with Option 1. You can always migrate to Option 3 later!** 🚀
