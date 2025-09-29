# Variables for Transfer Worker Terraform deployment

# Environment configuration
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^(dev|staging|prod)$", var.environment))
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "owner_email" {
  description = "Email of the service owner for tagging"
  type        = string
  default     = "transfer-worker-team@example.com"
}

variable "cost_center" {
  description = "Cost center for billing"
  type        = string
  default     = "engineering"
}

# AWS Configuration
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "aws_account_id" {
  description = "AWS account ID for cross-cloud federation"
  type        = string
  default     = ""
}

variable "aws_source_bucket" {
  description = "AWS S3 source bucket name"
  type        = string
  default     = "transfer-worker-source"
}

variable "aws_dest_bucket" {
  description = "AWS S3 destination bucket name"
  type        = string
  default     = "transfer-worker-dest"
}

variable "enable_aws_queue" {
  description = "Enable AWS SQS queue"
  type        = bool
  default     = true
}

# GCP Configuration
variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
  default     = ""
}

variable "gcp_project_number" {
  description = "GCP project number for workload identity"
  type        = string
  default     = ""
}

variable "gcp_region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "gcs_source_bucket" {
  description = "GCS source bucket name"
  type        = string
  default     = "transfer-worker-source"
}

variable "gcs_dest_bucket" {
  description = "GCS destination bucket name"
  type        = string
  default     = "transfer-worker-dest"
}

variable "enable_gcp_queue" {
  description = "Enable GCP Pub/Sub"
  type        = bool
  default     = true
}

# Kubernetes Configuration
variable "deploy_to_kubernetes" {
  description = "Deploy worker to Kubernetes"
  type        = bool
  default     = false
}

variable "kubernetes_provider" {
  description = "Kubernetes cluster provider (eks, gke, aks)"
  type        = string
  default     = "gke"
  
  validation {
    condition     = can(regex("^(eks|gke|aks)$", var.kubernetes_provider))
    error_message = "Kubernetes provider must be eks, gke, or aks."
  }
}

variable "kubernetes_node_count" {
  description = "Number of nodes in Kubernetes cluster"
  type        = number
  default     = 3
  
  validation {
    condition     = var.kubernetes_node_count >= 1 && var.kubernetes_node_count <= 10
    error_message = "Node count must be between 1 and 10."
  }
}

variable "kubernetes_node_type" {
  description = "Instance type for Kubernetes nodes (t3.medium for EKS, e2-medium for GKE)"
  type        = string
  default     = "e2-medium"
}

variable "worker_replicas" {
  description = "Number of worker replicas"
  type        = number
  default     = 3
  
  validation {
    condition     = var.worker_replicas >= 1
    error_message = "Worker replicas must be at least 1."
  }
}

# Container Configuration
variable "container_registry" {
  description = "Container registry URL"
  type        = string
  default     = "ghcr.io/transfer-worker"
}

variable "container_image_tag" {
  description = "Container image tag"
  type        = string
  default     = "latest"
}

# Monitoring Configuration
variable "enable_monitoring" {
  description = "Enable monitoring stack"
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Email for alerts"
  type        = string
  default     = "alerts@example.com"
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for notifications"
  type        = string
  default     = ""
  sensitive   = true
}

# Network Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "enable_private_endpoints" {
  description = "Enable private endpoints for cloud services"
  type        = bool
  default     = true
}

# Security Configuration
variable "enable_encryption" {
  description = "Enable encryption for all resources"
  type        = bool
  default     = true
}

variable "kms_key_rotation" {
  description = "Enable automatic KMS key rotation"
  type        = bool
  default     = true
}

variable "enable_audit_logging" {
  description = "Enable audit logging"
  type        = bool
  default     = true
}

# Performance Configuration
variable "max_concurrent_transfers" {
  description = "Maximum concurrent transfers per worker"
  type        = number
  default     = 10
  
  validation {
    condition     = var.max_concurrent_transfers >= 1 && var.max_concurrent_transfers <= 100
    error_message = "Max concurrent transfers must be between 1 and 100."
  }
}

variable "transfer_timeout_seconds" {
  description = "Timeout for individual transfers in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.transfer_timeout_seconds >= 60
    error_message = "Transfer timeout must be at least 60 seconds."
  }
}

# Auto-scaling Configuration
variable "enable_autoscaling" {
  description = "Enable auto-scaling for workers"
  type        = bool
  default     = true
}

variable "min_workers" {
  description = "Minimum number of workers"
  type        = number
  default     = 1
}

variable "max_workers" {
  description = "Maximum number of workers"
  type        = number
  default     = 10
}

variable "target_cpu_utilization" {
  description = "Target CPU utilization for auto-scaling (%)"
  type        = number
  default     = 70
  
  validation {
    condition     = var.target_cpu_utilization > 0 && var.target_cpu_utilization <= 100
    error_message = "CPU utilization must be between 1 and 100."
  }
}