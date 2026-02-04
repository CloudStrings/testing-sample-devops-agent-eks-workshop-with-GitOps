# ArgoCD Configuration Guide - Watch Your Fork

## Prerequisites

Before configuring ArgoCD, ensure:
- ✅ ArgoCD is installed on your EKS cluster
- ✅ You can access ArgoCD UI (via port-forward or LoadBalancer)
- ✅ You have forked the repository to your GitHub account
- ✅ You have a GitHub Personal Access Token (for private repos)

---

## Method 1: Configure via ArgoCD UI (Easiest)

### Step 1: Access ArgoCD UI

```bash
# Start port forwarding
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo

# Open in browser
open https://localhost:8080
```

Login with:
- **Username**: `admin`
- **Password**: (from command above)

### Step 2: Add Your Git Repository

1. Click **Settings** (gear icon) in the left sidebar
2. Click **Repositories**
3. Click **+ Connect Repo**
4. Choose connection method:

#### Option A: HTTPS (Recommended for Public Repos)

```
Connection Method: VIA HTTPS
Type: git
Project: default
Repository URL: https://github.com/YOUR_USERNAME/sample-devops-agent-eks-workshop.git

# For public repos, leave credentials empty
# For private repos, fill in:
Username: YOUR_GITHUB_USERNAME
Password: YOUR_GITHUB_TOKEN (Personal Access Token)

# Click "Connect"
```

#### Option B: SSH (For Private Repos with SSH Keys)

```
Connection Method: VIA SSH
Type: git
Project: default
Repository URL: git@github.com:YOUR_USERNAME/sample-devops-agent-eks-workshop.git
SSH private key data: [Paste your SSH private key]

# Click "Connect"
```

### Step 3: Verify Repository Connection

After clicking "Connect", you should see:
- ✅ **Connection Status: Successful**
- Repository appears in the list

If you see an error, check:
- URL is correct
- GitHub token has `repo` permissions
- Repository exists and is accessible

### Step 4: Create Your First Application

1. Click **Applications** in the left sidebar
2. Click **+ New App**
3. Fill in the form:

```yaml
Application Name: retail-ui
Project: default
Sync Policy: Automatic

# Source
Repository URL: https://github.com/YOUR_USERNAME/sample-devops-agent-eks-workshop.git
Revision: main
Path: helm-charts/ui

# Destination
Cluster URL: https://kubernetes.default.svc
Namespace: ui

# Helm (if using Helm charts)
Values Files: values.yaml
```

4. Click **Create**

### Step 5: Enable Auto-Sync

After creating the app:

1. Click on the application name (retail-ui)
2. Click **App Details** (top right)
3. Click **Sync Policy** section
4. Enable:
   - ✅ **Automated Sync**
   - ✅ **Prune Resources** (delete resources not in Git)
   - ✅ **Self Heal** (auto-sync if cluster state drifts)
5. Click **Save**

---

## Method 2: Configure via ArgoCD CLI (Advanced)

### Step 1: Install ArgoCD CLI

```bash
# macOS
brew install argocd

# Verify installation
argocd version
```

### Step 2: Login to ArgoCD

```bash
# Get admin password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

# Login (if using port-forward)
argocd login localhost:8080 \
  --username admin \
  --password $ARGOCD_PASSWORD \
  --insecure

# OR login (if using LoadBalancer)
ARGOCD_SERVER=$(kubectl get svc argocd-server -n argocd \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
argocd login $ARGOCD_SERVER \
  --username admin \
  --password $ARGOCD_PASSWORD \
  --insecure
```

### Step 3: Add Your Git Repository

#### For Public Repository:

```bash
argocd repo add https://github.com/YOUR_USERNAME/sample-devops-agent-eks-workshop.git
```

#### For Private Repository:

```bash
# Create GitHub Personal Access Token first:
# https://github.com/settings/tokens
# Scopes needed: repo (all)

argocd repo add https://github.com/YOUR_USERNAME/sample-devops-agent-eks-workshop.git \
  --username YOUR_GITHUB_USERNAME \
  --password YOUR_GITHUB_TOKEN
```

### Step 4: Verify Repository

```bash
# List repositories
argocd repo list

# You should see your repository with CONNECTION STATUS: Successful
```

### Step 5: Create Application via CLI

```bash
argocd app create retail-ui \
  --repo https://github.com/YOUR_USERNAME/sample-devops-agent-eks-workshop.git \
  --path helm-charts/ui \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace ui \
  --sync-policy automated \
  --auto-prune \
  --self-heal \
  --sync-option CreateNamespace=true
```

### Step 6: Verify Application

```bash
# List applications
argocd app list

# Get application details
argocd app get retail-ui

# Watch sync status
argocd app sync retail-ui --watch
```

---

## Method 3: Configure via Kubernetes Manifests (GitOps Way)

### Step 1: Create Application Manifest

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
```

### Step 2: Apply the Manifest

```bash
kubectl apply -f argocd-apps/ui-app.yaml
```

### Step 3: Verify

```bash
# Check application status
kubectl get applications -n argocd

# Or via ArgoCD CLI
argocd app list
```

---

## Create Applications for All Services

### Quick Script to Create All Apps

Create `create-all-apps.sh`:

```bash
#!/bin/bash

# Replace with your GitHub username
GITHUB_USERNAME="YOUR_USERNAME"
REPO_URL="https://github.com/${GITHUB_USERNAME}/sample-devops-agent-eks-workshop.git"

# Services to deploy
SERVICES=("ui" "catalog" "carts" "orders" "checkout")

for service in "${SERVICES[@]}"; do
  echo "Creating application for $service..."
  
  argocd app create retail-$service \
    --repo $REPO_URL \
    --path helm-charts/$service \
    --dest-server https://kubernetes.default.svc \
    --dest-namespace $service \
    --sync-policy automated \
    --auto-prune \
    --self-heal \
    --sync-option CreateNamespace=true
  
  echo "✅ Created retail-$service"
done

echo ""
echo "All applications created!"
echo "View them at: https://localhost:8080/applications"
```

Make it executable and run:

```bash
chmod +x create-all-apps.sh
./create-all-apps.sh
```

---

## Verify Everything is Working

### Check Application Status

```bash
# Via CLI
argocd app list

# Expected output:
# NAME         CLUSTER                         NAMESPACE  PROJECT  STATUS  HEALTH   SYNCPOLICY  CONDITIONS
# retail-ui    https://kubernetes.default.svc  ui         default  Synced  Healthy  Auto-Prune  <none>
```

### Check in UI

1. Go to https://localhost:8080/applications
2. You should see all your applications
3. Each should show:
   - **Status**: Synced (green)
   - **Health**: Healthy (green)

### Check Kubernetes Pods

```bash
# Check all namespaces
kubectl get pods --all-namespaces | grep retail

# Check specific service
kubectl get pods -n ui
kubectl get pods -n catalog
```

---

## Test Auto-Deployment

### Step 1: Make a Change

```bash
# Edit a Helm values file
cd helm-charts/ui
nano values.yaml

# Change something (e.g., replica count)
replicaCount: 2  # Change from 1 to 2

# Commit and push
git add values.yaml
git commit -m "Scale UI to 2 replicas"
git push origin main
```

### Step 2: Watch ArgoCD Sync

```bash
# ArgoCD polls Git every 3 minutes by default
# Watch the sync happen
argocd app get retail-ui --watch

# Or view in UI
open https://localhost:8080/applications/retail-ui
```

### Step 3: Verify Change Applied

```bash
# Check replica count
kubectl get deployment -n ui

# Should show 2/2 replicas
```

---

## Troubleshooting

### Issue: Repository Connection Failed

**Check credentials:**
```bash
# Test GitHub access
curl -H "Authorization: token YOUR_GITHUB_TOKEN" \
  https://api.github.com/repos/YOUR_USERNAME/sample-devops-agent-eks-workshop

# Should return repository info, not 404
```

**Re-add repository:**
```bash
# Remove old repo
argocd repo rm https://github.com/YOUR_USERNAME/sample-devops-agent-eks-workshop.git

# Add again with correct credentials
argocd repo add https://github.com/YOUR_USERNAME/sample-devops-agent-eks-workshop.git \
  --username YOUR_GITHUB_USERNAME \
  --password YOUR_GITHUB_TOKEN
```

### Issue: Application Not Syncing

**Check sync status:**
```bash
argocd app get retail-ui

# Look for errors in the output
```

**Manual sync:**
```bash
argocd app sync retail-ui
```

**Check ArgoCD logs:**
```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=50
```

### Issue: Self-Signed Certificate Error

**In browser:**
- Click "Advanced"
- Click "Proceed to localhost (unsafe)"

**In CLI:**
```bash
# Use --insecure flag
argocd login localhost:8080 --insecure
```

---

## Advanced: Enable Webhook for Instant Sync

Instead of waiting 3 minutes for polling, enable webhooks for instant deployment:

### Step 1: Expose ArgoCD Publicly

```bash
# Change to LoadBalancer
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'

# Get public URL
kubectl get svc argocd-server -n argocd
```

### Step 2: Add Webhook to GitHub

1. Go to your GitHub repo
2. Click **Settings** → **Webhooks** → **Add webhook**
3. Configure:
   ```
   Payload URL: https://YOUR_ARGOCD_URL/api/webhook
   Content type: application/json
   Secret: (leave empty or configure in ArgoCD)
   Events: Just the push event
   Active: ✅
   ```
4. Click **Add webhook**

Now changes deploy instantly instead of waiting 3 minutes!

---

## Summary

**Easiest Method: ArgoCD UI**
1. Settings → Repositories → Connect Repo
2. Applications → New App
3. Enable Auto-Sync

**CLI Method:**
```bash
argocd repo add https://github.com/YOUR_USERNAME/sample-devops-agent-eks-workshop.git
argocd app create retail-ui --repo ... --sync-policy automated
```

**GitOps Method:**
```bash
kubectl apply -f argocd-apps/ui-app.yaml
```

Choose the method that works best for you! The UI is easiest for getting started. 🚀
