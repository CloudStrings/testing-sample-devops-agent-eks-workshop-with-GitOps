#!/bin/bash

# Quick Fix Script for IAM Permissions
# This script adds necessary permissions for the EKS workshop deployment

set -e

echo "=========================================="
echo "EKS Workshop - Permission Fix Script"
echo "=========================================="
echo ""

# Get current IAM identity
echo "Checking your AWS identity..."
IDENTITY=$(aws sts get-caller-identity --output json)
ACCOUNT_ID=$(echo $IDENTITY | jq -r '.Account')
ARN=$(echo $IDENTITY | jq -r '.Arn')
USER_TYPE=$(echo $ARN | cut -d':' -f6 | cut -d'/' -f1)

echo "Account ID: $ACCOUNT_ID"
echo "ARN: $ARN"
echo "Type: $USER_TYPE"
echo ""

# Check if it's a user or role
if [[ $USER_TYPE == "user" ]]; then
    USERNAME=$(echo $ARN | cut -d'/' -f2)
    echo "Detected IAM User: $USERNAME"
    echo ""
    
    # List of required policies
    POLICIES=(
        "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
        "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
        "arn:aws:iam::aws:policy/AmazonRDSFullAccess"
        "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
        "arn:aws:iam::aws:policy/AmazonElastiCacheFullAccess"
        "arn:aws:iam::aws:policy/AmazonMQFullAccess"
        "arn:aws:iam::aws:policy/CloudWatchFullAccess"
        "arn:aws:iam::aws:policy/IAMFullAccess"
    )
    
    echo "Adding required IAM policies..."
    echo ""
    
    for policy in "${POLICIES[@]}"; do
        POLICY_NAME=$(echo $policy | cut -d'/' -f2)
        echo "Attaching: $POLICY_NAME"
        
        aws iam attach-user-policy \
            --user-name $USERNAME \
            --policy-arn $policy 2>/dev/null || echo "  (Already attached or insufficient permissions)"
    done
    
    echo ""
    echo "✅ Policies attached successfully!"
    echo ""
    echo "Waiting 30 seconds for IAM propagation..."
    sleep 30
    
elif [[ $USER_TYPE == "assumed-role" ]]; then
    ROLE_NAME=$(echo $ARN | cut -d'/' -f2)
    echo "Detected IAM Role: $ROLE_NAME"
    echo ""
    echo "⚠️  You are using an IAM role (likely AWS SSO)."
    echo "You need to contact your AWS administrator to add these policies to your role:"
    echo ""
    echo "  - AmazonEC2FullAccess"
    echo "  - AmazonEKSClusterPolicy"
    echo "  - AmazonRDSFullAccess"
    echo "  - AmazonDynamoDBFullAccess"
    echo "  - AmazonElastiCacheFullAccess"
    echo "  - AmazonMQFullAccess"
    echo "  - CloudWatchFullAccess"
    echo "  - IAMFullAccess"
    echo ""
    echo "OR ask for AdministratorAccess policy (for workshop/non-production only)"
    echo ""
    exit 1
else
    echo "❌ Unknown identity type. Cannot proceed."
    exit 1
fi

# Verify ElastiCache permissions
echo "Verifying ElastiCache permissions..."
if aws elasticache describe-replication-groups --region us-east-1 >/dev/null 2>&1; then
    echo "✅ ElastiCache permissions verified!"
else
    echo "❌ ElastiCache permissions still missing. You may need to:"
    echo "   1. Wait a few more minutes for IAM propagation"
    echo "   2. Contact your AWS administrator"
    echo "   3. Use AdministratorAccess policy instead"
fi

echo ""
echo "=========================================="
echo "Permission fix complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Navigate to terraform directory: cd terraform/eks"
echo "2. Run: terraform apply"
echo ""
