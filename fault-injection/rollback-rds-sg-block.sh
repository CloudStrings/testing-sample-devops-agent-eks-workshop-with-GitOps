#!/bin/bash
# RDS Security Group Rollback
# Restores security group rules by adding the CURRENT EKS cluster SG to all RDS instances

set -e

REGION="${AWS_REGION:-us-east-1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_FILE="$SCRIPT_DIR/rds-sg-ids.json"

echo "=== RDS Security Group Rollback ==="
echo ""
echo "Region: $REGION"
echo ""

# Step 1: Always discover the CURRENT EKS cluster SG (don't rely on backup)
echo "[1/4] Discovering current EKS cluster security group..."
EKS_CLUSTER=$(AWS_PAGER="" aws eks list-clusters --region $REGION --query "clusters[0]" --output text 2>/dev/null)

if [ -z "$EKS_CLUSTER" ] || [ "$EKS_CLUSTER" == "None" ]; then
  echo "ERROR: No EKS cluster found in region $REGION"
  exit 1
fi

EKS_CLUSTER_SG=$(AWS_PAGER="" aws eks describe-cluster --region $REGION --name "$EKS_CLUSTER" \
  --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" --output text 2>/dev/null)

echo "  EKS Cluster: $EKS_CLUSTER"
echo "  Current EKS Cluster SG: $EKS_CLUSTER_SG"
echo ""

if [ -z "$EKS_CLUSTER_SG" ] || [ "$EKS_CLUSTER_SG" == "None" ]; then
  echo "ERROR: Could not determine EKS cluster security group"
  exit 1
fi

# Step 2: Discover all RDS instances
echo "[2/4] Discovering RDS instances..."
RDS_INFO=$(AWS_PAGER="" aws rds describe-db-instances --region $REGION \
  --query "DBInstances[*].[DBInstanceIdentifier,VpcSecurityGroups[0].VpcSecurityGroupId,Endpoint.Port,Engine]" \
  --output json 2>/dev/null)

if [ -z "$RDS_INFO" ] || [ "$RDS_INFO" == "[]" ]; then
  echo "ERROR: No RDS instances found in region $REGION"
  exit 1
fi

echo "  Found RDS instances:"
echo "$RDS_INFO" | jq -r '.[] | "    - \(.[0]) (\(.[3]), Port: \(.[2]), SG: \(.[1]))"'
echo ""

# Step 3: Add EKS cluster SG to all RDS security groups
echo "[3/4] Adding EKS cluster SG to RDS security groups..."
echo ""

RESTORED=0
FAILED=0
RDS_COUNT=$(echo "$RDS_INFO" | jq 'length')

for i in $(seq 0 $((RDS_COUNT - 1))); do
  DB_ID=$(echo "$RDS_INFO" | jq -r ".[$i][0]")
  RDS_SG=$(echo "$RDS_INFO" | jq -r ".[$i][1]")
  DB_PORT=$(echo "$RDS_INFO" | jq -r ".[$i][2]")
  DB_ENGINE=$(echo "$RDS_INFO" | jq -r ".[$i][3]")
  
  echo "  Restoring: $DB_ID ($DB_ENGINE, Port: $DB_PORT)"
  
  if AWS_PAGER="" aws ec2 authorize-security-group-ingress \
    --group-id $RDS_SG \
    --protocol tcp \
    --port $DB_PORT \
    --source-group $EKS_CLUSTER_SG \
    --region $REGION 2>/dev/null; then
    echo "    ✓ Added EKS SG $EKS_CLUSTER_SG to $RDS_SG on port $DB_PORT"
    RESTORED=$((RESTORED + 1))
  else
    echo "    ✗ Failed to add (rule may already exist)"
    FAILED=$((FAILED + 1))
  fi
done

echo ""
echo "[4/4] Verifying restoration..."
echo ""

for i in $(seq 0 $((RDS_COUNT - 1))); do
  RDS_SG=$(echo "$RDS_INFO" | jq -r ".[$i][1]")
  DB_ID=$(echo "$RDS_INFO" | jq -r ".[$i][0]")
  
  echo "Security Group: $RDS_SG ($DB_ID)"
  AWS_PAGER="" aws ec2 describe-security-groups --region $REGION \
    --group-ids $RDS_SG \
    --query "SecurityGroups[0].IpPermissions[*].[IpRanges[0].CidrIp,FromPort,UserIdGroupPairs[0].GroupId]" \
    --output table 2>/dev/null || echo "  Could not describe security group"
  
  # Check if EKS SG is in the rules
  HAS_EKS_SG=$(AWS_PAGER="" aws ec2 describe-security-groups --region $REGION \
    --group-ids $RDS_SG \
    --query "SecurityGroups[0].IpPermissions[?UserIdGroupPairs[?GroupId=='$EKS_CLUSTER_SG']]" \
    --output text 2>/dev/null)
  
  if [ -n "$HAS_EKS_SG" ]; then
    echo "  ✓ EKS cluster SG ($EKS_CLUSTER_SG) is present"
  else
    echo "  ✗ WARNING: EKS cluster SG ($EKS_CLUSTER_SG) NOT found in rules!"
  fi
  echo ""
done

echo "=== Security Group Rollback Complete ==="
echo "Restored: $RESTORED rules"
echo "Failed/Already existed: $FAILED rules"
echo ""

# Restart pods
echo "[5/5] Restarting application pods..."

if kubectl get deployment -n catalog catalog &>/dev/null; then
  kubectl rollout restart deployment -n catalog catalog 2>/dev/null && echo "  ✓ Restarted catalog deployment"
fi

if kubectl get deployment -n orders orders &>/dev/null; then
  kubectl rollout restart deployment -n orders orders 2>/dev/null && echo "  ✓ Restarted orders deployment"
fi

echo ""
echo "Waiting 30 seconds for pods to restart..."
sleep 30

echo ""
echo "Checking pod status..."
echo ""
echo "Catalog pods:"
kubectl get pods -n catalog -l app.kubernetes.io/name=catalog --no-headers 2>/dev/null | sed 's/^/  /' || echo "  No catalog pods found"

echo ""
echo "Orders pods:"
kubectl get pods -n orders -l app.kubernetes.io/name=orders --no-headers 2>/dev/null | sed 's/^/  /' || echo "  No orders pods found"

echo ""
echo "=== Rollback Complete ==="
echo ""
echo "Verify the application is working by checking the UI or running:"
echo "  kubectl logs -n catalog -l app.kubernetes.io/name=catalog --tail=20"
echo "  kubectl logs -n orders -l app.kubernetes.io/name=orders --tail=20"
