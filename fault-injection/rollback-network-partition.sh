#!/bin/bash
# Network Partition Rollback - Removes NetworkPolicy blocking UI ingress

set -e

echo "=== Network Partition Rollback ==="
echo ""

NAMESPACE="ui"

echo "[1/2] Removing NetworkPolicy..."
kubectl delete networkpolicy deny-ingress-to-ui -n $NAMESPACE --ignore-not-found=true

echo ""
echo "[2/2] Verifying policy removal..."
kubectl get networkpolicy -n $NAMESPACE 2>/dev/null || echo "  No NetworkPolicies found"

echo ""
echo "=== Rollback Complete ==="
echo ""
echo "Website should be accessible again."
