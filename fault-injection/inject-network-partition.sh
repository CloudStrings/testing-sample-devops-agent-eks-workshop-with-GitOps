#!/bin/bash
# Network Partition Injection - Blocks UI ingress

set -e

echo "=== Network Partition Injection ==="
echo ""

NAMESPACE="ui"

echo "[1/2] Cleaning up old NetworkPolicy..."
kubectl delete networkpolicy deny-ingress-to-ui -n $NAMESPACE 2>/dev/null || true

echo ""
echo "[2/2] Applying NetworkPolicy..."

cat <<'POLICY' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-ingress-to-ui
  namespace: ui
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: ui
  policyTypes:
  - Ingress
  ingress: []
POLICY

echo ""
kubectl get networkpolicy -n $NAMESPACE

echo ""
echo "=== Fault Injection Active ==="
echo ""
echo "Symptom: Website is unreachable."
echo ""
echo "Rollback: ./fault-injection/rollback-network-partition.sh"
