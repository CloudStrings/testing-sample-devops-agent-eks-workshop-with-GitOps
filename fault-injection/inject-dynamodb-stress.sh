#!/bin/bash
# DynamoDB Stress Test Injection
# Deploys a stress pod that hammers DynamoDB with massive read/write requests

set -e

NAMESPACE="carts"
TABLE_NAME="retail-store-carts"
REGION="${AWS_REGION:-us-east-1}"

echo "=== DynamoDB Stress Test Injection ==="
echo ""
echo "Target Table: $TABLE_NAME"
echo "Region: $REGION"
echo ""

# Step 1: Verify table
echo "[1/4] Verifying DynamoDB table..."
TABLE_STATUS=$(aws dynamodb describe-table --table-name $TABLE_NAME --region $REGION --query 'Table.TableStatus' --output text 2>/dev/null)
if [ "$TABLE_STATUS" != "ACTIVE" ]; then
  echo "ERROR: Table $TABLE_NAME not found or not active"
  exit 1
fi
echo "  Table status: $TABLE_STATUS"

# Step 2: Create ConfigMap with Python stress script
echo "[2/4] Creating stress test ConfigMap..."
kubectl apply -f - <<'CONFIGMAP_EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: dynamodb-stress-script
  namespace: carts
data:
  stress.py: |
    import boto3
    import threading
    import time
    import random
    import string
    import os
    from concurrent.futures import ThreadPoolExecutor

    TABLE_NAME = os.environ.get('TABLE_NAME', 'retail-store-carts')
    REGION = os.environ.get('AWS_REGION', 'us-east-1')

    dynamodb = boto3.resource('dynamodb', region_name=REGION)
    table = dynamodb.Table(TABLE_NAME)

    write_count = 0
    scan_count = 0
    lock = threading.Lock()

    def generate_payload(size=2000):
        return ''.join(random.choices(string.ascii_letters + string.digits, k=size))

    def write_worker(worker_id):
        global write_count
        payload = generate_payload()
        counter = 0
        while True:
            try:
                item_id = f"stress-{worker_id}-{counter}"
                table.put_item(Item={
                    'id': item_id,
                    'data': payload,
                    'items': [],
                    'timestamp': int(time.time())
                })
                counter += 1
                with lock:
                    write_count += 1
                    if write_count % 500 == 0:
                        print(f"Total writes: {write_count}", flush=True)
            except Exception as e:
                if 'Throttl' in str(e):
                    print(f"THROTTLED on write! {e}", flush=True)
                time.sleep(0.01)

    def scan_worker(worker_id):
        global scan_count
        while True:
            try:
                response = table.scan(Limit=1000)
                with lock:
                    scan_count += 1
                    if scan_count % 100 == 0:
                        print(f"Total scans: {scan_count}", flush=True)
            except Exception as e:
                if 'Throttl' in str(e):
                    print(f"THROTTLED on scan! {e}", flush=True)
                time.sleep(0.01)

    print("=== DynamoDB Stress Test ===")
    print(f"Table: {TABLE_NAME}")
    print(f"Region: {REGION}")
    print("Starting 20 write workers and 20 scan workers...")
    print("")

    with ThreadPoolExecutor(max_workers=40) as executor:
        for i in range(20):
            executor.submit(write_worker, i)
        for i in range(20):
            executor.submit(scan_worker, i)
        while True:
            time.sleep(60)
            print(f"Status: {write_count} writes, {scan_count} scans", flush=True)
CONFIGMAP_EOF

# Step 3: Create stress pod
echo "[3/4] Deploying stress test pod..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: dynamodb-stress-test
  namespace: $NAMESPACE
  labels:
    app: dynamodb-stress-test
    fault-injection: "true"
spec:
  serviceAccountName: carts
  containers:
  - name: stress
    image: python:3.11-slim
    command: ["bash", "-c", "pip install boto3 --quiet && python /scripts/stress.py"]
    env:
    - name: TABLE_NAME
      value: "$TABLE_NAME"
    - name: AWS_REGION
      value: "$REGION"
    volumeMounts:
    - name: stress-script
      mountPath: /scripts
    resources:
      requests:
        cpu: "500m"
        memory: "512Mi"
      limits:
        cpu: "2000m"
        memory: "1Gi"
  volumes:
  - name: stress-script
    configMap:
      name: dynamodb-stress-script
  restartPolicy: Never
EOF

# Step 4: Wait for pod
echo "[4/4] Waiting for stress pod to start..."
kubectl wait --for=condition=Ready pod/dynamodb-stress-test -n $NAMESPACE --timeout=120s 2>/dev/null || true
sleep 5

echo ""
echo "=== DynamoDB Stress Test Active ==="
echo ""
echo "Monitor stress pod:"
echo "  kubectl logs -f dynamodb-stress-test -n $NAMESPACE"
echo ""
echo "CloudWatch metrics to check:"
echo "  - ConsumedReadCapacityUnits"
echo "  - ConsumedWriteCapacityUnits"  
echo "  - ThrottledRequests"
echo ""
echo "Rollback:"
echo "  ./fault-injection/rollback-dynamodb-stress.sh"
