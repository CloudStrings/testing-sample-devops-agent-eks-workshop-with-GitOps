#!/bin/bash

echo "=== Cleaning up ALL retail-store AWS resources ==="

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="us-east-1"
echo "Account ID: $ACCOUNT_ID"
echo "Region: $REGION"

# Delete EKS cluster first (if exists)
echo ""
echo "=== Deleting EKS cluster ==="
aws eks delete-cluster --name retail-store --region $REGION 2>/dev/null && echo "  EKS cluster deletion initiated" || echo "  No EKS cluster found"

# Wait for cluster deletion
echo "  Waiting for EKS cluster deletion..."
aws eks wait cluster-deleted --name retail-store --region $REGION 2>/dev/null || true

# Delete EKS node groups
echo ""
echo "=== Deleting EKS node groups ==="
for ng in $(aws eks list-nodegroups --cluster-name retail-store --region $REGION --query 'nodegroups[*]' --output text 2>/dev/null); do
  echo "  Deleting node group: $ng"
  aws eks delete-nodegroup --cluster-name retail-store --nodegroup-name $ng --region $REGION 2>/dev/null || true
done

# Delete KMS alias and key
echo ""
echo "=== Deleting KMS resources ==="
aws kms delete-alias --alias-name alias/eks/retail-store --region $REGION 2>/dev/null && echo "  Deleted KMS alias" || echo "  KMS alias not found"

# Schedule KMS key for deletion (find by alias first)
KEY_ID=$(aws kms list-aliases --region $REGION --query "Aliases[?AliasName=='alias/eks/retail-store'].TargetKeyId" --output text 2>/dev/null)
if [ -n "$KEY_ID" ] && [ "$KEY_ID" != "None" ]; then
  echo "  Scheduling KMS key $KEY_ID for deletion"
  aws kms schedule-key-deletion --key-id $KEY_ID --pending-window-in-days 7 --region $REGION 2>/dev/null || true
fi

# Delete CloudWatch Log Groups
echo ""
echo "=== Deleting CloudWatch Log Groups ==="
for lg in $(aws logs describe-log-groups --log-group-name-prefix /aws/eks/retail-store --region $REGION --query 'logGroups[*].logGroupName' --output text 2>/dev/null); do
  echo "  Deleting log group: $lg"
  aws logs delete-log-group --log-group-name "$lg" --region $REGION 2>/dev/null || true
done

for lg in $(aws logs describe-log-groups --log-group-name-prefix /aws/containerinsights/retail-store --region $REGION --query 'logGroups[*].logGroupName' --output text 2>/dev/null); do
  echo "  Deleting log group: $lg"
  aws logs delete-log-group --log-group-name "$lg" --region $REGION 2>/dev/null || true
done

# Delete DynamoDB table
echo ""
echo "=== Deleting DynamoDB table ==="
aws dynamodb delete-table --table-name retail-store-carts --region $REGION 2>/dev/null && echo "  Deleted DynamoDB table" || echo "  DynamoDB table not found"

# Delete ElastiCache
echo ""
echo "=== Deleting ElastiCache resources ==="
aws elasticache delete-cache-cluster --cache-cluster-id retail-store-checkout --region $REGION 2>/dev/null && echo "  Deleted ElastiCache cluster" || echo "  ElastiCache cluster not found"
aws elasticache delete-cache-parameter-group --cache-parameter-group-name retail-store-checkout --region $REGION 2>/dev/null && echo "  Deleted ElastiCache parameter group" || echo "  Parameter group not found"
aws elasticache delete-cache-subnet-group --cache-subnet-group-name retail-store-checkout --region $REGION 2>/dev/null && echo "  Deleted ElastiCache subnet group" || echo "  Subnet group not found"

# Delete RDS clusters
echo ""
echo "=== Deleting RDS resources ==="
for cluster in retail-store-catalog retail-store-orders; do
  echo "  Deleting RDS cluster: $cluster"
  aws rds delete-db-cluster --db-cluster-identifier $cluster --skip-final-snapshot --region $REGION 2>/dev/null || echo "    Not found"
done

# Delete RDS subnet groups
for sg in retail-store-catalog retail-store-orders; do
  aws rds delete-db-subnet-group --db-subnet-group-name $sg --region $REGION 2>/dev/null || true
done

# Delete Amazon MQ broker
echo ""
echo "=== Deleting Amazon MQ broker ==="
BROKER_ID=$(aws mq list-brokers --region $REGION --query "BrokerSummaries[?BrokerName=='retail-store-orders'].BrokerId" --output text 2>/dev/null)
if [ -n "$BROKER_ID" ] && [ "$BROKER_ID" != "None" ]; then
  echo "  Deleting broker: $BROKER_ID"
  aws mq delete-broker --broker-id $BROKER_ID --region $REGION 2>/dev/null || true
fi

# Delete Prometheus workspace
echo ""
echo "=== Deleting Prometheus workspace ==="
PROM_WS=$(aws amp list-workspaces --region $REGION --query "workspaces[?alias=='retail-store'].workspaceId" --output text 2>/dev/null)
if [ -n "$PROM_WS" ] && [ "$PROM_WS" != "None" ]; then
  echo "  Deleting Prometheus workspace: $PROM_WS"
  aws amp delete-workspace --workspace-id $PROM_WS --region $REGION 2>/dev/null || true
fi

# Delete Grafana workspace
echo ""
echo "=== Deleting Grafana workspace ==="
GRAFANA_WS=$(aws grafana list-workspaces --region $REGION --query "workspaces[?name=='retail-store-grafana'].id" --output text 2>/dev/null)
if [ -n "$GRAFANA_WS" ] && [ "$GRAFANA_WS" != "None" ]; then
  echo "  Deleting Grafana workspace: $GRAFANA_WS"
  aws grafana delete-workspace --workspace-id $GRAFANA_WS --region $REGION 2>/dev/null || true
fi

# Delete IAM policies
echo ""
echo "=== Deleting IAM policies ==="
for policy_name in retail-store-carts-dynamo retail-store-catalog-rds retail-store-orders-rds retail-store-checkout-redis retail-store-orders-mq; do
  policy_arn="arn:aws:iam::${ACCOUNT_ID}:policy/${policy_name}"
  echo "  Deleting policy: $policy_name"
  aws iam delete-policy --policy-arn $policy_arn 2>/dev/null || true
done

# Delete IAM roles
echo ""
echo "=== Deleting IAM roles ==="
ROLES=(
  "retail-store-eks-auto-node"
  "retail-store-eks-auto-cluster"
  "retail-store-prometheus-scraper"
  "retail-store-grafana"
  "retail-store-carts"
  "retail-store-catalog"
  "retail-store-orders"
  "retail-store-checkout"
  "retail-store-ui"
)

for role in "${ROLES[@]}"; do
  echo "  Cleaning up role: $role"
  
  # Detach managed policies
  for policy in $(aws iam list-attached-role-policies --role-name $role --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null); do
    [ -n "$policy" ] && aws iam detach-role-policy --role-name $role --policy-arn $policy 2>/dev/null || true
  done
  
  # Delete inline policies
  for policy in $(aws iam list-role-policies --role-name $role --query 'PolicyNames[*]' --output text 2>/dev/null); do
    [ -n "$policy" ] && aws iam delete-role-policy --role-name $role --policy-name $policy 2>/dev/null || true
  done
  
  # Remove from instance profiles
  for profile in $(aws iam list-instance-profiles-for-role --role-name $role --query 'InstanceProfiles[*].InstanceProfileName' --output text 2>/dev/null); do
    [ -n "$profile" ] && aws iam remove-role-from-instance-profile --instance-profile-name $profile --role-name $role 2>/dev/null || true
  done
  
  # Delete the role
  aws iam delete-role --role-name $role 2>/dev/null || true
done

# Delete VPC (this will fail if resources still exist, which is expected)
echo ""
echo "=== Attempting VPC cleanup ==="
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=retail-store" --region $REGION --query 'Vpcs[0].VpcId' --output text 2>/dev/null)
if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
  echo "  Found VPC: $VPC_ID"
  
  # Delete NAT Gateways
  for nat in $(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" --region $REGION --query 'NatGateways[*].NatGatewayId' --output text 2>/dev/null); do
    echo "    Deleting NAT Gateway: $nat"
    aws ec2 delete-nat-gateway --nat-gateway-id $nat --region $REGION 2>/dev/null || true
  done
  
  # Delete Internet Gateway
  for igw in $(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --region $REGION --query 'InternetGateways[*].InternetGatewayId' --output text 2>/dev/null); do
    echo "    Detaching and deleting Internet Gateway: $igw"
    aws ec2 detach-internet-gateway --internet-gateway-id $igw --vpc-id $VPC_ID --region $REGION 2>/dev/null || true
    aws ec2 delete-internet-gateway --internet-gateway-id $igw --region $REGION 2>/dev/null || true
  done
  
  # Delete subnets
  for subnet in $(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --region $REGION --query 'Subnets[*].SubnetId' --output text 2>/dev/null); do
    echo "    Deleting subnet: $subnet"
    aws ec2 delete-subnet --subnet-id $subnet --region $REGION 2>/dev/null || true
  done
  
  # Delete security groups (except default)
  for sg in $(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --region $REGION --query "SecurityGroups[?GroupName!='default'].GroupId" --output text 2>/dev/null); do
    echo "    Deleting security group: $sg"
    aws ec2 delete-security-group --group-id $sg --region $REGION 2>/dev/null || true
  done
  
  # Delete route tables (except main)
  for rt in $(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --region $REGION --query "RouteTables[?Associations[0].Main!=\`true\`].RouteTableId" --output text 2>/dev/null); do
    echo "    Deleting route table: $rt"
    aws ec2 delete-route-table --route-table-id $rt --region $REGION 2>/dev/null || true
  done
  
  # Delete VPC
  echo "    Deleting VPC: $VPC_ID"
  aws ec2 delete-vpc --vpc-id $VPC_ID --region $REGION 2>/dev/null || echo "    VPC deletion may require manual cleanup"
fi

# Delete Elastic IPs
echo ""
echo "=== Releasing Elastic IPs ==="
for eip in $(aws ec2 describe-addresses --region $REGION --query "Addresses[?Tags[?Key=='Name' && contains(Value, 'retail-store')]].AllocationId" --output text 2>/dev/null); do
  echo "  Releasing EIP: $eip"
  aws ec2 release-address --allocation-id $eip --region $REGION 2>/dev/null || true
done

echo ""
echo "=== Cleanup complete! ==="
echo ""
echo "Note: Some resources may take time to delete. Wait a few minutes before running terraform apply."
echo "If VPC deletion failed, you may need to manually delete remaining ENIs in the AWS console."
