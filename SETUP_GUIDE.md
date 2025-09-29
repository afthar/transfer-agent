# Setup Guide

## Prerequisites

- GitHub repository with Actions enabled
- AWS Account
- GCP Project
- aws CLI installed
- gcloud CLI installed

## Step 1: GitHub Secrets

Go to: Repository Settings → Secrets and variables → Actions

### AWS Secrets

| Secret | Description | Example |
|--------|------------|---------|
| AWS_ACCESS_KEY_ID | IAM access key | AKIA... |
| AWS_SECRET_ACCESS_KEY | IAM secret key | wJal... |
| AWS_ACCOUNT_ID | Account ID | 123456789012 |
| AWS_REGION | Region | us-east-1 |
| AWS_SOURCE_BUCKET | Source bucket | my-source |
| AWS_DEST_BUCKET | Destination bucket | my-dest |

### GCP Secrets

| Secret | Description | Example |
|--------|------------|---------|
| GCP_SERVICE_ACCOUNT_KEY | Service account JSON | {"type": "service_account"...} |
| GCP_PROJECT_ID | Project ID | my-project-123 |
| GCP_PROJECT_NUMBER | Project number | 123456789012 |
| GCP_REGION | Region | us-central1 |
| GCS_SOURCE_BUCKET | Source bucket | my-gcs-source |
| GCS_DEST_BUCKET | Destination bucket | my-gcs-dest |

### Deployment Control

| Secret | Description | Value |
|--------|------------|-------|
| DEPLOY_TO_AWS | Enable AWS | true/false |
| DEPLOY_TO_GCP | Enable GCP | true/false |
| DEPLOY_TERRAFORM | Enable Terraform | true/false |

## Step 2: AWS Setup

### Create IAM User

```bash
aws iam create-user --user-name transfer-worker-ci
aws iam create-access-key --user-name transfer-worker-ci
```

### IAM Policy

Create `aws-ci-policy.json`:

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

Attach policy:

```bash
aws iam put-user-policy \
  --user-name transfer-worker-ci \
  --policy-name TransferWorkerCIPolicy \
  --policy-document file://aws-ci-policy.json
```

### Create S3 Buckets

```bash
aws s3api create-bucket --bucket $AWS_SOURCE_BUCKET --region $AWS_REGION
aws s3api create-bucket --bucket $AWS_DEST_BUCKET --region $AWS_REGION

aws s3api put-bucket-versioning \
  --bucket $AWS_SOURCE_BUCKET \
  --versioning-configuration Status=Enabled
```

### Create ECR Repository

```bash
aws ecr create-repository --repository-name transfer-worker --region $AWS_REGION
```

## Step 3: GCP Setup

### Create Service Account

```bash
gcloud config set project $GCP_PROJECT_ID

gcloud iam service-accounts create transfer-worker-ci \
  --display-name="Transfer Worker CI/CD"

SA_EMAIL=transfer-worker-ci@${GCP_PROJECT_ID}.iam.gserviceaccount.com
```

### Grant Permissions

```bash
for role in storage.admin pubsub.admin iam.serviceAccountUser run.admin artifactregistry.writer; do
  gcloud projects add-iam-policy-binding ${GCP_PROJECT_ID} \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/${role}"
done
```

### Create Service Account Key

```bash
gcloud iam service-accounts keys create key.json \
  --iam-account=${SA_EMAIL}

cat key.json  # Copy to GitHub secret
rm key.json
```

### Create GCS Buckets

```bash
gsutil mb -p ${GCP_PROJECT_ID} -l ${GCP_REGION} gs://${GCS_SOURCE_BUCKET}
gsutil mb -p ${GCP_PROJECT_ID} -l ${GCP_REGION} gs://${GCS_DEST_BUCKET}

gsutil versioning set on gs://${GCS_SOURCE_BUCKET}
gsutil versioning set on gs://${GCS_DEST_BUCKET}
```

### Enable APIs

```bash
gcloud services enable storage.googleapis.com \
  pubsub.googleapis.com \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com
```

## Step 4: Workload Identity Federation

### AWS to GCP

```bash
gcloud iam workload-identity-pools create transfer-worker-pool \
  --location="global" \
  --display-name="Transfer Worker Pool"

gcloud iam workload-identity-pools providers create-aws transfer-worker-aws \
  --location="global" \
  --workload-identity-pool="transfer-worker-pool" \
  --account-id="${AWS_ACCOUNT_ID}" \
  --attribute-mapping="google.subject=assertion.arn"
```

### GCP to AWS

```bash
ISSUER_URI="https://iam.googleapis.com/projects/${GCP_PROJECT_NUMBER}/locations/global/workloadIdentityPools/transfer-worker-pool/providers/transfer-worker-gcp"

aws iam create-open-id-connect-provider \
  --url ${ISSUER_URI} \
  --client-id-list "sts.amazonaws.com" \
  --thumbprint-list "1234567890abcdef"
```

## Step 5: Local Testing

Create `.env`:

```bash
export AWS_REGION=us-east-1
export AWS_SOURCE_BUCKET=my-transfer-source
export AWS_DEST_BUCKET=my-transfer-dest
export GCP_PROJECT_ID=my-project-123
export GCP_REGION=us-central1
export GCS_SOURCE_BUCKET=my-gcs-source
export GCS_DEST_BUCKET=my-gcs-dest
export AWS_PROFILE=default
export GOOGLE_APPLICATION_CREDENTIALS=~/.config/gcloud/application_default_credentials.json
```

Run tests:

```bash
source .env
pytest test_transfer_worker.py -v
```

## Step 6: Deploy

```bash
git add .
git commit -m "Deploy transfer worker"
git push origin main
```

Check GitHub Actions tab for deployment status.

## Step 7: Verify

AWS:
```bash
aws s3 ls s3://${AWS_SOURCE_BUCKET}/
aws sqs list-queues --queue-name-prefix transfer-worker
aws ecs list-services --cluster transfer-worker
```

GCP:
```bash
gsutil ls gs://${GCS_SOURCE_BUCKET}/
gcloud pubsub subscriptions list --filter="name:transfer-worker"
gcloud run services list --platform managed
```

## Monitoring

AWS:
```bash
aws logs tail /aws/transfer-worker --follow
```

GCP:
```bash
gcloud logging read "resource.type=cloud_run_revision" --limit 50
```

## Troubleshooting

Common issues:
- Permission denied: Check IAM roles
- Bucket not found: Verify names (case-sensitive)
- Network timeout: Check VPC/firewall rules
- Authentication failed: Verify GitHub secrets

Debug:
```bash
aws sts get-caller-identity
gcloud auth list
```

## Security

- Rotate credentials every 90 days
- Use least privilege permissions
- Enable MFA
- Enable audit logging
- Encrypt buckets
- Use VPC endpoints
- Enable secret scanning