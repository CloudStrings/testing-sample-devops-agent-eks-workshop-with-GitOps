#!/bin/bash

# Setup Helm Charts for ArgoCD GitOps
# This script sets up the hybrid Terraform + ArgoCD approach

set -e

echo "=========================================="
echo "Setting up Helm Charts for ArgoCD GitOps"
echo "=========================================="
echo ""

# Define paths
WORKSPACE_DIR="/Users/kunpil/MyProjects"
REPO_DIR="${WORKSPACE_DIR}/sample-devops-agent-eks-workshop"
RETAIL_STORE_DIR="${WORKSPACE_DIR}/retail-store-sample-app"

# Step 1: Clone retail store sample app
echo "Step 1: Cloning retail store sample app..."
if [ -d "$RETAIL_STORE_DIR" ]; then
  echo "✅ Retail store app already exists at $RETAIL_STORE_DIR"
else
  git clone https://github.com/aws-containers/retail-store-sample-app.git "$RETAIL_STORE_DIR"
  echo "✅ Cloned retail store sample app"
fi
echo ""

# Step 2: Check if helm charts exist in retail store
echo "Step 2: Checking retail store Helm charts..."
if [ -d "$RETAIL_STORE_DIR/src" ]; then
  echo "✅ Found source directory in retail store"
  ls -la "$RETAIL_STORE_DIR/src/"
else
  echo "❌ Source directory not found"
  echo "Expected: $RETAIL_STORE_DIR/src"
  exit 1
fi
echo ""

# Step 3: Create helm-charts directory in your repo
echo "Step 3: Creating helm-charts directory..."
mkdir -p "$REPO_DIR/helm-charts"
echo "✅ Created helm-charts directory"
echo ""

# Step 4: Copy Helm charts for each service
echo "Step 4: Copying Helm charts..."

# Copy UI
if [ -d "$RETAIL_STORE_DIR/src/ui/chart" ]; then
  echo "  Copying ui..."
  cp -r "$RETAIL_STORE_DIR/src/ui/chart" "$REPO_DIR/helm-charts/ui"
  echo "  ✅ Copied ui"
fi

# Copy Catalog
if [ -d "$RETAIL_STORE_DIR/src/catalog/chart" ]; then
  echo "  Copying catalog..."
  cp -r "$RETAIL_STORE_DIR/src/catalog/chart" "$REPO_DIR/helm-charts/catalog"
  echo "  ✅ Copied catalog"
fi

# Copy Carts (note: source is 'cart' not 'carts')
if [ -d "$RETAIL_STORE_DIR/src/cart/chart" ]; then
  echo "  Copying carts (from cart)..."
  cp -r "$RETAIL_STORE_DIR/src/cart/chart" "$REPO_DIR/helm-charts/carts"
  echo "  ✅ Copied carts"
fi

# Copy Orders
if [ -d "$RETAIL_STORE_DIR/src/orders/chart" ]; then
  echo "  Copying orders..."
  cp -r "$RETAIL_STORE_DIR/src/orders/chart" "$REPO_DIR/helm-charts/orders"
  echo "  ✅ Copied orders"
fi

# Copy Checkout
if [ -d "$RETAIL_STORE_DIR/src/checkout/chart" ]; then
  echo "  Copying checkout..."
  cp -r "$RETAIL_STORE_DIR/src/checkout/chart" "$REPO_DIR/helm-charts/checkout"
  echo "  ✅ Copied checkout"
fi
echo ""

# Step 5: Merge Terraform values with Helm values
echo "Step 5: Merging Terraform values with Helm values..."
TERRAFORM_VALUES_DIR="$REPO_DIR/terraform/eks/default/values"

if [ -d "$TERRAFORM_VALUES_DIR" ]; then
  for service in "${SERVICES[@]}"; do
    if [ -f "$TERRAFORM_VALUES_DIR/${service}.yaml" ]; then
      echo "  Merging values for $service..."
      
      # Backup original values
      cp "$REPO_DIR/helm-charts/$service/values.yaml" \
         "$REPO_DIR/helm-charts/$service/values.yaml.original"
      
      # Append Terraform values
      echo "" >> "$REPO_DIR/helm-charts/$service/values.yaml"
      echo "# Terraform-specific values merged below:" >> "$REPO_DIR/helm-charts/$service/values.yaml"
      cat "$TERRAFORM_VALUES_DIR/${service}.yaml" >> "$REPO_DIR/helm-charts/$service/values.yaml"
      
      echo "  ✅ Merged values for $service"
    else
      echo "  ⚠️  No Terraform values found for $service"
    fi
  done
else
  echo "  ⚠️  Terraform values directory not found: $TERRAFORM_VALUES_DIR"
  echo "  Skipping values merge..."
fi
echo ""

# Step 6: Verify structure
echo "Step 6: Verifying Helm charts structure..."
SERVICES=("ui" "catalog" "carts" "orders" "checkout")

for service in "${SERVICES[@]}"; do
  if [ -f "$REPO_DIR/helm-charts/$service/Chart.yaml" ]; then
    echo "  ✅ $service/Chart.yaml exists"
  else
    echo "  ❌ $service/Chart.yaml missing"
  fi
  
  if [ -f "$REPO_DIR/helm-charts/$service/values.yaml" ]; then
    echo "  ✅ $service/values.yaml exists"
  else
    echo "  ❌ $service/values.yaml missing"
  fi
done
echo ""

# Step 7: Show next steps
echo "=========================================="
echo "✅ Setup Complete!"
echo "=========================================="
echo ""
echo "Helm charts have been copied to:"
echo "  $REPO_DIR/helm-charts/"
echo ""
echo "Next steps:"
echo ""
echo "1. Review the Helm charts:"
echo "   ls -la $REPO_DIR/helm-charts/"
echo ""
echo "2. Commit and push to GitHub:"
echo "   cd $REPO_DIR"
echo "   git add helm-charts/"
echo "   git commit -m 'Add Helm charts for GitOps with ArgoCD'"
echo "   git push origin main"
echo ""
echo "3. Verify on GitHub:"
echo "   open https://github.com/CloudStrings/testing-sample-devops-agent-eks-workshop-with-GitOps/tree/main/helm-charts"
echo ""
echo "4. Sync ArgoCD apps:"
echo "   argocd app sync retail-ui retail-catalog retail-carts retail-orders retail-checkout"
echo ""
echo "5. Check app status:"
echo "   argocd app list"
echo ""
echo "=========================================="
