# Variables for AWS Module

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "service_name" {
  description = "Name of the service"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
}

variable "source_bucket_name" {
  description = "Name for the source S3 bucket"
  type        = string
}

variable "dest_bucket_name" {
  description = "Name for the destination S3 bucket"
  type        = string
}

variable "enable_sqs_queue" {
  description = "Whether to create SQS queue"
  type        = bool
  default     = true
}

variable "queue_name" {
  description = "Name of the SQS queue"
  type        = string
}

variable "dlq_name" {
  description = "Name of the Dead Letter Queue"
  type        = string
}

variable "gcp_project_number" {
  description = "GCP project number for workload identity federation"
  type        = string
  default     = ""
}