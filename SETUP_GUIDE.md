# Setup Guide - AWS & GCP Configuration with GitHub Secrets

This guide walks you through configuring your AWS and GCP accounts, setting up GitHub secrets, and deploying the Transfer Worker service.

## 📋 Prerequisites

- GitHub repository with Actions enabled
- AWS Account with appropriate permissions
- GCP Project with appropriate permissions
- `aws` CLI installed and configured locally
- `gcloud` CLI installed and configured locally

## 🔐 Step 1: Configure GitHub Secrets

Navigate to your GitHub repository → Settings → Secrets and variables → Actions

### Required Secrets

Add the following secrets to your repository:

#### AWS Secrets
| Secret Name | Description | Example Value |
|-------------|-------------|---------------|
| `AWS_ACCESS_KEY_ID` | AWS IAM user access key | `AKIA...` |
| `AWS_SECRET_ACCESS_KEY` | AWS IAM user secret key | `wJal...` |
| `AWS_ACCOUNT_ID` | Your AWS account ID | `123456789012` |
| `AWS_REGION` | AWS region for resources | `us-east-1` |
| `AWS_SOURCE_BUCKET` | S3 bucket for source files | `my-transfer-source` |
| `AWS_DEST_BUCKET` | S3 bucket for destination files | `my-transfer-dest` |

#### GCP Secrets
| Secret Name | Description | Example Value |
|-------------|-------------|---------------|
| `GCP_SERVICE_ACCOUNT_KEY` | GCP service account JSON key (entire JSON) | `{"type": "service_account"...}` |
| `GCP_PROJECT_ID` | Your GCP project ID | `my-project-123` |
| `GCP_PROJECT_NUMBER` | Your GCP project number | `123456789012` |
| `GCP_REGION` | GCP region for resources | `us-central1` |
| `GCS_SOURCE_BUCKET` | GCS bucket for source files | `my-gcs-source` |
| `GCS_DEST_BUCKET` | GCS bucket for destination files | `my-gcs-dest` |

#### Deployment Control Secrets
| Secret Name | Description | Example Value |
|-------------|-------------|---------------|
| `DEPLOY_TO_AWS` | Enable AWS deployment | `true` or `false` |
| `DEPLOY_TO_GCP` | Enable GCP deployment | `true` or `false` |
| `DEPLOY_TERRAFORM` | Enable Terraform deployment | `true` or `false` |

## 🔧 Step 2: AWS Setup

### 2.1 Create IAM User for CI/CD

```bash
# Create IAM user
aws iam create-user --user-name transfer-worker-ci

# Create access key
aws iam create-access-key --user-name transfer-worker-ci

# Save the AccessKeyId and SecretAccessKey as GitHub secrets
```

### 2.2 Create IAM Policy

Create file `aws-ci-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:CreateBucket",
        "s3:ListBucket",
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:GetBucketLocation",
        "s3:ListAllMyBuckets"
      ],
      "Resource": [
        "arn:aws:s3:::my-transfer-*",
        "arn:aws:s3:::my-transfer-*/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "sqs:CreateQueue",
        "sqs:DeleteQueue",
        "sqs:GetQueueAttributes",
        "sqs:SendMessage",
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:ListQueues"
      ],
      "Resource": "arn:aws:sqs:*:*:transfer-worker-*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:AttachRolePolicy",
        "iam:PutRolePolicy",
        "iam:GetRole",
        "iam:PassRole",
        "iam:ListRolePolicies"
      ],
      "Resource": "arn:aws:iam::*:role/transfer-worker-*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:CreateRepository"
      ],
      "Resource": "*"
    }
  ]
}
```

Attach the policy:

```bash
# Create and attach policy
aws iam put-user-policy \
  --user-name transfer-worker-ci \
  --policy-name TransferWorkerCIPolicy \
  --policy-document file://aws-ci-policy.json
```

### 2.3 Create S3 Buckets

```bash
# Create source bucket
aws s3api create-bucket \
  --bucket $AWS_SOURCE_BUCKET \
  --region $AWS_REGION

# Create destination bucket  
aws s3api create-bucket \
  --bucket $AWS_DEST_BUCKET \
  --region $AWS_REGION

# Enable versioning (optional but recommended)
aws s3api put-bucket-versioning \
  --bucket $AWS_SOURCE_BUCKET \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-versioning \
  --bucket $AWS_DEST_BUCKET \
  --versioning-configuration Status=Enabled
```

### 2.4 Create ECR Repository (for container deployment)

```bash
aws ecr create-repository \
  --repository-name transfer-worker \
  --region $AWS_REGION
```

## 🌐 Step 3: GCP Setup

### 3.1 Create Service Account

```bash
# Set your project
gcloud config set project $GCP_PROJECT_ID

# Create service account
gcloud iam service-accounts create transfer-worker-ci \
  --display-name="Transfer Worker CI/CD"

# Get the service account email
SA_EMAIL=transfer-worker-ci@${GCP_PROJECT_ID}.iam.gserviceaccount.com
```

### 3.2 Grant Permissions

```bash
# Grant necessary roles
gcloud projects add-iam-policy-binding ${GCP_PROJECT_ID} \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/storage.admin"

gcloud projects add-iam-policy-binding ${GCP_PROJECT_ID} \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/pubsub.admin"

gcloud projects add-iam-policy-binding ${GCP_PROJECT_ID} \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/iam.serviceAccountUser"

gcloud projects add-iam-policy-binding ${GCP_PROJECT_ID} \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/run.admin"

gcloud projects add-iam-policy-binding ${GCP_PROJECT_ID} \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/artifactregistry.writer"
```

### 3.3 Create Service Account Key

```bash
# Create and download key
gcloud iam service-accounts keys create key.json \
  --iam-account=${SA_EMAIL}

# Display the key (copy this entire JSON to GitHub secret GCP_SERVICE_ACCOUNT_KEY)
cat key.json

# IMPORTANT: Delete the local key file after copying
rm key.json
```

### 3.4 Create GCS Buckets

```bash
# Create source bucket
gsutil mb -p ${GCP_PROJECT_ID} -l ${GCP_REGION} gs://${GCS_SOURCE_BUCKET}

# Create destination bucket
gsutil mb -p ${GCP_PROJECT_ID} -l ${GCP_REGION} gs://${GCS_DEST_BUCKET}

# Enable versioning (optional but recommended)
gsutil versioning set on gs://${GCS_SOURCE_BUCKET}
gsutil versioning set on gs://${GCS_DEST_BUCKET}
```

### 3.5 Enable Required APIs

```bash
# Enable necessary APIs
gcloud services enable storage.googleapis.com
gcloud services enable pubsub.googleapis.com
gcloud services enable run.googleapis.com
gcloud services enable cloudbuild.googleapis.com
gcloud services enable artifactregistry.googleapis.com
```

## 🔄 Step 4: Configure Workload Identity Federation (Recommended)

For production, use Workload Identity Federation instead of long-lived keys.

### AWS → GCP Federation

```bash
# Create workload identity pool in GCP
gcloud iam workload-identity-pools create transfer-worker-pool \
  --location="global" \
  --display-name="Transfer Worker Pool"

# Create AWS provider
gcloud iam workload-identity-pools providers create-aws transfer-worker-aws \
  --location="global" \
  --workload-identity-pool="transfer-worker-pool" \
  --account-id="${AWS_ACCOUNT_ID}" \
  --attribute-mapping="google.subject=assertion.arn"
```

### GCP → AWS Federation

Create OIDC provider in AWS:

```bash
# Get GCP's OIDC issuer
ISSUER_URI="https://iam.googleapis.com/projects/${GCP_PROJECT_NUMBER}/locations/global/workloadIdentityPools/transfer-worker-pool/providers/transfer-worker-gcp"

# Create OIDC provider in AWS
aws iam create-open-id-connect-provider \
  --url ${ISSUER_URI} \
  --client-id-list "sts.amazonaws.com" \
  --thumbprint-list "1234567890abcdef"  # Use actual thumbprint
```

## 🚀 Step 5: Local Testing

### Set Environment Variables

Create `.env` file (DO NOT commit this file):

```bash
# AWS Configuration
export AWS_REGION=us-east-1
export AWS_SOURCE_BUCKET=my-transfer-source
export AWS_DEST_BUCKET=my-transfer-dest

# GCP Configuration
export GCP_PROJECT_ID=my-project-123
export GCP_REGION=us-central1
export GCS_SOURCE_BUCKET=my-gcs-source
export GCS_DEST_BUCKET=my-gcs-dest

# Load credentials from CLI tools
export AWS_PROFILE=default
export GOOGLE_APPLICATION_CREDENTIALS=~/.config/gcloud/application_default_credentials.json
```

### Run Tests

```bash
# Source environment variables
source .env

# Run unit tests
pytest test_transfer_worker.py -v

# Run integration test with real cloud resources
python test_integration.py
```

## 📦 Step 6: Deploy with GitHub Actions

### Trigger Deployment

Push to main branch to trigger deployment:

```bash
git add .
git commit -m "Deploy transfer worker"
git push origin main
```

### Monitor Deployment

1. Go to GitHub Actions tab
2. Watch the CI/CD Pipeline workflow
3. Check deployment logs for each job

## 🔍 Step 7: Verify Deployment

### AWS Verification

```bash
# Check S3 buckets
aws s3 ls s3://${AWS_SOURCE_BUCKET}/
aws s3 ls s3://${AWS_DEST_BUCKET}/

# Check SQS queue
aws sqs list-queues --queue-name-prefix transfer-worker

# Check ECS/Lambda deployment (if applicable)
aws ecs list-services --cluster transfer-worker
```

### GCP Verification

```bash
# Check GCS buckets
gsutil ls gs://${GCS_SOURCE_BUCKET}/
gsutil ls gs://${GCS_DEST_BUCKET}/

# Check Pub/Sub subscription
gcloud pubsub subscriptions list --filter="name:transfer-worker"

# Check Cloud Run deployment
gcloud run services list --platform managed
```

## 📊 Step 8: Monitor Operations

### CloudWatch (AWS)

```bash
# View logs
aws logs tail /aws/transfer-worker --follow

# View metrics
aws cloudwatch get-metric-statistics \
  --namespace TransferWorker \
  --metric-name TransferSuccess \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-02T00:00:00Z \
  --period 3600 \
  --statistics Sum
```

### Cloud Logging (GCP)

```bash
# View logs
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=transfer-worker" \
  --limit 50 \
  --format json

# View metrics
gcloud monitoring metrics list --filter="metric.type:transfer_worker"
```

## 🆘 Troubleshooting

### Common Issues

1. **Permission Denied**: Ensure IAM roles have correct permissions
2. **Bucket Not Found**: Verify bucket names match exactly (case-sensitive)
3. **Network Timeout**: Check VPC/firewall rules allow cross-cloud communication
4. **Authentication Failed**: Verify credentials are correctly set in GitHub secrets

### Debug Commands

```bash
# Test AWS credentials
aws sts get-caller-identity

# Test GCP credentials
gcloud auth list

# Test bucket access
aws s3 ls s3://${AWS_SOURCE_BUCKET}/ --debug
gsutil ls gs://${GCS_SOURCE_BUCKET}/ -D

# Test GitHub Actions locally
act -j test --secret-file .env
```

## 🔒 Security Best Practices

1. **Rotate Credentials Regularly**: Update GitHub secrets every 90 days
2. **Use Least Privilege**: Grant minimum necessary permissions
3. **Enable MFA**: For AWS and GCP console access
4. **Audit Logs**: Enable CloudTrail (AWS) and Audit Logs (GCP)
5. **Encrypt at Rest**: Enable bucket encryption
6. **Network Security**: Use VPC endpoints where possible
7. **Secret Scanning**: Enable GitHub secret scanning

## 📚 Additional Resources

- [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [GCP IAM Overview](https://cloud.google.com/iam/docs/overview)
- [GitHub Actions Security](https://docs.github.com/en/actions/security-guides)
- [Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation)