# Fix Expired AWS Credentials

## Quick Fix - Choose Your Authentication Method

### Method 1: AWS SSO (Most Common for Enterprise Users)

If you're using AWS SSO (Single Sign-On):

```bash
# Login to AWS SSO
aws sso login

# If you have a specific profile
aws sso login --profile your-profile-name

# Verify it works
aws sts get-caller-identity
```

**If you don't have SSO configured yet:**

```bash
# Configure SSO
aws configure sso

# You'll be prompted for:
# - SSO start URL (e.g., https://your-company.awsapps.com/start)
# - SSO region (e.g., us-east-1)
# - Account ID
# - Role name
# - CLI default region
# - Output format
```

---

### Method 2: Long-term IAM User Credentials (Recommended for Workshop)

If you have an IAM user with access keys:

```bash
# Reconfigure AWS CLI with fresh credentials
aws configure

# You'll be prompted for:
# AWS Access Key ID: [Enter your access key]
# AWS Secret Access Key: [Enter your secret key]
# Default region name: us-east-1
# Default output format: json

# Verify it works
aws sts get-caller-identity
```

**To get new access keys:**

1. Go to AWS Console: https://console.aws.amazon.com/iam/
2. Navigate to: IAM → Users → [Your Username] → Security credentials
3. Click "Create access key"
4. Choose "Command Line Interface (CLI)"
5. Download the credentials
6. Run `aws configure` and enter the new keys

---

### Method 3: Temporary Credentials (Session Token)

If you're using MFA or temporary credentials:

```bash
# Get new session token with MFA
aws sts get-session-token \
  --serial-number arn:aws:iam::ACCOUNT_ID:mfa/USERNAME \
  --token-code 123456

# This returns:
# - AccessKeyId
# - SecretAccessKey  
# - SessionToken
# - Expiration

# Set them as environment variables
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_SESSION_TOKEN="your-session-token"

# Verify
aws sts get-caller-identity
```

---

### Method 4: AWS Profiles

If you have multiple AWS profiles configured:

```bash
# List available profiles
cat ~/.aws/credentials

# Use a specific profile
export AWS_PROFILE=your-profile-name

# Or specify in each command
aws sts get-caller-identity --profile your-profile-name

# For Terraform, set the profile
export AWS_PROFILE=your-profile-name
terraform apply
```

---

## Recommended Solution for This Workshop

**Use IAM User with Long-term Credentials:**

### Step 1: Create IAM User (if you don't have one)

```bash
# Via AWS Console:
# 1. Go to IAM → Users → Create user
# 2. Username: workshop-user
# 3. Enable "Provide user access to AWS Management Console" (optional)
# 4. Attach policy: AdministratorAccess (for workshop only!)
# 5. Create user
# 6. Go to Security credentials → Create access key
# 7. Choose "Command Line Interface (CLI)"
# 8. Download credentials
```

### Step 2: Configure AWS CLI

```bash
# Configure with your new credentials
aws configure

# Enter when prompted:
AWS Access Key ID: AKIAIOSFODNN7EXAMPLE
AWS Secret Access Key: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
Default region name: us-east-1
Default output format: json
```

### Step 3: Verify

```bash
# Test credentials
aws sts get-caller-identity

# Expected output:
{
    "UserId": "AIDACKCEVSQ6C2EXAMPLE",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/workshop-user"
}
```

### Step 4: Add Required Permissions

```bash
# Get your username from the output above
USERNAME="workshop-user"

# Add all required permissions
aws iam attach-user-policy \
  --user-name $USERNAME \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

---

## Troubleshooting

### Issue: "aws configure" doesn't prompt for input

```bash
# Manually edit credentials file
nano ~/.aws/credentials

# Add:
[default]
aws_access_key_id = YOUR_ACCESS_KEY
aws_secret_access_key = YOUR_SECRET_KEY

# Edit config file
nano ~/.aws/config

# Add:
[default]
region = us-east-1
output = json
```

### Issue: Still getting ExpiredToken after aws configure

```bash
# Clear any environment variables that might override
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN
unset AWS_PROFILE

# Remove old credentials
rm -rf ~/.aws/credentials
rm -rf ~/.aws/config

# Reconfigure
aws configure

# Verify
aws sts get-caller-identity
```

### Issue: Using AWS SSO but login fails

```bash
# Clear SSO cache
rm -rf ~/.aws/sso/cache/

# Reconfigure SSO
aws configure sso

# Login again
aws sso login
```

### Issue: Multiple profiles causing confusion

```bash
# Check what's configured
cat ~/.aws/credentials
cat ~/.aws/config

# See which profile is active
echo $AWS_PROFILE

# Clear profile override
unset AWS_PROFILE

# Use default profile
aws sts get-caller-identity
```

---

## Quick Verification Checklist

After fixing credentials, verify everything:

```bash
# 1. Check identity
aws sts get-caller-identity

# 2. Check region
aws configure get region

# 3. Test EC2 permissions
aws ec2 describe-vpcs --region us-east-1

# 4. Test EKS permissions
aws eks list-clusters --region us-east-1

# 5. Test ElastiCache permissions
aws elasticache describe-replication-groups --region us-east-1
```

All commands should work without errors.

---

## For Terraform Deployment

Once credentials are fixed:

```bash
# Navigate to terraform directory
cd terraform/eks

# Verify Terraform can authenticate
terraform init

# Run deployment
terraform apply
```

---

## Security Best Practices

**For Production:**
- ✅ Use AWS SSO with temporary credentials
- ✅ Enable MFA on IAM users
- ✅ Use least-privilege IAM policies
- ✅ Rotate access keys regularly
- ❌ Don't use AdministratorAccess

**For This Workshop:**
- ✅ Use IAM user with AdministratorAccess (simplest)
- ✅ Delete the user after workshop
- ✅ Use us-east-1 region
- ❌ Don't commit credentials to git

---

## Still Having Issues?

### Check AWS CLI Installation

```bash
# Check AWS CLI version
aws --version

# Should be v2.x.x
# If not, reinstall:
brew upgrade awscli
```

### Check Credentials File Location

```bash
# macOS/Linux
ls -la ~/.aws/

# Should show:
# - credentials
# - config

# View contents (be careful not to share these!)
cat ~/.aws/credentials
cat ~/.aws/config
```

### Enable Debug Mode

```bash
# See detailed authentication flow
aws sts get-caller-identity --debug
```

---

## Next Steps After Fixing Credentials

1. ✅ Verify: `aws sts get-caller-identity`
2. ✅ Add permissions: Run `./fix-permissions.sh`
3. ✅ Deploy: `cd terraform/eks && terraform apply`

---

**Good luck! 🚀**
