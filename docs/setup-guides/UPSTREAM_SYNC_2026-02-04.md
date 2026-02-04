# Upstream Sync - February 4, 2026

## Summary
Successfully merged 4 new commits from the upstream repository (aws-samples/sample-devops-agent-eks-workshop) into your fork while preserving all GitOps customizations.

## Upstream Repository
- **Source**: https://github.com/aws-samples/sample-devops-agent-eks-workshop
- **Your Fork**: https://github.com/CloudStrings/testing-sample-devops-agent-eks-workshop-with-GitOps
- **Merge Commit**: 75fe3ec

## Changes Merged

### 1. One-Click Deploy Script (New File)
**File**: `terraform/deploy.sh`
**Author**: shyam kulkarni
**Date**: Jan 25, 2026

**Features**:
- Automated deployment with validation
- Helm prerequisite check
- Network connectivity check to AWS endpoints
- ECR Public authentication (prevents 403 rate limit errors)
- Edge case handling and better error messages
- Cleanup trap for failed deployments

**Usage**:
```bash
./terraform/deploy.sh
```

### 2. Enhanced README
**File**: `README.md`
**Changes**:
- Reduced from 1550 lines to ~280 lines
- Added "What is this Workshop?" section
- Explained inject-investigate-learn approach
- Added visual workflow diagram
- Rewrote fault injection scenarios to match Workshop Studio format
- Added detailed investigation prompts
- Added Key Learnings sections for each lab
- Added OOMKilled exit codes table
- Added DynamoDB metrics monitoring table

### 3. Improved Destroy Script
**File**: `terraform/destroy.sh`
**Author**: shyam kulkarni
**Date**: Jan 26, 2026

**Enhancements**:
- Comprehensive VPC cleanup after terraform destroy
- Deletes remaining VPC endpoints
- Handles ENI detachment and deletion
- Deletes GuardDuty managed security groups
- Removes subnets, internet gateway, NAT gateways
- Ensures VPC deletion completes without manual intervention

**New Cleanup Steps**:
1. Delete VPC endpoints
2. Detach and delete ENIs
3. Delete non-default security groups
4. Delete subnets
5. Detach and delete internet gateway
6. Delete NAT gateways (with 60s wait)
7. Delete VPC

### 4. Workshop Introduction
**File**: `README.md`
**Added Section**: "What is this Workshop?"

Explains:
- Purpose: Demonstrate AWS DevOps Agent investigation capabilities
- Workflow: Deploy → Inject → Investigate → Learn
- Learning outcomes: How the agent analyzes logs, metrics, traces, and configurations

## Merge Strategy

### Automatic Merge
The merge completed automatically with no conflicts because:
- Your GitOps customizations are in separate directories (`argocd-apps/`, `helm-charts/`, `docs/setup-guides/`, `scripts/`)
- Upstream changes were in different files (`README.md`, `terraform/deploy.sh`, `terraform/destroy.sh`)
- Your Terraform modifications (`kubernetes.tf`, `output.tf`, `data.tf`) were not touched by upstream

### Preserved Customizations
All your GitOps work remains intact:
- ✅ ArgoCD App of Apps configuration
- ✅ Helm charts with Terraform infrastructure values
- ✅ Complete documentation suite (17 guides)
- ✅ Helper scripts (5 automation scripts)
- ✅ Terraform/ArgoCD separation
- ✅ All application configurations

## Files Changed in Merge

| File | Status | Description |
|------|--------|-------------|
| README.md | Modified | Streamlined and enhanced |
| terraform/deploy.sh | Added | New one-click deployment |
| terraform/destroy.sh | Modified | Enhanced VPC cleanup |

## Verification

### Before Merge
```bash
git log --oneline -5
b8d2263 docs: Add comprehensive README for setup guides directory
d7aae2a docs: Organize documentation and scripts into repository structure
b1832c3 fix: Add missing app.persistence.provider to checkout values.yaml
ad4b4aa Configure Helm charts with Terraform infrastructure values
68fa234 Scale all services to 2 replicas for HA
```

### After Merge
```bash
git log --oneline -6
75fe3ec Merge upstream improvements from aws-samples/sample-devops-agent-eks-workshop
b8d2263 docs: Add comprehensive README for setup guides directory
d7aae2a docs: Organize documentation and scripts into repository structure
b1832c3 fix: Add missing app.persistence.provider to checkout values.yaml
ad4b4aa Configure Helm charts with Terraform infrastructure values
68fa234 Scale all services to 2 replicas for HA
```

## Testing Recommendations

### 1. Test New Deploy Script
```bash
# Dry run to see what it would do
./terraform/deploy.sh --help

# Full deployment (if starting fresh)
./terraform/deploy.sh
```

### 2. Verify Destroy Script
```bash
# When ready to cleanup
cd terraform/eks/default
terraform destroy -auto-approve
cd ../../..
./terraform/destroy.sh
```

### 3. Review README Changes
The new README is much more concise and workshop-focused. Your detailed documentation is preserved in `docs/setup-guides/`.

## Future Syncs

To sync with upstream in the future:

```bash
# Fetch latest changes
git fetch upstream

# Check what's new
git log HEAD..upstream/main --oneline

# Merge changes
git merge upstream/main

# Resolve any conflicts if needed
# Then push
git push origin main
```

## Benefits of These Changes

1. **Easier Deployment**: One-click deploy script simplifies setup
2. **Better Cleanup**: Enhanced destroy script prevents VPC deletion issues
3. **Clearer Documentation**: Streamlined README focuses on workshop goals
4. **Maintained Customizations**: All your GitOps work preserved

## Next Steps

1. ✅ Merge completed successfully
2. ✅ Changes pushed to your fork
3. ⏭️ Test the new deploy.sh script (optional)
4. ⏭️ Review the updated README
5. ⏭️ Continue using your GitOps workflow as before

---

**Sync Date**: February 4, 2026
**Status**: ✅ Complete
**Conflicts**: None
**Files Preserved**: All GitOps customizations intact
