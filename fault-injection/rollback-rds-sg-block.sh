#!/bin/bash
# RDS Security Group Rollback

set -e

REGION="${AWS_REGION:-us-east-1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_FILE="$SCRIPT_DIR/rds-sg-ids.json"

echo "=== RDS Security Group Rollback ==="
echo ""

if [ ! -f "$BACKUP_FILE" ]; then
  echo "ERROR: No backup file found at $BACKUP_FILE"
  exit 1
fi

REGION=$(jq -r '.region' "$BACKUP_FILE")
REVOKED_RULES=$(jq -r '.revoked_rules' "$BACKUP_FILE")

echo "Region: $REGION"
echo ""

RULE_COUNT=$(echo "$REVOKED_RULES" | jq 'length')
if [ "$RULE_COUNT" -eq 0 ]; then
  echo "No rules to restore."
  exit 0
fi

echo "[1/3] Restoring $RULE_COUNT security group rules..."
echo ""

RESTORED=0
FAILED=0

for row in $(echo "$REVOKED_RULES" | jq -r '.[] | @base64'); do
  _jq() {
    echo ${row} | base64 --decode | jq -r ${1}
  }
  
  RDS_SG=$(_jq '.rds_sg')
  SOURCE_SG=$(_jq '.source_sg // empty')
  CIDR=$(_jq '.cidr // empty')
  PORT=$(_jq '.port')
  DB_ID=$(_jq '.db_id')
  
  echo "  Restoring: $DB_ID (SG: $RDS_SG, Port: $PORT)"
  
  if [ -n "$SOURCE_SG" ]; then
    if AWS_PAGER="" aws ec2 authorize-security-group-ingress \
      --group-id $RDS_SG \
      --protocol tcp \
      --port $PORT \
      --source-group $SOURCE_SG \
      --region $REGION 2>/dev/null; then
      echo "    ✓ Restored"
      RESTORED=$((RESTORED + 1))
    else
      echo "    ✗ Failed (may already exist)"
      FAILED=$((FAILED + 1))
    fi
  elif [ -n "$CIDR" ]; then
    if AWS_PAGER="" aws ec2 authorize-security-group-ingress \
      --group-id $RDS_SG \
      --protocol tcp \
      --port $PORT \
      --cidr $CIDR \
      --region $REGION 2>/dev/null; then
      echo "    ✓ Restored"
      RESTORED=$((RESTORED + 1))
    else
      echo "    ✗ Failed (may already exist)"
      FAILED=$((FAILED + 1))
    fi
  fi
done

echo ""
echo "[2/3] Restarting application pods..."

if kubectl get deployment -n catalog catalog &>/dev/null; then
  kubectl rollout restart deployment -n catalog catalog 2>/dev/null && echo "  ✓ Restarted catalog"
fi

if kubectl get deployment -n orders orders &>/dev/null; then
  kubectl rollout restart deployment -n orders orders 2>/dev/null && echo "  ✓ Restarted orders"
fi

echo ""
echo "Waiting 30 seconds for pods to restart..."
sleep 30

echo ""
echo "[3/3] Checking pod status..."
kubectl get pods -n catalog -l app.kubernetes.io/name=catalog --no-headers 2>/dev/null | sed 's/^/  /'
kubectl get pods -n orders -l app.kubernetes.io/name=orders --no-headers 2>/dev/null | sed 's/^/  /'

echo ""
echo "=== Rollback Complete ==="
echo ""
echo "Restored: $RESTORED rules, Failed: $FAILED rules"
