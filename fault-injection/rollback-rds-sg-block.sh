#!/bin/bash
# RDS Security Group Rollback
# Restores security group rules that were revoked by inject-rds-sg-block.sh

set -e

REGION="${AWS_REGION:-us-east-1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_FILE="$SCRIPT_DIR/rds-sg-ids.json"

echo "=== RDS Security Group Rollback ==="
echo ""

# Check if backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
  echo "ERROR: No backup file found at $BACKUP_FILE"
  echo ""
  echo "If you need to manually restore, run these commands to add EKS cluster SG to RDS:"
  echo ""
  echo "  # Get EKS cluster security group"
  echo "  EKS_SG=\$(aws eks describe-cluster --name \$CLUSTER_NAME --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)"
  echo ""
  echo "  # Get RDS security groups and ports"
  echo "  aws rds describe-db-instances --query 'DBInstances[*].[DBInstanceIdentifier,Engine,Endpoint.Port,VpcSecurityGroups[0].VpcSecurityGroupId]' --output table"
  echo ""
  echo "  # Add rules for each RDS instance"
  echo "  aws ec2 authorize-security-group-ingress --group-id <RDS_SG> --protocol tcp --port <PORT> --source-group \$EKS_SG"
  exit 1
fi

# Read backup file
REGION=$(jq -r '.region' "$BACKUP_FILE")
EKS_CLUSTER=$(jq -r '.eks_cluster // empty' "$BACKUP_FILE")
EKS_CLUSTER_SG=$(jq -r '.eks_cluster_sg // empty' "$BACKUP_FILE")
REVOKED_RULES=$(jq -c '.revoked_rules // []' "$BACKUP_FILE")

echo "Region: $REGION"
echo "EKS Cluster: $EKS_CLUSTER"
echo "EKS Cluster SG: $EKS_CLUSTER_SG"
echo ""

RULE_COUNT=$(echo "$REVOKED_RULES" | jq 'length')
if [ "$RULE_COUNT" -eq 0 ]; then
  echo "No rules to restore from backup file."
  echo ""
  echo "Attempting to auto-discover and restore rules..."
  
  # Auto-restore: Add EKS cluster SG to all RDS security groups
  if [ -n "$EKS_CLUSTER_SG" ] && [ "$EKS_CLUSTER_SG" != "null" ]; then
    RDS_INFO=$(AWS_PAGER="" aws rds describe-db-instances --region $REGION \
      --query "DBInstances[*].[DBInstanceIdentifier,VpcSecurityGroups[0].VpcSecurityGroupId,Endpoint.Port,Engine]" \
      --output json 2>/dev/null)
    
    if [ -n "$RDS_INFO" ] && [ "$RDS_INFO" != "[]" ]; then
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
        else
          echo "    - Rule may already exist or failed to add"
        fi
      done
    fi
  fi
else
  echo "[1/3] Restoring $RULE_COUNT security group rules..."
  echo ""

  RESTORED=0
  FAILED=0

  # Process each revoked rule
  for row in $(echo "$REVOKED_RULES" | jq -r '.[] | @base64'); do
    _jq() {
      echo ${row} | base64 --decode | jq -r ${1}
    }
    
    RDS_SG=$(_jq '.rds_sg')
    SOURCE_SG=$(_jq '.source_sg // empty')
    CIDR=$(_jq '.cidr // empty')
    PORT=$(_jq '.port')
    DB_ID=$(_jq '.db_id')
    DB_ENGINE=$(_jq '.engine // "unknown"')
    
    echo "  Restoring: $DB_ID ($DB_ENGINE, SG: $RDS_SG, Port: $PORT)"
    
    if [ -n "$SOURCE_SG" ] && [ "$SOURCE_SG" != "null" ]; then
      if AWS_PAGER="" aws ec2 authorize-security-group-ingress \
        --group-id $RDS_SG \
        --protocol tcp \
        --port $PORT \
        --source-group $SOURCE_SG \
        --region $REGION 2>/dev/null; then
        echo "    ✓ Restored: Allow port $PORT from SG $SOURCE_SG"
        RESTORED=$((RESTORED + 1))
      else
        echo "    - Failed (rule may already exist)"
        FAILED=$((FAILED + 1))
      fi
    elif [ -n "$CIDR" ] && [ "$CIDR" != "null" ]; then
      if AWS_PAGER="" aws ec2 authorize-security-group-ingress \
        --group-id $RDS_SG \
        --protocol tcp \
        --port $PORT \
        --cidr $CIDR \
        --region $REGION 2>/dev/null; then
        echo "    ✓ Restored: Allow port $PORT from CIDR $CIDR"
        RESTORED=$((RESTORED + 1))
      else
        echo "    - Failed (rule may already exist)"
        FAILED=$((FAILED + 1))
      fi
    fi
  done

  echo ""
  echo "Restored: $RESTORED rules, Failed/Skipped: $FAILED rules"
fi

echo ""
echo "[2/3] Restarting application pods..."

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
echo "[3/3] Checking pod status..."
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
