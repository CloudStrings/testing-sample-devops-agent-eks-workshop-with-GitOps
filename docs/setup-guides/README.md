# Setup Guides and Documentation

This directory contains comprehensive documentation for setting up and managing the DevOps Agent EKS Workshop with GitOps.

## Quick Start

1. **[DEPLOYMENT_GUIDE.md](../../DEPLOYMENT_GUIDE.md)** - Start here for initial deployment
2. **[GITOPS_SETUP_GUIDE.md](GITOPS_SETUP_GUIDE.md)** - GitOps workflow setup with ArgoCD

## Documentation Index

### Core Setup Guides
- **[GITOPS_SETUP_GUIDE.md](GITOPS_SETUP_GUIDE.md)** - Complete GitOps setup with ArgoCD
- **[ARGOCD_CONFIGURATION_GUIDE.md](ARGOCD_CONFIGURATION_GUIDE.md)** - ArgoCD configuration details
- **[ARGOCD_MULTI_SERVICE_GUIDE.md](ARGOCD_MULTI_SERVICE_GUIDE.md)** - Multi-service deployment guide

### ArgoCD App of Apps Pattern
- **[APP_OF_APPS_QUICKSTART.md](APP_OF_APPS_QUICKSTART.md)** - Quick start for App of Apps pattern
- **[ARGOCD_APP_OF_APPS_TROUBLESHOOTING.md](ARGOCD_APP_OF_APPS_TROUBLESHOOTING.md)** - Troubleshooting guide
- **[ARGOCD_STRUCTURE_EXPLAINED.md](ARGOCD_STRUCTURE_EXPLAINED.md)** - Architecture explanation

### Terraform and ArgoCD Separation
- **[TERRAFORM_ARGOCD_SEPARATION_PLAN.md](TERRAFORM_ARGOCD_SEPARATION_PLAN.md)** - Separation strategy
- **[SEPARATION_ANALYSIS.md](SEPARATION_ANALYSIS.md)** - Detailed analysis
- **[CLEANUP_TERRAFORM_APPS.md](CLEANUP_TERRAFORM_APPS.md)** - Cleanup procedures
- **[TERRAFORM_PLAN_SUCCESS.md](TERRAFORM_PLAN_SUCCESS.md)** - Verification guide

### Helm Configuration
- **[ARGOCD_HELM_VALUES_GUIDE.md](ARGOCD_HELM_VALUES_GUIDE.md)** - Helm values configuration
- **[HELM_VALUES_UPDATED_SUMMARY.md](HELM_VALUES_UPDATED_SUMMARY.md)** - Update summary

### Troubleshooting and Fixes
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** - General troubleshooting
- **[ARGOCD_CHECKOUT_FIX.md](ARGOCD_CHECKOUT_FIX.md)** - Checkout service fix
- **[fix-expired-credentials.md](fix-expired-credentials.md)** - AWS credentials issues

### Success Reports
- **[GITOPS_DEPLOYMENT_SUCCESS.md](GITOPS_DEPLOYMENT_SUCCESS.md)** - Final deployment status

## Helper Scripts

All helper scripts are located in `../../scripts/`:

- **[argocd-app-of-apps-setup.sh](../../scripts/argocd-app-of-apps-setup.sh)** - Automated ArgoCD setup
- **[setup-helm-charts-for-argocd.sh](../../scripts/setup-helm-charts-for-argocd.sh)** - Helm chart setup
- **[update-helm-values-with-terraform-outputs.sh](../../scripts/update-helm-values-with-terraform-outputs.sh)** - Sync Terraform outputs to Helm
- **[test-application.sh](../../scripts/test-application.sh)** - Application testing
- **[fix-permissions.sh](../../scripts/fix-permissions.sh)** - IAM permissions fix

## Architecture Overview

```
Terraform (Infrastructure)          ArgoCD (Applications)
├── EKS Cluster                     ├── UI Service
├── VPC & Networking                ├── Catalog Service
├── RDS (MySQL, PostgreSQL)         ├── Carts Service
├── DynamoDB                        ├── Orders Service
├── ElastiCache Redis               └── Checkout Service
├── RabbitMQ
├── IAM Roles
└── Security Groups
```

## Workflow

1. **Infrastructure**: Terraform provisions AWS resources
2. **GitOps**: ArgoCD syncs applications from GitHub
3. **Automation**: Changes pushed to GitHub trigger automatic deployments
4. **Monitoring**: ArgoCD UI shows real-time application status

## Access Points

- **Application UI**: Check ALB URL in deployment output
- **ArgoCD UI**: Check ArgoCD service URL
- **Kubernetes**: `kubectl` commands for cluster access

## Support

For issues or questions:
1. Check the troubleshooting guides
2. Review ArgoCD application status
3. Check pod logs: `kubectl logs -n <namespace> <pod-name>`
4. Verify Terraform outputs match Helm values

---

**Last Updated**: February 4, 2026
**Status**: Production Ready
