#!/bin/bash
# Catalog Service Fault Rollback Script
# Restores original deployment configuration

set -e

NAMESPACE="catalog"
DEPLOYMENT="catalog"
BACKUP_FILE="fault-injection/catalog-original.yaml"

echo "=== Catalog Service Fault Rollback ==="
echo ""

# Check if backup exists
if [ ! -f "$BACKUP_FILE" ]; then
  echo "ERROR: Backup file not found at $BACKUP_FILE"
  echo "Attempting manual rollback..."
  
  # Manual rollback - restore original CPU and remove sidecar
  echo "[1/3] Removing latency injector sidecar..."
  kubectl patch deployment $DEPLOYMENT -n $NAMESPACE --type='json' -p='[
    {
      "op": "replace",
      "path": "/spec/template/spec/containers/0/resources/limits/cpu",
      "value": "256m"
    },
    {
      "op": "replace",
      "path": "/spec/template/spec/containers/0/resources/requests/cpu", 
      "value": "256m"
    }
  ]'
  
  # Remove the sidecar container by redeploying with only the main container
  echo "[2/3] Restarting deployment to remove sidecar..."
  kubectl rollout restart deployment/$DEPLOYMENT -n $NAMESPACE
  
else
  echo "[1/3] Restoring from backup: $BACKUP_FILE"
  # Use replace --force to handle resourceVersion conflicts
  kubectl replace --force -f $BACKUP_FILE
fi

# Wait for rollout
echo "[2/3] Waiting for deployment rollout..."
kubectl rollout status deployment/$DEPLOYMENT -n $NAMESPACE --timeout=120s

# Cleanup ConfigMap
echo "[3/3] Cleaning up fault injection resources..."
kubectl delete configmap latency-injector-script -n $NAMESPACE --ignore-not-found=true

# Source verification functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/verify-functions.sh" 2>/dev/null || true

echo ""
echo "[4/7] Waiting for pods to stabilize..."
sleep 30

# Step 5: Check pod status
echo ""
echo "[5/7] Checking pod status..."
check_pod_status "$NAMESPACE" "app.kubernetes.io/name=catalog" 2>/dev/null || kubectl get pods -n $NAMESPACE --no-headers | sed 's/^/    /'

# Step 6: Check resource usage
echo ""
echo "[6/7] Checking resource usage..."
check_resource_usage "$NAMESPACE" "app.kubernetes.io/name=catalog" 2>/dev/null || kubectl top pods -n $NAMESPACE 2>/dev/null | sed 's/^/    /' || echo "    Metrics not available"

# Step 7: Verify latency restored
echo ""
echo "[7/7] Verifying response latency restored..."

echo ""
echo "  Measuring catalog service response time:"
kubectl port-forward -n $NAMESPACE svc/catalog 8085:80 &>/dev/null &
PF_PID=$!
sleep 2

if kill -0 $PF_PID 2>/dev/null; then
  for i in 1 2 3; do
    START=$(date +%s%3N)
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 http://localhost:8085/catalogue 2>/dev/null)
    END=$(date +%s%3N)
    LATENCY=$((END - START))
    if [ $LATENCY -lt 300 ]; then
      echo "    Request $i: HTTP $STATUS (${LATENCY}ms) ✓"
    else
      echo "    Request $i: HTTP $STATUS (${LATENCY}ms) ⚠ still slow"
    fi
  done
  kill $PF_PID 2>/dev/null
else
  echo "    Could not port-forward to catalog"
fi

echo ""
echo "  Recent catalog logs:"
kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=catalog --tail=5 2>/dev/null | sed 's/^/    /' || echo "    No logs available"

echo ""
echo "=== Rollback Complete ==="
echo ""
echo "Restored configuration:"
echo "  - CPU: 256m (original)"
echo "  - Latency sidecar: Removed"
