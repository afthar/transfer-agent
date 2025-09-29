# Main Terraform configuration for Transfer Worker deployment
# This is a stub showing the infrastructure pattern for cross-cloud deployment

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
  
  backend "s3" {
    bucket = "terraform-state-transfer-worker"
    key    = "transfer-worker/terraform.tfstate"
    region = "us-east-1"
    encrypt = true
    dynamodb_table = "terraform-state-lock"
  }
}

# Provider configurations
provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = local.common_tags
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

provider "kubernetes" {
  host                   = module.kubernetes_cluster.endpoint
  cluster_ca_certificate = base64decode(module.kubernetes_cluster.ca_certificate)
  token                  = module.kubernetes_cluster.token
}

# Local variables
locals {
  common_tags = {
    Environment = var.environment
    Service     = "transfer-worker"
    ManagedBy   = "terraform"
    Owner       = var.owner_email
    CostCenter  = var.cost_center
  }
  
  service_name = "transfer-worker-${var.environment}"
}

# AWS Resources
module "aws_resources" {
  source = "./modules/aws"
  
  environment    = var.environment
  service_name   = local.service_name
  aws_region     = var.aws_region
  common_tags    = local.common_tags
  
  # S3 buckets for storage
  source_bucket_name = var.aws_source_bucket
  dest_bucket_name   = var.aws_dest_bucket
  
  # SQS queue for events
  enable_sqs_queue = var.enable_aws_queue
  queue_name       = "${local.service_name}-queue"
  dlq_name        = "${local.service_name}-dlq"
  
  # IAM for workload identity
  gcp_project_number = var.gcp_project_number
}

# GCP Resources
module "gcp_resources" {
  source = "./modules/gcp"
  
  environment     = var.environment
  service_name    = local.service_name
  gcp_project_id  = var.gcp_project_id
  gcp_region      = var.gcp_region
  
  # GCS buckets for storage
  source_bucket_name = var.gcs_source_bucket
  dest_bucket_name   = var.gcs_dest_bucket
  
  # PubSub for events
  enable_pubsub = var.enable_gcp_queue
  topic_name    = "${local.service_name}-topic"
  subscription_name = "${local.service_name}-subscription"
  
  # Workload identity federation
  aws_account_id  = var.aws_account_id
}

# Kubernetes deployment (optional)
module "kubernetes_cluster" {
  source = "./modules/kubernetes"
  count  = var.deploy_to_kubernetes ? 1 : 0
  
  environment  = var.environment
  service_name = local.service_name
  
  # Choose cluster provider
  cluster_provider = var.kubernetes_provider # "eks", "gke", or "aks"
  
  # Cluster configuration
  cluster_name     = "${local.service_name}-cluster"
  node_count       = var.kubernetes_node_count
  node_type        = var.kubernetes_node_type
  
  # Workload configuration
  container_image  = "${var.container_registry}/${local.service_name}:${var.container_image_tag}"
  replicas        = var.worker_replicas
  
  # Service account for workload identity
  service_account_annotations = {
    "eks.amazonaws.com/role-arn" = module.aws_resources.worker_role_arn
    "iam.gke.io/gcp-service-account" = module.gcp_resources.worker_service_account_email
  }
}

# Monitoring and alerting
module "monitoring" {
  source = "./modules/monitoring"
  
  environment  = var.environment
  service_name = local.service_name
  
  # Prometheus/Grafana configuration
  enable_prometheus = var.enable_monitoring
  prometheus_namespace = "monitoring"
  
  # Alert configurations
  alert_email = var.alert_email
  slack_webhook_url = var.slack_webhook_url
  
  # SLO thresholds
  slo_success_rate_threshold = 99.5
  slo_latency_p99_threshold  = 60
}

# Outputs
output "aws_worker_role_arn" {
  description = "ARN of the AWS IAM role for the worker"
  value       = module.aws_resources.worker_role_arn
}

output "gcp_service_account_email" {
  description = "Email of the GCP service account for the worker"
  value       = module.gcp_resources.worker_service_account_email
}

output "queue_endpoints" {
  description = "Queue endpoints for event processing"
  value = {
    aws_sqs_url = var.enable_aws_queue ? module.aws_resources.queue_url : null
    gcp_pubsub_subscription = var.enable_gcp_queue ? module.gcp_resources.subscription_path : null
  }
  sensitive = true
}

output "deployment_info" {
  description = "Deployment information"
  value = {
    environment = var.environment
    service_name = local.service_name
    kubernetes_deployed = var.deploy_to_kubernetes
    monitoring_enabled = var.enable_monitoring
  }
}