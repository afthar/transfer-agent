# GitHub Secrets Configuration Guide

## 🔐 Required GitHub Secrets

This document lists all the GitHub secrets you need to configure for the Transfer Worker CI/CD pipeline.

### How to Add Secrets

1. Navigate to your repository on GitHub
2. Go to **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Add each secret listed below

## 📋 Secrets List

### AWS Secrets

| Secret Name | Description | How to Get It |
|-------------|-------------|---------------|
| `AWS_ACCESS_KEY_ID` | AWS IAM user access key | Run: `aws iam create-access-key --user-name transfer-worker-ci` |
| `AWS_SECRET_ACCESS_KEY` | AWS IAM user secret key | From the same command above |
| `AWS_ACCOUNT_ID` | Your 12-digit AWS account ID | Run: `aws sts get-caller-identity --query Account --output text` |
| `AWS_REGION` | AWS region (e.g., us-east-1) | Your preferred AWS region |
| `AWS_SOURCE_BUCKET` | S3 source bucket name | Your chosen bucket name (must be globally unique) |
| `AWS_DEST_BUCKET` | S3 destination bucket name | Your chosen bucket name (must be globally unique) |

### GCP Secrets

| Secret Name | Description | How to Get It |
|-------------|-------------|---------------|
| `GCP_SERVICE_ACCOUNT_KEY` | Complete JSON key for service account | See "Generate GCP Service Account Key" below |
| `GCP_PROJECT_ID` | Your GCP project ID | Run: `gcloud config get-value project` |
| `GCP_PROJECT_NUMBER` | Your GCP project number | Run: `gcloud projects describe $(gcloud config get-value project) --format="value(projectNumber)"` |
| `GCP_REGION` | GCP region (e.g., us-central1) | Your preferred GCP region |
| `GCS_SOURCE_BUCKET` | GCS source bucket name | Your chosen bucket name (must be globally unique) |
| `GCS_DEST_BUCKET` | GCS destination bucket name | Your chosen bucket name (must be globally unique) |

### Deployment Control Secrets

| Secret Name | Description | Recommended Value |
|-------------|-------------|-------------------|
| `DEPLOY_TO_AWS` | Enable AWS deployment | `true` or `false` |
| `DEPLOY_TO_GCP` | Enable GCP deployment | `true` or `false` |
| `DEPLOY_TERRAFORM` | Enable Terraform deployment | `false` (set `true` when ready) |

## 🔧 Quick Setup Commands

### AWS Setup

```bash
# Get AWS Account ID
aws sts get-caller-identity --query Account --output text

# Create IAM user
aws iam create-user --user-name transfer-worker-ci

# Create access key (save the output!)
aws iam create-access-key --user-name transfer-worker-ci

# Create S3 buckets (replace with your names)
aws s3api create-bucket --bucket my-transfer-source --region us-east-1
aws s3api create-bucket --bucket my-transfer-dest --region us-east-1
```

### GCP Setup

```bash
# Get project ID
gcloud config get-value project

# Get project number
gcloud projects describe $(gcloud config get-value project) --format="value(projectNumber)"

# Create service account
gcloud iam service-accounts create transfer-worker-ci \
  --display-name="Transfer Worker CI/CD"

# Generate service account key
gcloud iam service-accounts keys create key.json \
  --iam-account=transfer-worker-ci@$(gcloud config get-value project).iam.gserviceaccount.com

# Display key for copying to GitHub secret
cat key.json

# Create GCS buckets (replace with your names)
gsutil mb gs://my-gcs-source
gsutil mb gs://my-gcs-dest

# IMPORTANT: Delete the local key file after copying
rm key.json
```

## 🚀 Generate GCP Service Account Key

The GCP service account key is a JSON file. You need to copy the ENTIRE JSON content as the secret value.

### Step-by-step:

1. Generate the key:
```bash
PROJECT_ID=$(gcloud config get-value project)
gcloud iam service-accounts keys create /tmp/sa-key.json \
  --iam-account=transfer-worker-ci@${PROJECT_ID}.iam.gserviceaccount.com
```

2. Copy the entire JSON content:
```bash
cat /tmp/sa-key.json
```

3. In GitHub, create a new secret named `GCP_SERVICE_ACCOUNT_KEY` and paste the ENTIRE JSON content

4. Delete the local file:
```bash
rm /tmp/sa-key.json
```

## 🔄 Using GitHub CLI

If you have GitHub CLI installed, you can add secrets programmatically:

```bash
# First, set your repository
export GITHUB_REPO="owner/repo-name"

# AWS Secrets
echo "YOUR_ACCESS_KEY_ID" | gh secret set AWS_ACCESS_KEY_ID --repo $GITHUB_REPO
echo "YOUR_SECRET_ACCESS_KEY" | gh secret set AWS_SECRET_ACCESS_KEY --repo $GITHUB_REPO
echo "123456789012" | gh secret set AWS_ACCOUNT_ID --repo $GITHUB_REPO
echo "us-east-1" | gh secret set AWS_REGION --repo $GITHUB_REPO
echo "my-source-bucket" | gh secret set AWS_SOURCE_BUCKET --repo $GITHUB_REPO
echo "my-dest-bucket" | gh secret set AWS_DEST_BUCKET --repo $GITHUB_REPO

# GCP Secrets (use file for service account key)
cat key.json | gh secret set GCP_SERVICE_ACCOUNT_KEY --repo $GITHUB_REPO
echo "my-project-id" | gh secret set GCP_PROJECT_ID --repo $GITHUB_REPO
echo "123456789012" | gh secret set GCP_PROJECT_NUMBER --repo $GITHUB_REPO
echo "us-central1" | gh secret set GCP_REGION --repo $GITHUB_REPO
echo "my-gcs-source" | gh secret set GCS_SOURCE_BUCKET --repo $GITHUB_REPO
echo "my-gcs-dest" | gh secret set GCS_DEST_BUCKET --repo $GITHUB_REPO

# Deployment flags
echo "true" | gh secret set DEPLOY_TO_AWS --repo $GITHUB_REPO
echo "true" | gh secret set DEPLOY_TO_GCP --repo $GITHUB_REPO
echo "false" | gh secret set DEPLOY_TERRAFORM --repo $GITHUB_REPO
```

## 🛡️ Security Best Practices

1. **Never commit credentials** to your repository
2. **Rotate secrets regularly** (every 90 days)
3. **Use least privilege** - only grant necessary permissions
4. **Enable MFA** on your AWS and GCP accounts
5. **Monitor secret usage** in GitHub Actions logs
6. **Use separate accounts** for production and development

## 🧪 Testing Your Configuration

After adding all secrets, test your configuration:

1. Push to a feature branch to trigger the CI pipeline
2. Check the Actions tab in GitHub
3. Verify all jobs pass, especially the security and deployment jobs

## 🆘 Troubleshooting

### Common Issues

**"Invalid credentials"**
- Verify the secret values are correct
- Check that the IAM user/service account has necessary permissions

**"Bucket already exists"**
- S3 and GCS bucket names must be globally unique
- Choose different names for your buckets

**"Permission denied"**
- Ensure IAM policies are correctly attached
- Verify service account roles in GCP

### Verify Secrets Are Set

You can check which secrets are configured (but not their values):

```bash
gh secret list --repo owner/repo-name
```

## 📚 Additional Resources

- [GitHub Encrypted Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets)
- [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [GCP Service Accounts](https://cloud.google.com/iam/docs/service-accounts)
- [GitHub CLI Documentation](https://cli.github.com/manual/)