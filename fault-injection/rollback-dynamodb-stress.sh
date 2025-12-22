#!/bin/bash
# DynamoDB Stress Test Rollback
# Removes stress pod, ConfigMap, and recreates table (fastest cleanup)

set -e

NAMESPACE="carts"
TABLE_NAME="retail-store-carts"
REGION="${AWS_REGION:-us-east-1}"

echo "=== DynamoDB Stress Test Rollback ==="
echo ""

# Step 1: Delete stress pod
echo "[1/4] Deleting stress test pod..."
kubectl delete pod dynamodb-stress-test -n $NAMESPACE --ignore-not-found=true
echo "  ✓ Stress pod deleted"

# Step 2: Delete ConfigMap
echo "[2/4] Deleting stress test ConfigMap..."
kubectl delete configmap dynamodb-stress-script -n $NAMESPACE --ignore-not-found=true
echo "  ✓ ConfigMap deleted"

# Step 3: Get table schema before deleting
echo "[3/4] Backing up table schema and deleting table..."
TABLE_DESC=$(aws dynamodb describe-table --table-name $TABLE_NAME --region $REGION --output json 2>/dev/null)

if [ -z "$TABLE_DESC" ]; then
  echo "  Table not found, skipping cleanup"
else
  # Extract key schema and attribute definitions
  KEY_SCHEMA=$(echo "$TABLE_DESC" | jq '.Table.KeySchema')
  ATTR_DEFS=$(echo "$TABLE_DESC" | jq '.Table.AttributeDefinitions')
  
  # Delete the table
  echo "  Deleting table $TABLE_NAME..."
  aws dynamodb delete-table --table-name $TABLE_NAME --region $REGION --output json > /dev/null 2>&1
  
  # Wait for deletion
  echo "  Waiting for table deletion..."
  aws dynamodb wait table-not-exists --table-name $TABLE_NAME --region $REGION 2>/dev/null
  echo "  ✓ Table deleted"
  
  # Step 4: Recreate table with same schema (on-demand billing)
  echo "[4/4] Recreating table with original schema..."
  aws dynamodb create-table \
    --table-name $TABLE_NAME \
    --key-schema "$KEY_SCHEMA" \
    --attribute-definitions "$ATTR_DEFS" \
    --billing-mode PAY_PER_REQUEST \
    --region $REGION \
    --output json > /dev/null 2>&1
  
  # Wait for table to be active
  echo "  Waiting for table to become active..."
  aws dynamodb wait table-exists --table-name $TABLE_NAME --region $REGION 2>/dev/null
  echo "  ✓ Table recreated"
fi

# Restart carts deployment to reconnect
echo ""
echo "Restarting carts deployment..."
kubectl rollout restart deployment carts -n $NAMESPACE 2>/dev/null || true
kubectl rollout status deployment carts -n $NAMESPACE --timeout=60s 2>/dev/null || true

echo ""
echo "=== DynamoDB Stress Test Rollback Complete ==="
