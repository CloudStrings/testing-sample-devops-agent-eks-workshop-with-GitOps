#!/bin/bash
# Cart Memory Leak Rollback

set -e

NAMESPACE="carts"
DEPLOYMENT="carts"
BACKUP_FILE="fault-injection/carts-original.yaml"

echo "=== Cart Memory Leak Rollback ==="
echo ""

if [ ! -f "$BACKUP_FILE" ]; then
  echo "ERROR: Backup file not found at $BACKUP_FILE"
  echo "Attempting manual rollback..."
  
  kubectl patch deployment $DEPLOYMENT -n $NAMESPACE --type='json' -p='[
    {
      "op": "replace",
      "path": "/spec/template/spec/containers/0/resources/limits/memory",
      "value": "512Mi"
    },
    {
      "op": "replace",
      "path": "/spec/template/spec/containers/0/resources/requests/memory",
      "value": "512Mi"
    }
  ]'
  
  kubectl rollout restart deployment/$DEPLOYMENT -n $NAMESPACE
else
  echo "[1/3] Restoring from backup: $BACKUP_FILE"
  kubectl replace --force -f $BACKUP_FILE
fi

echo "[2/3] Waiting for deployment rollout..."
kubectl rollout status deployment/$DEPLOYMENT -n $NAMESPACE --timeout=120s

echo "[3/3] Cleaning up fault injection resources..."
kubectl delete configmap memory-leak-script -n $NAMESPACE --ignore-not-found=true

echo ""
echo "=== Rollback Complete ==="
echo ""
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=carts
