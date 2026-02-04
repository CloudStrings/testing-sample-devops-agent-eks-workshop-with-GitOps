#!/bin/bash

# ArgoCD App of Apps Setup Script
# This creates a parent app that manages all child apps

set -e

echo "=========================================="
echo "ArgoCD App of Apps Setup"
echo "=========================================="
echo ""

# Get GitHub username
read -p "Enter your GitHub username: " GITHUB_USERNAME
REPO_URL="https://github.com/${GITHUB_USERNAME}/sample-devops-agent-eks-workshop.git"

echo ""
echo "Creating directory structure..."

# Create directory for ArgoCD app manifests
mkdir -p argocd-apps

# Create individual app manifests
SERVICES=("ui" "catalog" "carts" "orders" "checkout")

for service in "${SERVICES[@]}"; do
  echo "Creating manifest for $service..."
  
  cat > argocd-apps/${service}-app.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: retail-${service}
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  
  source:
    repoURL: ${REPO_URL}
    targetRevision: main
    path: helm-charts/${service}
    helm:
      valueFiles:
        - values.yaml
  
  destination:
    server: https://kubernetes.default.svc
    namespace: ${service}
  
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
done

# Create parent "App of Apps"
echo ""
echo "Creating parent App of Apps..."

cat > argocd-apps/app-of-apps.yaml << EOF
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
    repoURL: ${REPO_URL}
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

echo ""
echo "✅ Manifests created in argocd-apps/"
echo ""
echo "Next steps:"
echo "1. Review the manifests: ls -la argocd-apps/"
echo "2. Commit to Git:"
echo "   git add argocd-apps/"
echo "   git commit -m 'Add ArgoCD App of Apps configuration'"
echo "   git push origin main"
echo ""
echo "3. Deploy the parent app:"
echo "   kubectl apply -f argocd-apps/app-of-apps.yaml"
echo ""
echo "4. Watch it create all child apps:"
echo "   argocd app list"
echo "   argocd app get retail-store-apps"
echo ""
echo "=========================================="
