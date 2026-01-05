#!/bin/bash
# DynamoDB Stress Test Rollback

set -e

NAMESPACE="carts"

echo "=== DynamoDB Stress Test Rollback ==="
echo ""

echo "[1/2] Deleting stress test pod..."
kubectl delete pod dynamodb-stress-test -n $NAMESPACE --ignore-not-found=true
echo "  ✓ Stress pod deleted"

echo "[2/2] Deleting stress test ConfigMap..."
kubectl delete configmap dynamodb-stress-script -n $NAMESPACE --ignore-not-found=true
echo "  ✓ ConfigMap deleted"

echo ""
echo "=== Rollback Complete ==="
