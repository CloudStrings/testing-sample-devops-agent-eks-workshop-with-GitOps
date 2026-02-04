# Troubleshooting Guide - Common Deployment Issues

## Issue 1: EKS Add-on "metrics-server" Error

### Symptoms
```
Error: creating EKS Add-On (retail-store:metrics-server): operation error EKS: CreateAddon, 
https response error StatusCode: 400, RequestID: xxx, InvalidParameterException: 
Addon metrics-server is not available for cluster version x.xx
```

### Root Cause
The `metrics-server` is not an official EKS add-on. It needs to be installed via Helm instead.

### Solution 1: Remove metrics-server from EKS add-ons

If the Terraform code includes `metrics-server` in the `cluster_addons` block, you need to either:

**Option A: Comment it out in the Terraform code**

Find the EKS module configuration and remove/comment out metrics-server:

```hcl
# In your main.tf or eks.tf file
module "eks" {
  source = "terraform-aws-modules/eks/aws"
  
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
    }
    # REMOVE OR COMMENT OUT THIS:
    # metrics-server = {
    #   most_recent = true
    # }
  }
}
```

**Option B: Install metrics-server via Helm instead**

After the EKS cluster is created, install metrics-server manually:

```bash
# Install metrics-server via Helm
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update

helm install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  --set args[0]="--kubelet-preferred-address-types=InternalIP"

# Verify installation
kubectl get deployment metrics-server -n kube-system
```

**Option C: Skip metrics-server entirely**

If you don't need metrics-server for this workshop, you can skip it. The observability stack (Prometheus, CloudWatch) provides sufficient metrics.

---

## Issue 2: 403 Error for DescribeReplicationGroups (ElastiCache)

### Symptoms
```
Error: reading ElastiCache Replication Group (xxx): operation error ElastiCache: 
DescribeReplicationGroups, https response error StatusCode: 403, RequestID: xxx, 
api error AccessDenied: User: arn:aws:iam::xxx:user/xxx is not authorized to 
perform: elasticache:DescribeReplicationGroups
```

### Root Cause
Your IAM user/role lacks the necessary ElastiCache permissions.

### Solution 1: Add ElastiCache Permissions to Your IAM User

**Option A: Attach AWS Managed Policy (Recommended for Workshop)**

```bash
# Get your IAM username
aws sts get-caller-identity --query 'Arn' --output text

# Attach ElastiCache full access policy
aws iam attach-user-policy \
  --user-name YOUR_USERNAME \
  --policy-arn arn:aws:iam::aws:policy/AmazonElastiCacheFullAccess
```

**Option B: Create Custom Policy with Minimum Permissions**

Create a file `elasticache-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "elasticache:CreateReplicationGroup",
        "elasticache:CreateCacheSubnetGroup",
        "elasticache:DescribeReplicationGroups",
        "elasticache:DescribeCacheClusters",
        "elasticache:DescribeCacheSubnetGroups",
        "elasticache:ModifyReplicationGroup",
        "elasticache:DeleteReplicationGroup",
        "elasticache:DeleteCacheSubnetGroup",
        "elasticache:AddTagsToResource",
        "elasticache:ListTagsForResource"
      ],
      "Resource": "*"
    }
  ]
}
```

Apply the policy:

```bash
# Create the policy
aws iam create-policy \
  --policy-name ElastiCacheWorkshopPolicy \
  --policy-document file://elasticache-policy.json

# Attach to your user (replace with your username and account ID)
aws iam attach-user-policy \
  --user-name YOUR_USERNAME \
  --policy-arn arn:aws:iam::YOUR_ACCOUNT_ID:policy/ElastiCacheWorkshopPolicy
```

### Solution 2: Use IAM Role with Sufficient Permissions

If you're using an IAM role (e.g., via AWS SSO), ensure the role has ElastiCache permissions:

```bash
# Check your current identity
aws sts get-caller-identity

# If using a role, contact your AWS administrator to add:
# - AmazonElastiCacheFullAccess (managed policy)
# OR
# - Custom policy with elasticache:* permissions
```

### Solution 3: Verify All Required Permissions

For this workshop, your IAM user/role needs these AWS managed policies:

```bash
# List of required managed policies
POLICIES=(
  "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
  "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  "arn:aws:iam::aws:policy/AmazonRDSFullAccess"
  "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
  "arn:aws:iam::aws:policy/AmazonElastiCacheFullAccess"
  "arn:aws:iam::aws:policy/AmazonMQFullAccess"
  "arn:aws:iam::aws:policy/CloudWatchFullAccess"
  "arn:aws:iam::aws:policy/IAMFullAccess"
  "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
)

# Get your username
USERNAME=$(aws sts get-caller-identity --query 'Arn' --output text | cut -d'/' -f2)

# Attach all policies
for policy in "${POLICIES[@]}"; do
  echo "Attaching $policy..."
  aws iam attach-user-policy --user-name $USERNAME --policy-arn $policy
done
```

**OR use AdministratorAccess for simplicity (non-production only):**

```bash
USERNAME=$(aws sts get-caller-identity --query 'Arn' --output text | cut -d'/' -f2)

aws iam attach-user-policy \
  --user-name $USERNAME \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

---

## Complete Fix Workflow

### Step 1: Fix IAM Permissions First

```bash
# Check current permissions
aws elasticache describe-replication-groups --region us-east-1

# If you get 403, add permissions:
USERNAME=$(aws sts get-caller-identity --query 'Arn' --output text | cut -d'/' -f2)

aws iam attach-user-policy \
  --user-name $USERNAME \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

# Wait 30 seconds for IAM propagation
sleep 30

# Verify permissions
aws elasticache describe-replication-groups --region us-east-1
```

### Step 2: Fix metrics-server Issue

Navigate to your Terraform directory and check if metrics-server is defined:

```bash
cd terraform/eks

# Search for metrics-server in Terraform files
grep -r "metrics-server" .
```

If found, edit the file and remove/comment out the metrics-server add-on:

```bash
# Example: Edit main.tf or eks.tf
# Remove or comment out the metrics-server block
```

### Step 3: Re-run Terraform

```bash
# If you already ran terraform apply and it failed:
terraform apply

# Terraform will continue from where it failed
# Type 'yes' when prompted
```

### Step 4: Verify Deployment

```bash
# Check EKS cluster
aws eks describe-cluster --name retail-store --region us-east-1

# Check ElastiCache
aws elasticache describe-replication-groups --region us-east-1

# Check all pods
kubectl get pods --all-namespaces
```

---

## Alternative: Skip ElastiCache (Checkout Service)

If you want to proceed without ElastiCache/Redis (checkout service won't work):

### Option 1: Comment out ElastiCache resources

In your Terraform files, comment out:

```hcl
# resource "aws_elasticache_replication_group" "redis" {
#   ...
# }

# resource "aws_elasticache_subnet_group" "redis" {
#   ...
# }

# resource "aws_security_group" "redis_sg" {
#   ...
# }
```

And comment out the checkout service Helm release:

```hcl
# resource "helm_release" "checkout" {
#   ...
# }
```

### Option 2: Use Terraform variables to disable optional components

Check if the Terraform code supports variables like:

```hcl
variable "enable_redis" {
  default = true
}

variable "enable_checkout_service" {
  default = true
}
```

If so, create `terraform.tfvars`:

```hcl
enable_redis = false
enable_checkout_service = false
```

---

## Verification Commands

After fixing the issues, verify everything is working:

```bash
# 1. Check Terraform state
terraform show | grep -A 5 "eks_cluster"
terraform show | grep -A 5 "elasticache"

# 2. Check EKS add-ons
aws eks list-addons --cluster-name retail-store --region us-east-1

# 3. Check ElastiCache
aws elasticache describe-replication-groups --region us-east-1

# 4. Check all Kubernetes resources
kubectl get all --all-namespaces

# 5. Check for any failing pods
kubectl get pods --all-namespaces | grep -v Running

# 6. Get application URL
terraform output ui_alb_url
```

---

## Still Having Issues?

### Check Terraform State

```bash
# View current state
terraform state list

# Check specific resources
terraform state show module.eks
terraform state show aws_elasticache_replication_group.redis
```

### Enable Terraform Debug Logging

```bash
# Enable detailed logging
export TF_LOG=DEBUG
export TF_LOG_PATH=./terraform-debug.log

# Run terraform apply again
terraform apply

# Review the log
tail -f terraform-debug.log
```

### Clean State and Retry

If Terraform state is corrupted:

```bash
# CAUTION: This will destroy everything
terraform destroy

# Remove state files
rm -rf .terraform
rm terraform.tfstate*

# Start fresh
terraform init
terraform apply
```

---

## Quick Reference: Common Error Fixes

| Error | Quick Fix |
|-------|-----------|
| `metrics-server not available` | Remove from `cluster_addons` or install via Helm |
| `403 DescribeReplicationGroups` | Add `AmazonElastiCacheFullAccess` policy |
| `403 CreateCluster` | Add `AmazonEKSClusterPolicy` |
| `403 CreateDBInstance` | Add `AmazonRDSFullAccess` |
| `InvalidParameterException` | Check region is `us-east-1` |
| `Subnet not found` | Ensure VPC module completed successfully |
| `Security group not found` | Check VPC and security group dependencies |

---

## Contact Support

If issues persist:

1. Check GitHub Issues: https://github.com/aws-samples/sample-devops-agent-eks-workshop/issues
2. Review AWS Service Health: https://status.aws.amazon.com/
3. Check AWS Support Center (if you have support plan)

---

**Good luck! 🚀**
