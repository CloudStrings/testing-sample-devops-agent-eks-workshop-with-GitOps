# ArgoCD App of Apps Troubleshooting Guide

## Current Situation

You're seeing only the parent app (`retail-store-apps`) but not the child apps. The "broken pipe" error from port-forward is normal and can be ignored.

## Root Cause Analysis

The App of Apps pattern works like this:
```
Parent App (retail-store-apps)
  ↓ watches argocd-apps/ directory in Git
  ↓ creates child Application resources
  ↓
Child Apps (retail-ui, retail-catalog, etc.)
  ↓ watch helm-charts/ directories in Git
  ↓ deploy to Kubernetes
```

If child apps aren't appearing, it's usually because:
1. ✅ **argocd-apps/ directory not pushed to GitHub** (most common)
2. Parent app hasn't synced yet
3. Parent app has errors
4. Repository connection issues

---

## Step 1: Verify Files Are Pushed to GitHub

### Check Local Git Status

```bash
cd ~/aws-workshops/sample-devops-agent-eks-workshop

# Check if argocd-apps/ is committed
git status

# Check commit history
git log --oneline -5

# Check if pushed to remote
git log origin/main..HEAD
# If this shows commits, they haven't been pushed yet!
```

### Push to GitHub (If Needed)

```bash
# If argocd-apps/ shows as untracked or modified:
git add argocd-apps/
git commit -m "Add ArgoCD App of Apps configuration"
git push origin main
```

### Verify on GitHub

Open your browser and check:
```
https://github.com/CloudStrings/sample-devops-agent-eks-workshop/tree/main/argocd-apps
```

You should see:
- ✅ app-of-apps.yaml
- ✅ ui-app.yaml
- ✅ catalog-app.yaml
- ✅ carts-app.yaml
- ✅ orders-app.yaml
- ✅ checkout-app.yaml

**If you don't see these files on GitHub, that's your problem!** ArgoCD can't create child apps from files that don't exist in Git.

---

## Step 2: Check Parent App Status

### Via CLI

```bash
# Restart port-forward if needed (ignore "broken pipe" errors)
kubectl port-forward svc/argocd-server -n argocd 8080:443 &

# Get detailed parent app status
argocd app get retail-store-apps

# Look for:
# - SYNC STATUS: Should be "Synced" (green)
# - HEALTH STATUS: Should be "Healthy" (green)
# - LAST SYNC: Should be recent
# - Any error messages
```

### Expected Output (Healthy)

```
Name:               retail-store-apps
Project:            default
Server:             https://kubernetes.default.svc
Namespace:          argocd
URL:                https://localhost:8080/applications/retail-store-apps
Repo:               https://github.com/CloudStrings/sample-devops-agent-eks-workshop.git
Target:             main
Path:               argocd-apps
SyncWindow:         Sync Allowed
Sync Policy:        Automated (Prune)
Sync Status:        Synced to main (abc1234)
Health Status:      Healthy

GROUP              KIND         NAMESPACE  NAME              STATUS  HEALTH   HOOK  MESSAGE
argoproj.io        Application  argocd     retail-ui         Synced  Healthy        
argoproj.io        Application  argocd     retail-catalog    Synced  Healthy        
argoproj.io        Application  argocd     retail-carts      Synced  Healthy        
argoproj.io        Application  argocd     retail-orders     Synced  Healthy        
argoproj.io        Application  argocd     retail-checkout   Synced  Healthy
```

### If You See "OutOfSync"

The parent app hasn't synced yet. Force a sync:

```bash
argocd app sync retail-store-apps --force
```

---

## Step 3: Check Repository Connection

### Verify Repository is Registered

```bash
argocd repo list

# Should show:
# REPO                                                                    TYPE  NAME  STATUS      MESSAGE
# https://github.com/CloudStrings/sample-devops-agent-eks-workshop.git  git         Successful
```

### If Repository Shows "Failed"

Re-add the repository:

```bash
# For public repo
argocd repo add https://github.com/CloudStrings/sample-devops-agent-eks-workshop.git

# For private repo (if needed)
argocd repo add https://github.com/CloudStrings/sample-devops-agent-eks-workshop.git \
  --username CloudStrings \
  --password YOUR_GITHUB_TOKEN
```

---

## Step 4: Check ArgoCD Logs

### Application Controller Logs

```bash
# Check for errors in application controller
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=100 | grep retail-store-apps

# Look for errors like:
# - "failed to get git client"
# - "authentication required"
# - "repository not found"
# - "path does not exist"
```

### Repo Server Logs

```bash
# Check for Git sync errors
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server --tail=100
```

---

## Step 5: Manual Sync and Verification

### Force Sync Parent App

```bash
# Force sync (ignores cache)
argocd app sync retail-store-apps --force

# Watch the sync happen
argocd app sync retail-store-apps --watch
```

### Check Kubernetes Resources

```bash
# List all Application resources in argocd namespace
kubectl get applications -n argocd

# You should see:
# NAME                  SYNC STATUS   HEALTH STATUS
# retail-store-apps     Synced        Healthy
# retail-ui             Synced        Healthy
# retail-catalog        Synced        Healthy
# retail-carts          Synced        Healthy
# retail-orders         Synced        Healthy
# retail-checkout       Synced        Healthy
```

### If Only Parent App Shows

```bash
# Check if child Application resources exist
kubectl get applications -n argocd -o yaml | grep "name: retail-"

# If no child apps, check parent app for errors
kubectl describe application retail-store-apps -n argocd
```

---

## Step 6: Verify ArgoCD Can Access GitHub

### Test GitHub Access from ArgoCD

```bash
# Get into ArgoCD repo-server pod
kubectl exec -it -n argocd \
  $(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-repo-server -o name | head -1) \
  -- sh

# Inside the pod, test Git access
git ls-remote https://github.com/CloudStrings/sample-devops-agent-eks-workshop.git

# Should show refs/heads/main and other branches
# If it fails, there's a network or authentication issue

# Exit the pod
exit
```

---

## Step 7: Check ArgoCD Sync Settings

### Verify Sync Policy

```bash
# Check parent app sync policy
argocd app get retail-store-apps -o yaml | grep -A 10 syncPolicy

# Should show:
#   syncPolicy:
#     automated:
#       prune: true
#       selfHeal: true
```

### Check Sync Interval

ArgoCD polls Git every 3 minutes by default. If you just pushed changes, wait 3 minutes or force sync.

```bash
# Force immediate sync
argocd app sync retail-store-apps
```

---

## Common Issues and Solutions

### Issue 1: "argocd-apps/ directory not found"

**Symptom:**
```
Parent app shows: ComparisonError: path 'argocd-apps' does not exist
```

**Solution:**
```bash
# Verify directory exists locally
ls -la argocd-apps/

# Commit and push
git add argocd-apps/
git commit -m "Add ArgoCD apps"
git push origin main

# Sync parent app
argocd app sync retail-store-apps
```

### Issue 2: "Authentication required"

**Symptom:**
```
Repository connection failed: authentication required
```

**Solution:**
```bash
# For private repos, add credentials
argocd repo add https://github.com/CloudStrings/sample-devops-agent-eks-workshop.git \
  --username CloudStrings \
  --password YOUR_GITHUB_TOKEN

# Sync parent app
argocd app sync retail-store-apps
```

### Issue 3: Child apps created but not syncing

**Symptom:**
```
argocd app list shows child apps but they're "OutOfSync"
```

**Solution:**
```bash
# Sync each child app
argocd app sync retail-ui
argocd app sync retail-catalog
argocd app sync retail-carts
argocd app sync retail-orders
argocd app sync retail-checkout

# Or sync all at once
argocd app sync -l app.kubernetes.io/instance=retail-store-apps
```

### Issue 4: "helm-charts/ directory not found"

**Symptom:**
```
Child apps show: ComparisonError: path 'helm-charts/ui' does not exist
```

**Solution:**
```bash
# Verify helm-charts exist
ls -la helm-charts/

# If missing, you need to create them or use the original repo structure
# The sample repo should already have helm-charts/
```

---

## Quick Diagnostic Script

Run this to check everything:

```bash
#!/bin/bash

echo "=== ArgoCD App of Apps Diagnostics ==="
echo ""

echo "1. Checking local Git status..."
cd ~/aws-workshops/sample-devops-agent-eks-workshop
git status | grep argocd-apps
echo ""

echo "2. Checking if pushed to GitHub..."
git log origin/main..HEAD --oneline
echo ""

echo "3. Checking ArgoCD applications..."
kubectl get applications -n argocd
echo ""

echo "4. Checking parent app status..."
argocd app get retail-store-apps | grep -E "Sync Status|Health Status|Repo|Path"
echo ""

echo "5. Checking repository connection..."
argocd repo list | grep CloudStrings
echo ""

echo "6. Checking for errors in logs..."
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=20 | grep -i error
echo ""

echo "=== End Diagnostics ==="
```

---

## Expected Final State

When everything is working correctly:

### ArgoCD App List
```bash
$ argocd app list

NAME                CLUSTER                         NAMESPACE  PROJECT  STATUS  HEALTH   SYNCPOLICY  CONDITIONS
retail-store-apps   https://kubernetes.default.svc  argocd     default  Synced  Healthy  Auto-Prune  <none>
retail-ui           https://kubernetes.default.svc  ui         default  Synced  Healthy  Auto-Prune  <none>
retail-catalog      https://kubernetes.default.svc  catalog    default  Synced  Healthy  Auto-Prune  <none>
retail-carts        https://kubernetes.default.svc  carts      default  Synced  Healthy  Auto-Prune  <none>
retail-orders       https://kubernetes.default.svc  orders     default  Synced  Healthy  Auto-Prune  <none>
retail-checkout     https://kubernetes.default.svc  checkout   default  Synced  Healthy  Auto-Prune  <none>
```

### Kubernetes Applications
```bash
$ kubectl get applications -n argocd

NAME                  SYNC STATUS   HEALTH STATUS
retail-store-apps     Synced        Healthy
retail-ui             Synced        Healthy
retail-catalog        Synced        Healthy
retail-carts          Synced        Healthy
retail-orders         Synced        Healthy
retail-checkout       Synced        Healthy
```

### Running Pods
```bash
$ kubectl get pods --all-namespaces | grep retail

ui          retail-ui-xxxxx          1/1     Running
catalog     retail-catalog-xxxxx     1/1     Running
carts       retail-carts-xxxxx       1/1     Running
orders      retail-orders-xxxxx      1/1     Running
checkout    retail-checkout-xxxxx    1/1     Running
```

---

## Next Steps After Fixing

Once all apps are showing and synced:

1. **Test Auto-Deployment**
   ```bash
   # Edit a Helm chart
   cd helm-charts/ui
   nano values.yaml
   # Change replicaCount: 2
   
   git add values.yaml
   git commit -m "Scale UI to 2 replicas"
   git push origin main
   
   # Watch ArgoCD auto-deploy
   argocd app get retail-ui --watch
   ```

2. **Access ArgoCD UI**
   ```bash
   kubectl port-forward svc/argocd-server -n argocd 8080:443
   open https://localhost:8080
   ```

3. **Monitor Applications**
   ```bash
   # Watch all apps
   watch -n 5 'argocd app list'
   
   # Or in UI
   # Click on retail-store-apps to see the tree view
   ```

---

## Still Having Issues?

If you've tried all the above and still don't see child apps:

1. **Delete and recreate parent app:**
   ```bash
   kubectl delete application retail-store-apps -n argocd
   kubectl apply -f argocd-apps/app-of-apps.yaml
   ```

2. **Check ArgoCD version:**
   ```bash
   argocd version
   # Should be v2.8+ for best App of Apps support
   ```

3. **Restart ArgoCD components:**
   ```bash
   kubectl rollout restart deployment argocd-application-controller -n argocd
   kubectl rollout restart deployment argocd-repo-server -n argocd
   ```

4. **Enable debug logging:**
   ```bash
   kubectl set env deployment/argocd-application-controller -n argocd ARGOCD_LOG_LEVEL=debug
   kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller -f
   ```

---

## Summary Checklist

- [ ] argocd-apps/ directory exists locally
- [ ] All 6 YAML files exist (app-of-apps.yaml + 5 child apps)
- [ ] Files have correct GitHub username (CloudStrings)
- [ ] Files are committed to Git
- [ ] Files are pushed to GitHub (verify on github.com)
- [ ] Repository is registered in ArgoCD
- [ ] Parent app is created (retail-store-apps)
- [ ] Parent app is synced
- [ ] Child apps appear in `argocd app list`
- [ ] All apps show "Synced" and "Healthy"

**Most common fix:** Push argocd-apps/ to GitHub and sync parent app! 🚀
