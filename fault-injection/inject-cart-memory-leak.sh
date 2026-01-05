#!/bin/bash
# Cart Memory Leak Injection

set -e

NAMESPACE="carts"
DEPLOYMENT="carts"
BACKUP_FILE="fault-injection/carts-original.yaml"

echo "=== Cart Memory Leak Injection ==="
echo "Target: $DEPLOYMENT in namespace $NAMESPACE"
echo ""

echo "[1/3] Backing up current deployment..."
kubectl get deployment $DEPLOYMENT -n $NAMESPACE -o yaml > $BACKUP_FILE

echo "[2/3] Creating memory leak sidecar configuration..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: memory-leak-script
  namespace: $NAMESPACE
data:
  leak-memory.sh: |
    #!/bin/sh
    echo "Starting memory leak simulation..."
    LEAK_DIR="/tmp/memleak"
    mkdir -p \$LEAK_DIR
    counter=0
    while true; do
      dd if=/dev/zero of=\$LEAK_DIR/leak_\$counter bs=1M count=10 2>/dev/null
      counter=\$((counter + 1))
      total_mb=\$((counter * 10))
      echo "\$(date): Memory leaked: \${total_mb}MB"
      sleep 5
      if [ \$total_mb -gt 150 ]; then
        sleep 1
      fi
    done
EOF

echo "[3/3] Patching deployment with memory leak sidecar..."
kubectl patch deployment $DEPLOYMENT -n $NAMESPACE --type='json' -p='[
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/resources/limits/memory",
    "value": "256Mi"
  },
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/resources/requests/memory",
    "value": "256Mi"
  },
  {
    "op": "add",
    "path": "/spec/template/spec/containers/-",
    "value": {
      "name": "memory-leaker",
      "image": "alpine:3.18",
      "command": ["/bin/sh", "-c"],
      "args": ["cp /scripts/leak-memory.sh /tmp/leak.sh && chmod +x /tmp/leak.sh && /tmp/leak.sh"],
      "resources": {
        "limits": {
          "cpu": "50m",
          "memory": "200Mi"
        },
        "requests": {
          "cpu": "10m",
          "memory": "50Mi"
        }
      },
      "volumeMounts": [
        {
          "name": "leak-script",
          "mountPath": "/scripts"
        },
        {
          "name": "leak-storage",
          "mountPath": "/tmp/memleak"
        }
      ]
    }
  },
  {
    "op": "add",
    "path": "/spec/template/spec/volumes/-",
    "value": {
      "name": "leak-script",
      "configMap": {
        "name": "memory-leak-script",
        "defaultMode": 493
      }
    }
  },
  {
    "op": "add",
    "path": "/spec/template/spec/volumes/-",
    "value": {
      "name": "leak-storage",
      "emptyDir": {
        "medium": "Memory",
        "sizeLimit": "250Mi"
      }
    }
  }
]'

echo ""
echo "Waiting for deployment rollout..."
kubectl rollout status deployment/$DEPLOYMENT -n $NAMESPACE --timeout=120s || true

echo ""
echo "=== Fault Injection Active ==="
echo ""
echo "Symptom: Intermittent cart failures, pods restarting."
echo ""
echo "Rollback: ./fault-injection/rollback-cart-memory-leak.sh"
