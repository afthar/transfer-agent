#!/bin/bash

# Cloud Setup Script for Transfer Worker
# This script helps configure AWS and GCP resources for the Transfer Worker service

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI not found. Please install it first."
        echo "Visit: https://aws.amazon.com/cli/"
        exit 1
    fi
    
    # Check gcloud CLI
    if ! command -v gcloud &> /dev/null; then
        print_error "gcloud CLI not found. Please install it first."
        echo "Visit: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check GitHub CLI (optional but helpful)
    if ! command -v gh &> /dev/null; then
        print_warn "GitHub CLI not found. You'll need to add secrets manually."
        echo "Visit: https://cli.github.com/"
    fi
    
    print_info "Prerequisites check completed."
}

# Get configuration from user
get_configuration() {
    print_info "Please provide configuration details..."
    
    # AWS Configuration
    read -p "AWS Account ID: " AWS_ACCOUNT_ID
    read -p "AWS Region (default: us-east-1): " AWS_REGION
    AWS_REGION=${AWS_REGION:-us-east-1}
    read -p "AWS Source Bucket Name: " AWS_SOURCE_BUCKET
    read -p "AWS Destination Bucket Name: " AWS_DEST_BUCKET
    
    # GCP Configuration
    read -p "GCP Project ID: " GCP_PROJECT_ID
    read -p "GCP Region (default: us-central1): " GCP_REGION
    GCP_REGION=${GCP_REGION:-us-central1}
    read -p "GCS Source Bucket Name: " GCS_SOURCE_BUCKET
    read -p "GCS Destination Bucket Name: " GCS_DEST_BUCKET
    
    # GitHub Configuration
    read -p "GitHub Repository (owner/repo): " GITHUB_REPO
    
    # Save to .env file
    cat > .env.cloud <<EOF
# AWS Configuration
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
export AWS_REGION="${AWS_REGION}"
export AWS_SOURCE_BUCKET="${AWS_SOURCE_BUCKET}"
export AWS_DEST_BUCKET="${AWS_DEST_BUCKET}"

# GCP Configuration
export GCP_PROJECT_ID="${GCP_PROJECT_ID}"
export GCP_REGION="${GCP_REGION}"
export GCS_SOURCE_BUCKET="${GCS_SOURCE_BUCKET}"
export GCS_DEST_BUCKET="${GCS_DEST_BUCKET}"

# GitHub Configuration
export GITHUB_REPO="${GITHUB_REPO}"
EOF
    
    print_info "Configuration saved to .env.cloud"
    source .env.cloud
}

# Setup AWS resources
setup_aws() {
    print_info "Setting up AWS resources..."
    
    # Create IAM user for CI/CD
    print_info "Creating IAM user..."
    aws iam create-user --user-name transfer-worker-ci 2>/dev/null || print_warn "User already exists"
    
    # Create and attach policy
    print_info "Creating IAM policy..."
    cat > /tmp/aws-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:*"
      ],
      "Resource": [
        "arn:aws:s3:::${AWS_SOURCE_BUCKET}",
        "arn:aws:s3:::${AWS_SOURCE_BUCKET}/*",
        "arn:aws:s3:::${AWS_DEST_BUCKET}",
        "arn:aws:s3:::${AWS_DEST_BUCKET}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "sqs:*"
      ],
      "Resource": "arn:aws:sqs:${AWS_REGION}:${AWS_ACCOUNT_ID}:transfer-worker-*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:AttachRolePolicy",
        "iam:PutRolePolicy",
        "iam:GetRole",
        "iam:PassRole"
      ],
      "Resource": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/transfer-worker-*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecr:*"
      ],
      "Resource": "*"
    }
  ]
}
EOF
    
    aws iam put-user-policy \
        --user-name transfer-worker-ci \
        --policy-name TransferWorkerPolicy \
        --policy-document file:///tmp/aws-policy.json 2>/dev/null || print_warn "Policy already exists"
    
    # Create access key
    print_info "Creating access key..."
    AWS_CREDENTIALS=$(aws iam create-access-key --user-name transfer-worker-ci --output json 2>/dev/null || echo "{}")
    
    if [ ! -z "$AWS_CREDENTIALS" ] && [ "$AWS_CREDENTIALS" != "{}" ]; then
        AWS_ACCESS_KEY_ID=$(echo $AWS_CREDENTIALS | jq -r '.AccessKey.AccessKeyId')
        AWS_SECRET_ACCESS_KEY=$(echo $AWS_CREDENTIALS | jq -r '.AccessKey.SecretAccessKey')
        
        # Save credentials
        cat >> .env.secrets <<EOF

# AWS Credentials (SENSITIVE - DO NOT COMMIT)
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}"
EOF
        print_info "AWS credentials saved to .env.secrets"
    else
        print_warn "Access key already exists or creation failed"
    fi
    
    # Create S3 buckets
    print_info "Creating S3 buckets..."
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3api create-bucket --bucket ${AWS_SOURCE_BUCKET} 2>/dev/null || print_warn "Source bucket already exists"
        aws s3api create-bucket --bucket ${AWS_DEST_BUCKET} 2>/dev/null || print_warn "Dest bucket already exists"
    else
        aws s3api create-bucket \
            --bucket ${AWS_SOURCE_BUCKET} \
            --region ${AWS_REGION} \
            --create-bucket-configuration LocationConstraint=${AWS_REGION} 2>/dev/null || print_warn "Source bucket already exists"
        aws s3api create-bucket \
            --bucket ${AWS_DEST_BUCKET} \
            --region ${AWS_REGION} \
            --create-bucket-configuration LocationConstraint=${AWS_REGION} 2>/dev/null || print_warn "Dest bucket already exists"
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket ${AWS_SOURCE_BUCKET} \
        --versioning-configuration Status=Enabled
    aws s3api put-bucket-versioning \
        --bucket ${AWS_DEST_BUCKET} \
        --versioning-configuration Status=Enabled
    
    # Create ECR repository
    print_info "Creating ECR repository..."
    aws ecr create-repository \
        --repository-name transfer-worker \
        --region ${AWS_REGION} 2>/dev/null || print_warn "ECR repository already exists"
    
    print_info "AWS setup completed!"
}

# Setup GCP resources
setup_gcp() {
    print_info "Setting up GCP resources..."
    
    # Set project
    gcloud config set project ${GCP_PROJECT_ID}
    
    # Get project number
    GCP_PROJECT_NUMBER=$(gcloud projects describe ${GCP_PROJECT_ID} --format="value(projectNumber)")
    echo "export GCP_PROJECT_NUMBER=${GCP_PROJECT_NUMBER}" >> .env.cloud
    
    # Enable APIs
    print_info "Enabling GCP APIs..."
    gcloud services enable storage.googleapis.com
    gcloud services enable pubsub.googleapis.com
    gcloud services enable run.googleapis.com
    gcloud services enable cloudbuild.googleapis.com
    gcloud services enable artifactregistry.googleapis.com
    gcloud services enable iam.googleapis.com
    
    # Create service account
    print_info "Creating service account..."
    SA_EMAIL=transfer-worker-ci@${GCP_PROJECT_ID}.iam.gserviceaccount.com
    gcloud iam service-accounts create transfer-worker-ci \
        --display-name="Transfer Worker CI/CD" 2>/dev/null || print_warn "Service account already exists"
    
    # Grant permissions
    print_info "Granting permissions..."
    ROLES=(
        "roles/storage.admin"
        "roles/pubsub.admin"
        "roles/iam.serviceAccountUser"
        "roles/run.admin"
        "roles/artifactregistry.writer"
    )
    
    for role in "${ROLES[@]}"; do
        gcloud projects add-iam-policy-binding ${GCP_PROJECT_ID} \
            --member="serviceAccount:${SA_EMAIL}" \
            --role="${role}" \
            --quiet 2>/dev/null || print_warn "Role ${role} already bound"
    done
    
    # Create service account key
    print_info "Creating service account key..."
    gcloud iam service-accounts keys create /tmp/gcp-key.json \
        --iam-account=${SA_EMAIL} 2>/dev/null
    
    if [ -f /tmp/gcp-key.json ]; then
        GCP_SA_KEY=$(cat /tmp/gcp-key.json | base64 -w 0)
        
        # Save key
        cat >> .env.secrets <<EOF

# GCP Service Account Key (SENSITIVE - DO NOT COMMIT)
export GCP_SERVICE_ACCOUNT_KEY='$(cat /tmp/gcp-key.json)'
EOF
        rm /tmp/gcp-key.json
        print_info "GCP service account key saved to .env.secrets"
    else
        print_warn "Service account key creation failed"
    fi
    
    # Create GCS buckets
    print_info "Creating GCS buckets..."
    gsutil mb -p ${GCP_PROJECT_ID} -l ${GCP_REGION} gs://${GCS_SOURCE_BUCKET} 2>/dev/null || print_warn "Source bucket already exists"
    gsutil mb -p ${GCP_PROJECT_ID} -l ${GCP_REGION} gs://${GCS_DEST_BUCKET} 2>/dev/null || print_warn "Dest bucket already exists"
    
    # Enable versioning
    gsutil versioning set on gs://${GCS_SOURCE_BUCKET}
    gsutil versioning set on gs://${GCS_DEST_BUCKET}
    
    print_info "GCP setup completed!"
}

# Setup GitHub secrets
setup_github_secrets() {
    print_info "Setting up GitHub secrets..."
    
    if ! command -v gh &> /dev/null; then
        print_error "GitHub CLI not found. Please add the following secrets manually:"
        print_info "Visit: https://github.com/${GITHUB_REPO}/settings/secrets/actions"
        
        # Load secrets
        source .env.cloud
        source .env.secrets
        
        echo ""
        echo "Add these secrets to GitHub:"
        echo "------------------------"
        echo "AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID}"
        echo "AWS_SECRET_ACCESS_KEY: [hidden]"
        echo "AWS_ACCOUNT_ID: ${AWS_ACCOUNT_ID}"
        echo "AWS_REGION: ${AWS_REGION}"
        echo "AWS_SOURCE_BUCKET: ${AWS_SOURCE_BUCKET}"
        echo "AWS_DEST_BUCKET: ${AWS_DEST_BUCKET}"
        echo ""
        echo "GCP_SERVICE_ACCOUNT_KEY: [hidden - use content from .env.secrets]"
        echo "GCP_PROJECT_ID: ${GCP_PROJECT_ID}"
        echo "GCP_PROJECT_NUMBER: ${GCP_PROJECT_NUMBER}"
        echo "GCP_REGION: ${GCP_REGION}"
        echo "GCS_SOURCE_BUCKET: ${GCS_SOURCE_BUCKET}"
        echo "GCS_DEST_BUCKET: ${GCS_DEST_BUCKET}"
        echo ""
        echo "DEPLOY_TO_AWS: true"
        echo "DEPLOY_TO_GCP: true"
        echo "DEPLOY_TERRAFORM: false"
        return
    fi
    
    # Use GitHub CLI to set secrets
    print_info "Using GitHub CLI to set secrets..."
    
    # Load configuration
    source .env.cloud
    source .env.secrets
    
    # Set AWS secrets
    echo ${AWS_ACCESS_KEY_ID} | gh secret set AWS_ACCESS_KEY_ID --repo ${GITHUB_REPO}
    echo ${AWS_SECRET_ACCESS_KEY} | gh secret set AWS_SECRET_ACCESS_KEY --repo ${GITHUB_REPO}
    echo ${AWS_ACCOUNT_ID} | gh secret set AWS_ACCOUNT_ID --repo ${GITHUB_REPO}
    echo ${AWS_REGION} | gh secret set AWS_REGION --repo ${GITHUB_REPO}
    echo ${AWS_SOURCE_BUCKET} | gh secret set AWS_SOURCE_BUCKET --repo ${GITHUB_REPO}
    echo ${AWS_DEST_BUCKET} | gh secret set AWS_DEST_BUCKET --repo ${GITHUB_REPO}
    
    # Set GCP secrets
    echo "${GCP_SERVICE_ACCOUNT_KEY}" | gh secret set GCP_SERVICE_ACCOUNT_KEY --repo ${GITHUB_REPO}
    echo ${GCP_PROJECT_ID} | gh secret set GCP_PROJECT_ID --repo ${GITHUB_REPO}
    echo ${GCP_PROJECT_NUMBER} | gh secret set GCP_PROJECT_NUMBER --repo ${GITHUB_REPO}
    echo ${GCP_REGION} | gh secret set GCP_REGION --repo ${GITHUB_REPO}
    echo ${GCS_SOURCE_BUCKET} | gh secret set GCS_SOURCE_BUCKET --repo ${GITHUB_REPO}
    echo ${GCS_DEST_BUCKET} | gh secret set GCS_DEST_BUCKET --repo ${GITHUB_REPO}
    
    # Set deployment flags
    echo "true" | gh secret set DEPLOY_TO_AWS --repo ${GITHUB_REPO}
    echo "true" | gh secret set DEPLOY_TO_GCP --repo ${GITHUB_REPO}
    echo "false" | gh secret set DEPLOY_TERRAFORM --repo ${GITHUB_REPO}
    
    print_info "GitHub secrets configured!"
}

# Verify setup
verify_setup() {
    print_info "Verifying setup..."
    
    # Test AWS
    print_info "Testing AWS access..."
    aws sts get-caller-identity || print_error "AWS authentication failed"
    aws s3 ls s3://${AWS_SOURCE_BUCKET}/ || print_warn "Cannot list source bucket"
    aws s3 ls s3://${AWS_DEST_BUCKET}/ || print_warn "Cannot list dest bucket"
    
    # Test GCP
    print_info "Testing GCP access..."
    gcloud auth list
    gsutil ls gs://${GCS_SOURCE_BUCKET}/ || print_warn "Cannot list source bucket"
    gsutil ls gs://${GCS_DEST_BUCKET}/ || print_warn "Cannot list dest bucket"
    
    print_info "Verification completed!"
}

# Main execution
main() {
    print_info "Transfer Worker Cloud Setup Script"
    echo "=================================="
    echo ""
    
    check_prerequisites
    
    # Check if configuration exists
    if [ -f .env.cloud ]; then
        print_info "Found existing configuration in .env.cloud"
        read -p "Use existing configuration? (y/n): " USE_EXISTING
        if [ "$USE_EXISTING" = "y" ]; then
            source .env.cloud
        else
            get_configuration
        fi
    else
        get_configuration
    fi
    
    # Setup cloud resources
    read -p "Setup AWS resources? (y/n): " SETUP_AWS
    if [ "$SETUP_AWS" = "y" ]; then
        setup_aws
    fi
    
    read -p "Setup GCP resources? (y/n): " SETUP_GCP
    if [ "$SETUP_GCP" = "y" ]; then
        setup_gcp
    fi
    
    read -p "Configure GitHub secrets? (y/n): " SETUP_GITHUB
    if [ "$SETUP_GITHUB" = "y" ]; then
        setup_github_secrets
    fi
    
    # Verify setup
    read -p "Verify setup? (y/n): " VERIFY
    if [ "$VERIFY" = "y" ]; then
        verify_setup
    fi
    
    print_info "Setup complete!"
    print_warn "Remember to:"
    print_warn "1. Keep .env.secrets file secure and NEVER commit it"
    print_warn "2. Add .env* to .gitignore"
    print_warn "3. Test the deployment with: git push origin main"
}

# Run main function
main "$@"