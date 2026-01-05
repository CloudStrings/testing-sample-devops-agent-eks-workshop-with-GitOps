#!/bin/bash
# Catalog Service Fault Rollback

set -e

NAMESPACE="catalog"
DEPLOYMENT="catalog"
BACKUP_FILE="fault-injection/catalog-original.yaml"

echo "=== Catalog Service Fault Rollback ==="
echo ""

echo "[1/4] Cleaning up fault injection ConfigMap..."
kubectl delete configmap latency-injector-script -n $NAMESPACE --ignore-not-found=true

echo "[2/4] Removing latency injector sidecar and restoring CPU limits..."

SIDECAR_EXISTS=$(kubectl get deployment $DEPLOYMENT -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[?(@.name=="latency-injector")].name}' 2>/dev/null)

if [ -n "$SIDECAR_EXISTS" ]; then
  kubectl patch deployment $DEPLOYMENT -n $NAMESPACE --type='json' -p='[
    {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/cpu", "value": "256m"},
    {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value": "256m"},
    {"op": "remove", "path": "/spec/template/spec/containers/1"},
    {"op": "remove", "path": "/spec/template/spec/volumes/1"}
  ]' 2>/dev/null || {
    echo "  Patch failed, trying alternative approach..."
    kubectl patch deployment $DEPLOYMENT -n $NAMESPACE --type='json' -p='[
      {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/cpu", "value": "256m"},
      {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value": "256m"}
    ]'
    kubectl rollout restart deployment/$DEPLOYMENT -n $NAMESPACE
  }
else
  echo "  No sidecar found, just restoring CPU limits..."
  kubectl patch deployment $DEPLOYMENT -n $NAMESPACE --type='json' -p='[
    {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/cpu", "value": "256m"},
    {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value": "256m"}
  ]'
fi

echo "[3/4] Waiting for deployment rollout..."
kubectl rollout status deployment/$DEPLOYMENT -n $NAMESPACE --timeout=120s

echo "[4/4] Scaling deployment back to 2 replicas..."
kubectl scale deployment $DEPLOYMENT -n $NAMESPACE --replicas=2
kubectl rollout status deployment/$DEPLOYMENT -n $NAMESPACE --timeout=60s

echo ""
echo "=== Rollback Complete ==="
echo ""
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=catalog
