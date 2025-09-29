# GitHub Secrets Configuration

## Adding Secrets

1. Go to repository Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Add each secret below

## Required Secrets

### AWS

| Secret | Description | Command to Get Value |
|--------|-------------|---------------------|
| AWS_ACCESS_KEY_ID | IAM access key | `aws iam create-access-key --user-name transfer-worker-ci` |
| AWS_SECRET_ACCESS_KEY | IAM secret key | Same as above |
| AWS_ACCOUNT_ID | Account ID | `aws sts get-caller-identity --query Account --output text` |
| AWS_REGION | Region | Your choice (e.g., us-east-1) |
| AWS_SOURCE_BUCKET | Source bucket | Your bucket name |
| AWS_DEST_BUCKET | Destination bucket | Your bucket name |

### GCP

| Secret | Description | Command to Get Value |
|--------|-------------|---------------------|
| GCP_SERVICE_ACCOUNT_KEY | Service account JSON | See below |
| GCP_PROJECT_ID | Project ID | `gcloud config get-value project` |
| GCP_PROJECT_NUMBER | Project number | `gcloud projects describe $(gcloud config get-value project) --format="value(projectNumber)"` |
| GCP_REGION | Region | Your choice (e.g., us-central1) |
| GCS_SOURCE_BUCKET | Source bucket | Your bucket name |
| GCS_DEST_BUCKET | Destination bucket | Your bucket name |

### Deployment

| Secret | Value |
|--------|-------|
| DEPLOY_TO_AWS | true or false |
| DEPLOY_TO_GCP | true or false |
| DEPLOY_TERRAFORM | true or false |

## Setup Commands

### AWS

```bash
# Get account ID
aws sts get-caller-identity --query Account --output text

# Create IAM user
aws iam create-user --user-name transfer-worker-ci

# Create access key
aws iam create-access-key --user-name transfer-worker-ci

# Create buckets
aws s3api create-bucket --bucket my-transfer-source --region us-east-1
aws s3api create-bucket --bucket my-transfer-dest --region us-east-1
```

### GCP

```bash
# Get project info
gcloud config get-value project
gcloud projects describe $(gcloud config get-value project) --format="value(projectNumber)"

# Create service account
gcloud iam service-accounts create transfer-worker-ci

# Generate key
gcloud iam service-accounts keys create key.json \
  --iam-account=transfer-worker-ci@$(gcloud config get-value project).iam.gserviceaccount.com

# Display key for copying
cat key.json

# Delete local key after copying
rm key.json

# Create buckets
gsutil mb gs://my-gcs-source
gsutil mb gs://my-gcs-dest
```

## Getting GCP Service Account Key

1. Generate key:
```bash
PROJECT_ID=$(gcloud config get-value project)
gcloud iam service-accounts keys create /tmp/sa-key.json \
  --iam-account=transfer-worker-ci@${PROJECT_ID}.iam.gserviceaccount.com
```

2. Copy entire JSON:
```bash
cat /tmp/sa-key.json
```

3. Create GitHub secret `GCP_SERVICE_ACCOUNT_KEY` with the JSON content

4. Delete local file:
```bash
rm /tmp/sa-key.json
```

## GitHub CLI Method

```bash
export GITHUB_REPO="owner/repo-name"

# AWS
echo "YOUR_ACCESS_KEY_ID" | gh secret set AWS_ACCESS_KEY_ID --repo $GITHUB_REPO
echo "YOUR_SECRET_ACCESS_KEY" | gh secret set AWS_SECRET_ACCESS_KEY --repo $GITHUB_REPO
echo "123456789012" | gh secret set AWS_ACCOUNT_ID --repo $GITHUB_REPO
echo "us-east-1" | gh secret set AWS_REGION --repo $GITHUB_REPO
echo "my-source-bucket" | gh secret set AWS_SOURCE_BUCKET --repo $GITHUB_REPO
echo "my-dest-bucket" | gh secret set AWS_DEST_BUCKET --repo $GITHUB_REPO

# GCP
cat key.json | gh secret set GCP_SERVICE_ACCOUNT_KEY --repo $GITHUB_REPO
echo "my-project-id" | gh secret set GCP_PROJECT_ID --repo $GITHUB_REPO
echo "123456789012" | gh secret set GCP_PROJECT_NUMBER --repo $GITHUB_REPO
echo "us-central1" | gh secret set GCP_REGION --repo $GITHUB_REPO
echo "my-gcs-source" | gh secret set GCS_SOURCE_BUCKET --repo $GITHUB_REPO
echo "my-gcs-dest" | gh secret set GCS_DEST_BUCKET --repo $GITHUB_REPO

# Deployment
echo "true" | gh secret set DEPLOY_TO_AWS --repo $GITHUB_REPO
echo "true" | gh secret set DEPLOY_TO_GCP --repo $GITHUB_REPO
echo "false" | gh secret set DEPLOY_TERRAFORM --repo $GITHUB_REPO
```

## Testing

Push to feature branch and check Actions tab.

## Troubleshooting

- Invalid credentials: Verify secret values and IAM permissions
- Bucket exists: Bucket names must be globally unique
- Permission denied: Check IAM policies and service account roles

Verify secrets are set:
```bash
gh secret list --repo owner/repo-name
```

## References

- [GitHub Encrypted Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets)
- [AWS IAM](https://docs.aws.amazon.com/IAM/latest/UserGuide/)
- [GCP Service Accounts](https://cloud.google.com/iam/docs/service-accounts)