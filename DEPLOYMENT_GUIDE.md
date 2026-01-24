# Local Deployment Guide - AWS DevOps Agent EKS Workshop

## Prerequisites Installation

### 1. Install Homebrew (if not already installed)
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### 2. Install AWS CLI
```bash
brew install awscli

# Verify installation
aws --version
```

### 3. Install Terraform
```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# Verify installation
terraform --version
```

### 4. Install kubectl
```bash
brew install kubectl

# Verify installation
kubectl version --client
```

### 5. Install Helm (Optional - for manual chart management)
```bash
brew install helm

# Verify installation
helm version
```

### 6. Install Git (if not already installed)
```bash
brew install git

# Verify installation
git --version
```

---

## AWS Account Setup

### 1. Configure AWS Credentials
```bash
# Configure AWS CLI with your credentials
aws configure

# You'll be prompted for:
# - AWS Access Key ID
# - AWS Secret Access Key
# - Default region (use: us-east-1)
# - Default output format (use: json)
```

**Verify your credentials:**
```bash
aws sts get-caller-identity
```

Expected output:
```json
{
    "UserId": "XXXXXXXXXXXXXXXXX",
    "Account": "yyyyyy",
    "Arn": "arn:aws:iam::zzzzz:user/your-username"
}
```

### 2. Verify Required IAM Permissions
Your IAM user/role needs permissions for:
- EC2 (VPC, subnets, security groups)
- EKS (cluster creation, node groups)
- RDS (Aurora, MySQL)
- DynamoDB
- ElastiCache
- Amazon MQ
- CloudWatch
- IAM (role creation)
- Secrets Manager

**Recommended:** Use `AdministratorAccess` policy for this workshop (non-production only).

---

## Clone the Repository

```bash
# Create a workspace directory
mkdir -p ~/aws-workshops
cd ~/aws-workshops

# Clone the repository
git clone https://github.com/aws-samples/sample-devops-agent-eks-workshop.git

# Navigate to the project
cd sample-devops-agent-eks-workshop

# Verify structure
ls -la
```

---

## Terraform Deployment

### 1. Navigate to Terraform Directory
```bash
cd terraform/eks
```

### 2. Review and Customize Variables (Optional)

Create a `terraform.tfvars` file to customize deployment:

```bash
cat > terraform.tfvars << 'EOF'
# Cluster configuration
cluster_name = "retail-store"
region       = "us-east-1"

# Grafana (requires AWS IAM Identity Center)
enable_grafana = false  # Set to true if you have SSO configured

# Tags
tags = {
  Environment = "workshop"
  Owner       = "your-name"
  Project     = "devops-agent-demo"
}
EOF
```

### 3. Initialize Terraform
```bash
# Download provider plugins and modules
terraform init
```

Expected output:
```
Initializing modules...
Initializing the backend...
Initializing provider plugins...
Terraform has been successfully initialized!
```

### 4. Validate Configuration
```bash
# Check for syntax errors
terraform validate
```

### 5. Preview Changes
```bash
# See what will be created (takes 1-2 minutes)
terraform plan
```

Review the output - you should see ~100+ resources to be created.

### 6. Deploy Infrastructure
```bash
# Deploy everything (takes 15-20 minutes)
terraform apply

# When prompted, type: yes
```

**What happens during deployment:**
- ✅ VPC with public/private subnets (2 min)
- ✅ EKS cluster and node groups (10-12 min)
- ✅ RDS Aurora, MySQL, DynamoDB (3-5 min)
- ✅ ElastiCache Redis, Amazon MQ (2-3 min)
- ✅ Observability stack (2 min)
- ✅ Application deployment via Helm (2-3 min)

**☕ Grab coffee - this takes ~20 minutes!**

### 7. Save Terraform Outputs
```bash
# Save important outputs
terraform output > ../outputs.txt

# View cluster name
terraform output cluster_name

# View application URL
terraform output ui_alb_url
```

---

## Configure kubectl Access

### 1. Update kubeconfig
```bash
# Get cluster name from Terraform output
CLUSTER_NAME=$(terraform output -raw cluster_name)

# Configure kubectl
aws eks update-kubeconfig --region us-east-1 --name $CLUSTER_NAME
```

Expected output:
```
Added new context arn:aws:eks:us-east-1:123456789012:cluster/retail-store to /Users/yourname/.kube/config
```

### 2. Verify Cluster Access
```bash
# Check cluster info
kubectl cluster-info

# List nodes
kubectl get nodes

# Check all pods
kubectl get pods --all-namespaces
```

Expected output:
```
NAME                                        STATUS   ROLES    AGE   VERSION
ip-10-0-1-123.us-east-1.compute.internal   Ready    <none>   5m    v1.28.x
ip-10-0-2-456.us-east-1.compute.internal   Ready    <none>   5m    v1.28.x
ip-10-0-3-789.us-east-1.compute.internal   Ready    <none>   5m    v1.28.x
```

---

## Verify Application Deployment

### 1. Check Application Pods
```bash
# Check all application namespaces
kubectl get pods -n ui
kubectl get pods -n catalog
kubectl get pods -n carts
kubectl get pods -n orders
kubectl get pods -n checkout
```

All pods should show `STATUS: Running` and `READY: 1/1`.

### 2. Get Application Load Balancer URL
```bash
# Get ALB URL from Terraform
terraform output ui_alb_url

# Or get from Kubernetes ingress
kubectl get ingress -n ui
```

Example output:
```
http://k8s-ui-ui-abc123def456-1234567890.us-east-1.elb.amazonaws.com
```

### 3. Wait for ALB to be Ready
```bash
# Check ALB target health (takes 2-3 minutes)
ALB_URL=$(terraform output -raw ui_alb_url)

# Test connectivity
curl -I $ALB_URL
```

Wait until you get `HTTP/1.1 200 OK` response.

### 4. Access the Application
```bash
# Open in browser
open $(terraform output -raw ui_alb_url)
```

You should see the **Retail Store Sample App** homepage!

---

## Configure AWS DevOps Agent (Optional)

### 1. Access DevOps Agent Console
```bash
# Open AWS Console in us-east-1
open "https://us-east-1.console.aws.amazon.com/devops-agent/home?region=us-east-1"
```

### 2. Create Agent Space
1. Click **Create Agent Space**
2. Enter name: `retail-store-eks-workshop`
3. Select **Auto-create a new AWS DevOps Agent role**
4. Under **Include AWS tags**, add:
   - Key: `eksdevopsagent`
   - Value: `true`
5. Enable **Web App** with auto-created role
6. Click **Submit**

### 3. Configure EKS Access for DevOps Agent

Get the DevOps Agent IAM role ARN:
```bash
# From AWS Console → DevOps Agent → Your Agent Space → Settings
# Copy the "Agent Space role ARN"
```

Add access entry to EKS:
```bash
# Get cluster name
CLUSTER_NAME=$(terraform output -raw cluster_name)

# Get DevOps Agent role ARN (replace with your actual ARN)
AGENT_ROLE_ARN="arn:aws:iam::123456789012:role/DevOpsAgentRole-xxxxx"

# Create access entry
aws eks create-access-entry \
  --cluster-name $CLUSTER_NAME \
  --principal-arn $AGENT_ROLE_ARN \
  --type STANDARD \
  --region us-east-1

# Associate access policy
aws eks associate-access-policy \
  --cluster-name $CLUSTER_NAME \
  --principal-arn $AGENT_ROLE_ARN \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy \
  --access-scope type=cluster \
  --region us-east-1
```

---

## Test Fault Injection (Optional)

### 1. Navigate to Fault Injection Scripts
```bash
cd ../../fault-injection

# Make scripts executable
chmod +x *.sh
```

### 2. Run a Fault Injection Scenario
```bash
# Example: Inject catalog latency
./inject-catalog-latency.sh

# Wait 2-3 minutes for symptoms to appear
# Check application - product pages should be slow
```

### 3. Investigate with DevOps Agent
1. Open DevOps Agent Web App
2. Click **Start Investigation**
3. Enter: "Product pages are loading slowly"
4. Watch the agent investigate!

### 4. Rollback the Fault
```bash
# Restore normal operation
./rollback-catalog.sh
```

---

## Monitoring and Observability

### 1. CloudWatch Container Insights
```bash
# Open CloudWatch Console
open "https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#container-insights:infrastructure"
```

Select your cluster from the dropdown.

### 2. View Application Logs
```bash
# View logs for a specific service
kubectl logs -n catalog -l app=catalog --tail=50 -f

# View logs in CloudWatch
open "https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#logsV2:log-groups/log-group//aws/containerinsights/retail-store/application"
```

### 3. Check Prometheus Metrics
```bash
# Get Prometheus endpoint
terraform output prometheus_endpoint
```

### 4. Access Grafana (if enabled)
```bash
# Get Grafana URL
terraform output grafana_workspace_url

# Open in browser
open $(terraform output -raw grafana_workspace_url)
```

---

## Troubleshooting

### Issue: Terraform apply fails with "InvalidParameterException"
**Solution:** Ensure you're using `us-east-1` region (DevOps Agent requirement).

### Issue: Pods stuck in "Pending" state
**Solution:** Check node status and events:
```bash
kubectl get nodes
kubectl describe pod <pod-name> -n <namespace>
```

### Issue: ALB returns 503 Service Unavailable
**Solution:** Wait 2-3 minutes for target health checks to pass:
```bash
kubectl get pods -n ui
kubectl describe ingress -n ui
```

### Issue: Cannot access application URL
**Solution:** Verify security group rules allow your IP:
```bash
# Get ALB security group
aws elbv2 describe-load-balancers --region us-east-1 | grep SecurityGroups

# Check inbound rules
aws ec2 describe-security-groups --group-ids <sg-id> --region us-east-1
```

### Issue: Database connection errors in pod logs
**Solution:** Verify security groups allow EKS nodes:
```bash
# Check RDS security group
kubectl logs -n catalog -l app=catalog --tail=20

# Verify security group rules in AWS Console
```

---

## Cleanup

### ⚠️ IMPORTANT: Cleanup to Avoid Charges

When you're done, destroy all resources:

```bash
# Navigate to terraform directory
cd ~/aws-workshops/sample-devops-agent-eks-workshop/terraform/eks

# Use the cleanup script (recommended)
chmod +x ../../scripts/destroy.sh
../../scripts/destroy.sh

# OR manual cleanup:
terraform destroy

# When prompted, type: yes
```

**Cleanup takes ~10-15 minutes.**

### Verify Cleanup
```bash
# Check for remaining resources
aws eks list-clusters --region us-east-1
aws rds describe-db-instances --region us-east-1
aws dynamodb list-tables --region us-east-1
```

### Manual Cleanup (if needed)
```bash
# Delete CloudWatch log groups
aws logs describe-log-groups --region us-east-1 | grep retail-store

aws logs delete-log-group \
  --log-group-name /aws/containerinsights/retail-store/application \
  --region us-east-1
```

---

## Cost Estimation

**Approximate hourly costs (us-east-1):**
- EKS cluster: $0.10/hour
- EC2 nodes (3x m5.large): $0.29/hour
- RDS Aurora: $0.29/hour
- ElastiCache: $0.017/hour
- Amazon MQ: $0.30/hour
- NAT Gateways: $0.135/hour
- **Total: ~$1.15/hour** (~$28/day)

**💡 Tip:** Destroy resources when not in use to minimize costs!

---

## Next Steps

1. ✅ Explore the application UI
2. ✅ Run fault injection scenarios
3. ✅ Investigate with DevOps Agent
4. ✅ Review CloudWatch metrics and logs
5. ✅ Examine Kubernetes resources
6. ✅ Test auto-scaling and resilience
7. ✅ Clean up resources when done

---

## Useful Commands Reference

```bash
# Terraform
terraform init          # Initialize
terraform plan          # Preview changes
terraform apply         # Deploy
terraform destroy       # Cleanup
terraform output        # View outputs

# kubectl
kubectl get pods -A                    # All pods
kubectl get svc -A                     # All services
kubectl logs <pod> -n <namespace>      # Pod logs
kubectl describe pod <pod> -n <ns>     # Pod details
kubectl exec -it <pod> -n <ns> -- bash # Shell into pod

# AWS CLI
aws eks list-clusters --region us-east-1
aws eks describe-cluster --name <cluster> --region us-east-1
aws rds describe-db-instances --region us-east-1
aws dynamodb list-tables --region us-east-1

# Helm
helm list -A                           # All releases
helm status <release> -n <namespace>   # Release status
```

---

## Support Resources

- **Repository:** https://github.com/aws-samples/sample-devops-agent-eks-workshop
- **AWS DevOps Agent Docs:** https://docs.aws.amazon.com/devops-agent/
- **EKS Documentation:** https://docs.aws.amazon.com/eks/
- **Terraform AWS Provider:** https://registry.terraform.io/providers/hashicorp/aws/

---

**Happy Deploying! 🚀**
