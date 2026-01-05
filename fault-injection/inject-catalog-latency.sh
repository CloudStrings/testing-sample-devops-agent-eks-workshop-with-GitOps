#!/bin/bash
# Catalog Service Latency Injection

set -e

NAMESPACE="catalog"
DEPLOYMENT="catalog"
BACKUP_FILE="fault-injection/catalog-original.yaml"

echo "=== Catalog Service Latency Injection ==="
echo "Target: $DEPLOYMENT in namespace $NAMESPACE"
echo ""

if [ -f "$BACKUP_FILE" ]; then
  SIDECAR_EXISTS=$(kubectl get deployment $DEPLOYMENT -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[?(@.name=="latency-injector")].name}' 2>/dev/null)
  if [ -n "$SIDECAR_EXISTS" ]; then
    echo "[1/4] Backup exists and injection appears active - keeping existing backup"
  else
    echo "[1/4] Backing up current (clean) deployment..."
    kubectl get deployment $DEPLOYMENT -n $NAMESPACE -o yaml > $BACKUP_FILE
  fi
else
  echo "[1/4] Backing up current deployment..."
  kubectl get deployment $DEPLOYMENT -n $NAMESPACE -o yaml > $BACKUP_FILE
fi

echo "[2/4] Creating latency + CPU stress sidecar configuration..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: latency-injector-script
  namespace: $NAMESPACE
data:
  inject-latency.sh: |
    #!/bin/sh
    apk add --no-cache iproute2 stress-ng >/dev/null 2>&1 || true
    tc qdisc add dev eth0 root netem delay 400ms 100ms distribution normal 2>/dev/null || \
    tc qdisc change dev eth0 root netem delay 400ms 100ms distribution normal
    echo "Latency injection active: 300-500ms"
    stress-ng --cpu 8 --cpu-load 100 --cpu-method all --aggressive --timeout 0 &
    while true; do
      echo "\$(date): Latency + CPU stress running"
      sleep 30
    done
EOF

echo "[3/4] Patching deployment with fault injection..."
kubectl patch deployment $DEPLOYMENT -n $NAMESPACE --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/resources/limits/cpu",
    "value": "128m"
  },
  {
    "op": "replace", 
    "path": "/spec/template/spec/containers/0/resources/requests/cpu",
    "value": "128m"
  },
  {
    "op": "add",
    "path": "/spec/template/spec/containers/-",
    "value": {
      "name": "latency-injector",
      "image": "alpine:3.18",
      "command": ["/bin/sh", "-c"],
      "args": ["cp /scripts/inject-latency.sh /tmp/inject.sh && chmod +x /tmp/inject.sh && /tmp/inject.sh"],
      "securityContext": {
        "capabilities": {
          "add": ["NET_ADMIN"]
        }
      },
      "resources": {
        "limits": {
          "cpu": "4000m",
          "memory": "512Mi"
        },
        "requests": {
          "cpu": "2000m", 
          "memory": "256Mi"
        }
      },
      "volumeMounts": [
        {
          "name": "latency-script",
          "mountPath": "/scripts"
        }
      ]
    }
  },
  {
    "op": "add",
    "path": "/spec/template/spec/volumes/-",
    "value": {
      "name": "latency-script",
      "configMap": {
        "name": "latency-injector-script",
        "defaultMode": 493
      }
    }
  }
]'

echo "[4/4] Waiting for deployment rollout..."
kubectl rollout status deployment/$DEPLOYMENT -n $NAMESPACE --timeout=120s

echo ""
echo "=== Fault Injection Active ==="
echo ""
echo "Symptom: Product pages are loading slowly."
echo ""
echo "Rollback: ./fault-injection/rollback-catalog.sh"
