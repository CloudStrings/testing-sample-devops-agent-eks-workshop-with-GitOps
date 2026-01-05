#!/bin/bash
# RDS Security Group Misconfiguration Injection

set -e

REGION="${AWS_REGION:-us-east-1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_FILE="$SCRIPT_DIR/rds-sg-rules.tmp"

rm -f "$TMP_FILE"

echo "=== RDS Security Group Misconfiguration Injection ==="
echo ""
echo "Region: $REGION"
echo ""

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

echo "[2/4] Discovering RDS instances and security groups..."
RDS_INFO=$(AWS_PAGER="" aws rds describe-db-instances --region $REGION \
  --query "DBInstances[*].[DBInstanceIdentifier,VpcSecurityGroups[0].VpcSecurityGroupId,Endpoint.Port]" \
  --output json 2>/dev/null)

if [ -z "$RDS_INFO" ] || [ "$RDS_INFO" == "[]" ]; then
  echo "ERROR: No RDS instances found in region $REGION"
  exit 1
fi

echo "  Found RDS instances:"
echo "$RDS_INFO" | jq -r '.[] | "    - \(.[0]) (SG: \(.[1]), Port: \(.[2]))"'
echo ""

echo "[3/4] Discovering and revoking security group rules..."

RDS_COUNT=$(echo "$RDS_INFO" | jq 'length')
for i in $(seq 0 $((RDS_COUNT - 1))); do
  DB_ID=$(echo "$RDS_INFO" | jq -r ".[$i][0]")
  RDS_SG=$(echo "$RDS_INFO" | jq -r ".[$i][1]")
  DB_PORT=$(echo "$RDS_INFO" | jq -r ".[$i][2]")
  
  echo "  Processing: $DB_ID (SG: $RDS_SG, Port: $DB_PORT)"
  
  SG_RULES=$(AWS_PAGER="" aws ec2 describe-security-groups --region $REGION \
    --group-ids $RDS_SG \
    --query "SecurityGroups[0].IpPermissions" --output json 2>/dev/null)
  
  RULE_COUNT=$(echo "$SG_RULES" | jq 'length')
  for j in $(seq 0 $((RULE_COUNT - 1))); do
    rule=$(echo "$SG_RULES" | jq -c ".[$j]")
    FROM_PORT=$(echo "$rule" | jq -r '.FromPort // empty')
    TO_PORT=$(echo "$rule" | jq -r '.ToPort // empty')
    
    if [ "$FROM_PORT" == "$DB_PORT" ] || [ "$TO_PORT" == "$DB_PORT" ]; then
      SG_PAIR_COUNT=$(echo "$rule" | jq '.UserIdGroupPairs | length')
      for k in $(seq 0 $((SG_PAIR_COUNT - 1))); do
        SOURCE_SG=$(echo "$rule" | jq -r ".UserIdGroupPairs[$k].GroupId")
        
        if [ -n "$SOURCE_SG" ] && [ "$SOURCE_SG" != "null" ]; then
          echo "    Found rule: port $DB_PORT from SG $SOURCE_SG"
          
          if AWS_PAGER="" aws ec2 revoke-security-group-ingress \
            --group-id $RDS_SG \
            --protocol tcp \
            --port $DB_PORT \
            --source-group $SOURCE_SG \
            --region $REGION 2>/dev/null; then
            echo "    ✓ Revoked port $DB_PORT from $SOURCE_SG"
            echo "{\"rds_sg\": \"$RDS_SG\", \"source_sg\": \"$SOURCE_SG\", \"port\": $DB_PORT, \"db_id\": \"$DB_ID\"}" >> "$TMP_FILE"
          else
            echo "    - Failed to revoke (may already be removed)"
          fi
        fi
      done
      
      CIDR_COUNT=$(echo "$rule" | jq '.IpRanges | length')
      for k in $(seq 0 $((CIDR_COUNT - 1))); do
        CIDR=$(echo "$rule" | jq -r ".IpRanges[$k].CidrIp")
        
        if [ -n "$CIDR" ] && [ "$CIDR" != "null" ]; then
          echo "    Found rule: port $DB_PORT from CIDR $CIDR"
          
          if AWS_PAGER="" aws ec2 revoke-security-group-ingress \
            --group-id $RDS_SG \
            --protocol tcp \
            --port $DB_PORT \
            --cidr $CIDR \
            --region $REGION 2>/dev/null; then
            echo "    ✓ Revoked port $DB_PORT from $CIDR"
            echo "{\"rds_sg\": \"$RDS_SG\", \"cidr\": \"$CIDR\", \"port\": $DB_PORT, \"db_id\": \"$DB_ID\"}" >> "$TMP_FILE"
          else
            echo "    - Failed to revoke (may already be removed)"
          fi
        fi
      done
    fi
  done
done

if [ -f "$TMP_FILE" ]; then
  REVOKED_RULES=$(cat "$TMP_FILE" | jq -s '.')
  rm -f "$TMP_FILE"
else
  REVOKED_RULES="[]"
fi

echo "{\"region\": \"$REGION\", \"eks_cluster\": \"$EKS_CLUSTER\", \"revoked_rules\": $REVOKED_RULES}" > "$SCRIPT_DIR/rds-sg-ids.json"
echo ""
echo "  Backup saved to: $SCRIPT_DIR/rds-sg-ids.json"

REVOKED_COUNT=$(echo "$REVOKED_RULES" | jq 'length')
if [ "$REVOKED_COUNT" -eq 0 ]; then
  echo ""
  echo "WARNING: No rules were revoked."
  exit 0
fi

echo ""
echo "Revoked $REVOKED_COUNT security group rules"
echo ""

echo "[4/4] Restarting application pods..."

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
echo "Symptom: Catalog pod is crashing."
echo ""
echo "Rollback: ./fault-injection/rollback-rds-sg-block.sh"
