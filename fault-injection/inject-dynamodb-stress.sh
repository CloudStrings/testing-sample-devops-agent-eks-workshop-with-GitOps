#!/bin/bash
# DynamoDB Stress Test Injection (Read-Only)

set -e

NAMESPACE="carts"
REGION="${AWS_REGION:-us-east-1}"

echo "=== DynamoDB Stress Test Injection ==="
echo ""

echo "[1/4] Discovering DynamoDB table..."
TABLE_NAME=$(AWS_PAGER="" aws dynamodb list-tables --region $REGION --query "TableNames[?contains(@, 'carts')]" --output text 2>/dev/null | head -1)

if [ -z "$TABLE_NAME" ] || [ "$TABLE_NAME" == "None" ]; then
  echo "ERROR: No carts DynamoDB table found in region $REGION"
  exit 1
fi

echo "  Found table: $TABLE_NAME"
echo "  Region: $REGION"
echo ""

TABLE_STATUS=$(AWS_PAGER="" aws dynamodb describe-table --table-name $TABLE_NAME --region $REGION --query 'Table.TableStatus' --output text 2>/dev/null)
if [ "$TABLE_STATUS" != "ACTIVE" ]; then
  echo "ERROR: Table $TABLE_NAME not active (status: $TABLE_STATUS)"
  exit 1
fi

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
    import os
    from concurrent.futures import ThreadPoolExecutor

    TABLE_NAME = os.environ.get('TABLE_NAME', 'carts')
    REGION = os.environ.get('AWS_REGION', 'us-east-1')

    dynamodb = boto3.resource('dynamodb', region_name=REGION)
    table = dynamodb.Table(TABLE_NAME)

    scan_count = 0
    query_count = 0
    get_count = 0
    lock = threading.Lock()

    def scan_worker(worker_id):
        global scan_count
        while True:
            try:
                response = table.scan(Limit=1000)
                with lock:
                    scan_count += 1
                    if scan_count % 50 == 0:
                        print(f"Scans: {scan_count}", flush=True)
            except Exception as e:
                if 'Throttl' in str(e):
                    print(f"THROTTLED on scan!", flush=True)
            time.sleep(0.01)

    def query_worker(worker_id):
        global query_count
        while True:
            try:
                response = table.query(
                    IndexName='idx_global_customerId',
                    KeyConditionExpression='customerId = :cid',
                    ExpressionAttributeValues={':cid': f'stress-customer-{worker_id}'}
                )
                with lock:
                    query_count += 1
                    if query_count % 100 == 0:
                        print(f"Queries: {query_count}", flush=True)
            except Exception as e:
                if 'Throttl' in str(e):
                    print(f"THROTTLED on query!", flush=True)
            time.sleep(0.005)

    def get_worker(worker_id):
        global get_count
        while True:
            try:
                response = table.get_item(Key={'id': f'stress-nonexistent-{worker_id}-{get_count}'})
                with lock:
                    get_count += 1
                    if get_count % 500 == 0:
                        print(f"Gets: {get_count}", flush=True)
            except Exception as e:
                if 'Throttl' in str(e):
                    print(f"THROTTLED on get!", flush=True)
            time.sleep(0.001)

    print("=== DynamoDB Stress Test ===")
    print(f"Table: {TABLE_NAME}")
    print("Starting workers...")

    with ThreadPoolExecutor(max_workers=100) as executor:
        for i in range(30):
            executor.submit(scan_worker, i)
        for i in range(30):
            executor.submit(query_worker, i)
        for i in range(40):
            executor.submit(get_worker, i)
        while True:
            time.sleep(30)
            print(f"Status: {scan_count} scans, {query_count} queries, {get_count} gets", flush=True)
CONFIGMAP_EOF

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

echo "[4/4] Waiting for stress pod to start..."
kubectl wait --for=condition=Ready pod/dynamodb-stress-test -n $NAMESPACE --timeout=120s 2>/dev/null || true
sleep 5

echo ""
echo "=== Fault Injection Active ==="
echo ""
echo "Symptom: Slow performance and occasional failures."
echo ""
echo "Rollback: ./fault-injection/rollback-dynamodb-stress.sh"
