#!/bin/bash
# Network Partition Rollback Script
# Removes the NetworkPolicy blocking UI -> Cart traffic

set -e

echo "=== Network Partition Rollback ==="
echo ""

# Source verification functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/verify-functions.sh" 2>/dev/null || true

# Step 1: Remove the NetworkPolicy
echo "[1/5] Removing NetworkPolicy..."
kubectl delete networkpolicy block-ui-to-carts -n carts --ignore-not-found=true

echo ""
echo "[2/5] Verifying NetworkPolicy removal..."
kubectl get networkpolicy -n carts 2>/dev/null || echo "  ✓ No NetworkPolicies in carts namespace"

# Step 3: Check pod status
echo ""
echo "[3/5] Checking pod status..."
check_pod_status "ui" "app.kubernetes.io/name=ui" 2>/dev/null || kubectl get pods -n ui --no-headers | sed 's/^/    /'
check_pod_status "carts" "app.kubernetes.io/name=carts" 2>/dev/null || kubectl get pods -n carts --no-headers | sed 's/^/    /'

# Step 4: Verify connectivity restored
echo ""
echo "[4/5] Verifying connectivity restored..."

echo ""
echo "  Testing connectivity from UI to Carts:"
UI_POD=$(kubectl get pod -n ui -l app.kubernetes.io/name=ui -o name 2>/dev/null | head -1)
if [ -n "$UI_POD" ]; then
  RESULT=$(kubectl exec -n ui $UI_POD -- curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://carts.carts.svc.cluster.local/carts 2>/dev/null || echo "failed")
  if [ "$RESULT" == "200" ] || [ "$RESULT" == "201" ]; then
    echo "    ✓ Connection restored (HTTP $RESULT)"
  elif [ "$RESULT" == "failed" ] || [ "$RESULT" == "000" ]; then
    echo "    ✗ Connection still failing"
  else
    echo "    ⚠ HTTP $RESULT"
  fi
else
  echo "    - No UI pod found"
fi

# Step 5: Check logs
echo ""
echo "[5/5] Checking application logs..."
echo ""
echo "  UI recent logs:"
kubectl logs -n ui -l app.kubernetes.io/name=ui --tail=5 2>/dev/null | sed 's/^/    /' || echo "    No logs available"

echo ""
echo "  Carts recent logs:"
kubectl logs -n carts -l app.kubernetes.io/name=carts --tail=5 2>/dev/null | sed 's/^/    /' || echo "    No logs available"

echo ""
echo "=== Rollback Complete ==="
echo ""
echo "Traffic restored: UI -> Cart service"
