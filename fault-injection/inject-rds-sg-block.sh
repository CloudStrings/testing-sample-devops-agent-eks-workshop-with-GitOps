#!/bin/bash
# RDS Security Group Misconfiguration Injection
# Removes ingress rules allowing EKS to connect to ALL RDS instances
# Blocks both MySQL (3306) and PostgreSQL (5432) ports

set -e

REGION="${AWS_REGION:-us-east-1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_FILE="$SCRIPT_DIR/rds-sg-ids.json"

# Initialize empty backup
echo '{"region": "'$REGION'", "eks_cluster": "", "revoked_rules": []}' > "$BACKUP_FILE"

echo "=== RDS Security Group Misconfiguration Injection ==="
echo ""
echo "Region: $REGION"
echo ""

# Step 1: Discover EKS cluster
echo "[1/4] Discovering EKS cluster security groups..."
EKS_CLUSTER=$(AWS_PAGER="" aws eks list-clusters --region $REGION --query "clusters[0]" --output text 2>/dev/null)

if [ -z "$EKS_CLUSTER" ] || [ "$EKS_CLUSTER" == "None" ]; then
  echo "ERROR: No EKS cluster found in region $REGION"
  exit 1
fi

EKS_CLUSTER_SG=$(AWS_PAGER="" aws eks describe-cluster --region $REGION --name "$EKS_CLUSTER" \
  --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" --output text 2>/dev/null)

echo "  EKS Cluster: $EKS_CLUSTER"
echo "  Cluster Security Group: $EKS_CLUSTER_SG"
echo ""

# Step 2: Discover all RDS instances
echo "[2/4] Discovering RDS instances and security groups..."
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

# Step 3: Revoke security group rules and save to backup
echo "[3/4] Discovering and revoking security group rules..."

REVOKED_RULES="[]"
RDS_COUNT=$(echo "$RDS_INFO" | jq 'length')

for i in $(seq 0 $((RDS_COUNT - 1))); do
  DB_ID=$(echo "$RDS_INFO" | jq -r ".[$i][0]")
  RDS_SG=$(echo "$RDS_INFO" | jq -r ".[$i][1]")
  DB_PORT=$(echo "$RDS_INFO" | jq -r ".[$i][2]")
  DB_ENGINE=$(echo "$RDS_INFO" | jq -r ".[$i][3]")
  
  echo "  Processing: $DB_ID ($DB_ENGINE, SG: $RDS_SG, Port: $DB_PORT)"
  
  # Get all ingress rules for this security group
  SG_RULES=$(AWS_PAGER="" aws ec2 describe-security-groups --region $REGION \
    --group-ids $RDS_SG \
    --query "SecurityGroups[0].IpPermissions" --output json 2>/dev/null)
  
  if [ -z "$SG_RULES" ] || [ "$SG_RULES" == "null" ]; then
    echo "    No rules found for security group"
    continue
  fi
  
  RULE_COUNT=$(echo "$SG_RULES" | jq 'length')
  
  for j in $(seq 0 $((RULE_COUNT - 1))); do
    rule=$(echo "$SG_RULES" | jq -c ".[$j]")
    FROM_PORT=$(echo "$rule" | jq -r '.FromPort // empty')
    TO_PORT=$(echo "$rule" | jq -r '.ToPort // empty')
    
    # Check if this rule covers the DB port
    if [ "$FROM_PORT" == "$DB_PORT" ] || [ "$TO_PORT" == "$DB_PORT" ]; then
      
      # Process security group references
      SG_PAIRS=$(echo "$rule" | jq -c '.UserIdGroupPairs // []')
      SG_PAIR_COUNT=$(echo "$SG_PAIRS" | jq 'length')
      
      for k in $(seq 0 $((SG_PAIR_COUNT - 1))); do
        SOURCE_SG=$(echo "$SG_PAIRS" | jq -r ".[$k].GroupId")
        
        if [ -n "$SOURCE_SG" ] && [ "$SOURCE_SG" != "null" ]; then
          echo "    Found rule: port $DB_PORT from SG $SOURCE_SG"
          
          if AWS_PAGER="" aws ec2 revoke-security-group-ingress \
            --group-id $RDS_SG \
            --protocol tcp \
            --port $DB_PORT \
            --source-group $SOURCE_SG \
            --region $REGION 2>/dev/null; then
            echo "    ✓ Revoked port $DB_PORT from $SOURCE_SG"
            # Add to revoked rules array
            NEW_RULE="{\"rds_sg\": \"$RDS_SG\", \"source_sg\": \"$SOURCE_SG\", \"port\": $DB_PORT, \"db_id\": \"$DB_ID\", \"engine\": \"$DB_ENGINE\"}"
            REVOKED_RULES=$(echo "$REVOKED_RULES" | jq ". + [$NEW_RULE]")
          else
            echo "    - Failed to revoke (may already be removed)"
          fi
        fi
      done
      
      # Process CIDR blocks
      CIDR_RANGES=$(echo "$rule" | jq -c '.IpRanges // []')
      CIDR_COUNT=$(echo "$CIDR_RANGES" | jq 'length')
      
      for k in $(seq 0 $((CIDR_COUNT - 1))); do
        CIDR=$(echo "$CIDR_RANGES" | jq -r ".[$k].CidrIp")
        
        if [ -n "$CIDR" ] && [ "$CIDR" != "null" ]; then
          echo "    Found rule: port $DB_PORT from CIDR $CIDR"
          
          if AWS_PAGER="" aws ec2 revoke-security-group-ingress \
            --group-id $RDS_SG \
            --protocol tcp \
            --port $DB_PORT \
            --cidr $CIDR \
            --region $REGION 2>/dev/null; then
            echo "    ✓ Revoked port $DB_PORT from $CIDR"
            # Add to revoked rules array
            NEW_RULE="{\"rds_sg\": \"$RDS_SG\", \"cidr\": \"$CIDR\", \"port\": $DB_PORT, \"db_id\": \"$DB_ID\", \"engine\": \"$DB_ENGINE\"}"
            REVOKED_RULES=$(echo "$REVOKED_RULES" | jq ". + [$NEW_RULE]")
          else
            echo "    - Failed to revoke (may already be removed)"
          fi
        fi
      done
    fi
  done
done

# Save backup file
echo "{\"region\": \"$REGION\", \"eks_cluster\": \"$EKS_CLUSTER\", \"eks_cluster_sg\": \"$EKS_CLUSTER_SG\", \"revoked_rules\": $REVOKED_RULES}" > "$BACKUP_FILE"

echo ""
echo "  Backup saved to: $BACKUP_FILE"

REVOKED_COUNT=$(echo "$REVOKED_RULES" | jq 'length')
if [ "$REVOKED_COUNT" -eq 0 ]; then
  echo ""
  echo "WARNING: No rules were revoked. Security groups may not have matching rules."
  echo "Check the RDS security groups manually in the AWS Console."
  exit 0
fi

echo ""
echo "=== Revoked $REVOKED_COUNT security group rules ==="
echo ""

# Step 4: Restart pods
echo "[4/4] Restarting application pods to trigger connection errors..."

if kubectl get deployment -n catalog catalog &>/dev/null; then
  kubectl rollout restart deployment -n catalog catalog 2>/dev/null && echo "  ✓ Restarted catalog deployment"
fi

if kubectl get deployment -n orders orders &>/dev/null; then
  kubectl rollout restart deployment -n orders orders 2>/dev/null && echo "  ✓ Restarted orders deployment"
fi

echo ""
echo "Waiting 30 seconds for pods to restart and fail..."
sleep 30

echo ""
echo "=== Fault Injection Active ==="
echo ""
echo "Symptoms:"
echo "  - Catalog service: Cannot connect to MySQL (port 3306)"
echo "  - Orders service: Cannot connect to PostgreSQL (port 5432)"
echo ""
echo "Rollback command:"
echo "  ./fault-injection/rollback-rds-sg-block.sh"
