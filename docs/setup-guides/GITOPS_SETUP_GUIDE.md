# GitOps Setup Guide - Automated Deployments

## Overview

You have several options for automated deployments when you make changes to your repo:

1. **ArgoCD** (Kubernetes-native GitOps) - Best for application changes
2. **Flux CD** (Alternative to ArgoCD) - Similar to ArgoCD
3. **GitHub Actions + Terraform Cloud** - Best for infrastructure changes
4. **GitHub Actions + kubectl** - Simple application deployments

## Recommended Approach: Hybrid Strategy

For this workshop, I recommend a **two-tier approach**:

- **Terraform** → Infrastructure changes (manual or via GitHub Actions)
- **ArgoCD** → Application deployments (automated from your Git repo)

---

## Part 1: Fork and Setup Your Repository

### Step 1: Fork the Repository to Your GitHub

```bash
# Option A: Via GitHub Web UI
# 1. Go to: https://github.com/aws-samples/sample-devops-agent-eks-workshop
# 2. Click "Fork" button (top right)
# 3. Choose your account
# 4. Click "Create fork"

# Option B: Via GitHub CLI (if installed)
gh repo fork aws-samples/sample-devops-agent-eks-workshop --clone=false
```

### Step 2: Update Your Local Repository

```bash
# Navigate to your local clone
cd sample-devops-agent-eks-workshop

# Add your fork as a new remote
git remote add myfork https://github.com/YOUR_USERNAME/sample-devops-agent-eks-workshop.git

# Verify remotes
git remote -v
# Should show:
# origin    https://github.com/aws-samples/sample-devops-agent-eks-workshop.git (fetch)
# myfork    https://github.com/YOUR_USERNAME/sample-devops-agent-eks-workshop.git (fetch)

# Push to your fork
git push myfork main
```

### Step 3: Set Your Fork as Default

```bash
# Make your fork the default remote
git remote rename origin upstream
git remote rename myfork origin

# Verify
git remote -v
# Should show:
# origin     https://github.com/YOUR_USERNAME/sample-devops-agent-eks-workshop.git
# upstream   https://github.com/aws-samples/sample-devops-agent-eks-workshop.git
```

---

## Part 2: Setup ArgoCD for Application Deployments

### Why ArgoCD?

- ✅ Automatically syncs Kubernetes resources from Git
- ✅ Monitors your repo for changes
- ✅ Provides UI for deployment status
- ✅ Supports rollback and diff views
- ✅ Native Kubernetes integration

### Step 1: Install ArgoCD on Your EKS Cluster

```bash
# Create ArgoCD namespace
kubectl create namespace argocd

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready (takes 2-3 minutes)
kubectl wait --for=condition=available --timeout=300s \
  deployment/argocd-server -n argocd

# Verify installation
kubectl get pods -n argocd
```

### Step 2: Access ArgoCD UI

```bash
# Get initial admin password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

echo "ArgoCD Admin Password: $ARGOCD_PASSWORD"

# Port forward to access UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Open in browser
open https://localhost:8080

# Login with:
# Username: admin
# Password: (from above)
```

**Alternative: Expose via LoadBalancer**

```bash
# Change service type to LoadBalancer
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'

# Get LoadBalancer URL (takes 2-3 minutes)
kubectl get svc argocd-server -n argocd

# Access via the EXTERNAL-IP
```

### Step 3: Install ArgoCD CLI (Optional but Recommended)

```bash
# macOS
brew install argocd

# Verify
argocd version
```

### Step 4: Login to ArgoCD via CLI

```bash
# If using port-forward
argocd login localhost:8080 --username admin --password $ARGOCD_PASSWORD --insecure

# If using LoadBalancer
ARGOCD_SERVER=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
argocd login $ARGOCD_SERVER --username admin --password $ARGOCD_PASSWORD --insecure
```

---

## Part 3: Configure ArgoCD to Watch Your Repository

### Step 1: Add Your Git Repository to ArgoCD

```bash
# Add your forked repository
argocd repo add https://github.com/YOUR_USERNAME/sample-devops-agent-eks-workshop.git \
  --username YOUR_GITHUB_USERNAME \
  --password YOUR_GITHUB_TOKEN

# Verify repository is added
argocd repo list
```

**To create a GitHub Personal Access Token:**
1. Go to: https://github.com/settings/tokens
2. Click "Generate new token (classic)"
3. Select scopes: `repo` (all)
4. Click "Generate token"
5. Copy the token (you won't see it again!)

### Step 2: Create ArgoCD Applications

Create a file `argocd-apps/ui-app.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: retail-ui
  namespace: argocd
spec:
  project: default
  
  # Source: Your Git repository
  source:
    repoURL: https://github.com/YOUR_USERNAME/sample-devops-agent-eks-workshop.git
    targetRevision: main
    path: helm-charts/ui  # Path to Helm chart
    helm:
      valueFiles:
        - values.yaml
  
  # Destination: Your EKS cluster
  destination:
    server: https://kubernetes.default.svc
    namespace: ui
  
  # Sync policy: Automated
  syncPolicy:
    automated:
      prune: true      # Delete resources not in Git
      selfHeal: true   # Auto-sync if cluster state drifts
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

Create similar files for other services:

```bash
# Create directory for ArgoCD app definitions
mkdir -p argocd-apps

# Create app definitions for each service
cat > argocd-apps/catalog-app.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: retail-catalog
  namespace: argocd
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
    syncOptions:
      - CreateNamespace=true
EOF

# Repeat for carts, orders, checkout services
```

### Step 3: Apply ArgoCD Applications

```bash
# Apply all application definitions
kubectl apply -f argocd-apps/

# Verify applications are created
argocd app list

# Watch sync status
argocd app get retail-ui
```

---

## Part 4: Test Automated Deployment

### Step 1: Make a Change to Your Application

```bash
# Example: Update UI service image tag
cd helm-charts/ui

# Edit values.yaml
nano values.yaml

# Change:
image:
  tag: "latest"
# To:
image:
  tag: "v1.0.1"

# Commit and push
git add values.yaml
git commit -m "Update UI image to v1.0.1"
git push origin main
```

### Step 2: Watch ArgoCD Auto-Deploy

```bash
# ArgoCD polls Git every 3 minutes by default
# Watch the sync happen
argocd app get retail-ui --watch

# Or view in UI
open https://localhost:8080
```

### Step 3: Verify Deployment

```bash
# Check pod image
kubectl get pods -n ui -o jsonpath='{.items[0].spec.containers[0].image}'

# Check rollout status
kubectl rollout status deployment/ui -n ui
```

---

## Part 5: Setup GitHub Actions for Infrastructure Changes (Optional)

For Terraform infrastructure changes, use GitHub Actions:

### Step 1: Create GitHub Actions Workflow

Create `.github/workflows/terraform.yml`:

```yaml
name: Terraform Infrastructure

on:
  push:
    branches:
      - main
    paths:
      - 'terraform/**'
  pull_request:
    branches:
      - main
    paths:
      - 'terraform/**'

jobs:
  terraform:
    name: Terraform Plan/Apply
    runs-on: ubuntu-latest
    
    defaults:
      run:
        working-directory: terraform/eks
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v3
      
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2
        with:
          terraform_version: 1.5.0
      
      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1
      
      - name: Terraform Init
        run: terraform init
      
      - name: Terraform Plan
        run: terraform plan -out=tfplan
      
      - name: Terraform Apply
        if: github.ref == 'refs/heads/main' && github.event_name == 'push'
        run: terraform apply -auto-approve tfplan
```

### Step 2: Add AWS Credentials to GitHub Secrets

1. Go to your GitHub repo: `https://github.com/YOUR_USERNAME/sample-devops-agent-eks-workshop`
2. Click **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Add:
   - Name: `AWS_ACCESS_KEY_ID`, Value: `your-access-key`
   - Name: `AWS_SECRET_ACCESS_KEY`, Value: `your-secret-key`

### Step 3: Test GitHub Actions

```bash
# Make a change to Terraform
cd terraform/eks
nano variables.tf

# Commit and push
git add variables.tf
git commit -m "Update Terraform variables"
git push origin main

# Watch GitHub Actions run
# Go to: https://github.com/YOUR_USERNAME/sample-devops-agent-eks-workshop/actions
```

---

## Part 6: Advanced ArgoCD Configuration

### Enable Webhook for Instant Sync (Instead of 3-min Polling)

```bash
# Get ArgoCD webhook URL
ARGOCD_SERVER=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Webhook URL: https://$ARGOCD_SERVER/api/webhook"

# Add webhook to GitHub:
# 1. Go to your repo → Settings → Webhooks → Add webhook
# 2. Payload URL: https://ARGOCD_SERVER/api/webhook
# 3. Content type: application/json
# 4. Secret: (leave empty or set in ArgoCD)
# 5. Events: Just the push event
# 6. Click "Add webhook"
```

### Create App of Apps Pattern

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

This creates a "parent" app that manages all other apps.

---

## Workflow Summary

### For Application Changes (Helm Charts)

```
1. Edit helm-charts/*/values.yaml
2. git commit && git push
3. ArgoCD detects change (3 min or instant with webhook)
4. ArgoCD syncs to cluster
5. Pods restart with new config
```

### For Infrastructure Changes (Terraform)

```
1. Edit terraform/**/*.tf
2. git commit && git push
3. GitHub Actions runs terraform plan
4. If on main branch, terraform apply runs
5. Infrastructure updated
```

---

## Monitoring and Troubleshooting

### ArgoCD UI

```bash
# View all applications
open https://localhost:8080/applications

# Check sync status, health, and history
# Click on any app for detailed view
```

### ArgoCD CLI

```bash
# List all apps
argocd app list

# Get app details
argocd app get retail-ui

# Sync manually
argocd app sync retail-ui

# View logs
argocd app logs retail-ui

# Rollback to previous version
argocd app rollback retail-ui
```

### Troubleshooting

```bash
# Check ArgoCD controller logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller

# Check repo server logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server

# Check sync status
kubectl get applications -n argocd
```

---

## Cost Considerations

**ArgoCD Resources:**
- Minimal overhead (~200MB memory, 0.1 CPU)
- No additional AWS costs
- Runs on existing EKS nodes

**GitHub Actions:**
- Free tier: 2,000 minutes/month
- Terraform runs: ~5 minutes per run
- ~400 free runs per month

---

## Alternative: Simpler Approach with GitHub Actions Only

If ArgoCD seems too complex, use GitHub Actions for everything:

```yaml
name: Deploy to EKS

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Configure AWS
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1
      
      - name: Update kubeconfig
        run: aws eks update-kubeconfig --name retail-store --region us-east-1
      
      - name: Deploy with Helm
        run: |
          helm upgrade --install ui ./helm-charts/ui -n ui --create-namespace
          helm upgrade --install catalog ./helm-charts/catalog -n catalog --create-namespace
          # ... repeat for other services
```

---

## Recommended Setup for This Workshop

**Start Simple:**
1. ✅ Fork the repo
2. ✅ Deploy infrastructure with Terraform (manual)
3. ✅ Install ArgoCD
4. ✅ Configure ArgoCD to watch your fork
5. ✅ Make application changes and watch auto-deploy

**Later Add:**
- GitHub Actions for Terraform
- Webhooks for instant sync
- App of Apps pattern

---

## Next Steps

1. Fork the repository
2. Update your local git remotes
3. Deploy infrastructure with Terraform
4. Install ArgoCD
5. Configure ArgoCD applications
6. Test by making a change!

---

**Happy GitOps! 🚀**
