# AWS Module for Transfer Worker
# Handles S3 buckets, IAM roles, and SQS queues with workload identity federation

locals {
  bucket_prefix = "${var.service_name}-${var.aws_region}"
}

# S3 Buckets
resource "aws_s3_bucket" "source" {
  bucket = "${local.bucket_prefix}-${var.source_bucket_name}"
  
  tags = merge(
    var.common_tags,
    {
      Name = "${var.service_name}-source"
      Type = "source"
    }
  )
}

resource "aws_s3_bucket" "destination" {
  bucket = "${local.bucket_prefix}-${var.dest_bucket_name}"
  
  tags = merge(
    var.common_tags,
    {
      Name = "${var.service_name}-destination"
      Type = "destination"
    }
  )
}

# S3 Bucket Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "source" {
  bucket = aws_s3_bucket.source.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "destination" {
  bucket = aws_s3_bucket.destination.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 Bucket Versioning
resource "aws_s3_bucket_versioning" "source" {
  bucket = aws_s3_bucket.source.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "destination" {
  bucket = aws_s3_bucket.destination.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# SQS Queue for events
resource "aws_sqs_queue" "transfer_queue" {
  count = var.enable_sqs_queue ? 1 : 0
  
  name                       = var.queue_name
  visibility_timeout_seconds = 300
  message_retention_seconds  = 1209600  # 14 days
  receive_wait_time_seconds  = 20       # Long polling
  
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[0].arn
    maxReceiveCount     = 3
  })
  
  tags = merge(
    var.common_tags,
    {
      Name = var.queue_name
    }
  )
}

# Dead Letter Queue
resource "aws_sqs_queue" "dlq" {
  count = var.enable_sqs_queue ? 1 : 0
  
  name                      = var.dlq_name
  message_retention_seconds = 1209600  # 14 days
  
  tags = merge(
    var.common_tags,
    {
      Name = var.dlq_name
      Type = "DLQ"
    }
  )
}

# IAM Role for Transfer Worker (with trust policy for cross-cloud federation)
resource "aws_iam_role" "transfer_worker" {
  name = "${var.service_name}-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Effect = "Allow"
          Principal = {
            Service = "ec2.amazonaws.com"
          }
          Action = "sts:AssumeRole"
        }
      ],
      # GCP Workload Identity Federation
      var.gcp_project_number != "" ? [
        {
          Effect = "Allow"
          Principal = {
            Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/iam.googleapis.com"
          }
          Action = "sts:AssumeRoleWithWebIdentity"
          Condition = {
            StringEquals = {
              "iam.googleapis.com:aud" = "${var.gcp_project_number}"
            }
          }
        }
      ] : []
    )
  })
  
  tags = var.common_tags
}

# IAM Policy for Transfer Worker (Least Privilege)
resource "aws_iam_role_policy" "transfer_worker" {
  name = "${var.service_name}-policy"
  role = aws_iam_role.transfer_worker.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # S3 Read permissions (source bucket)
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.source.arn,
          "${aws_s3_bucket.source.arn}/*"
        ]
      },
      # S3 Write permissions (destination bucket)
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.destination.arn,
          "${aws_s3_bucket.destination.arn}/*"
        ]
      },
      # SQS permissions
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility"
        ]
        Resource = var.enable_sqs_queue ? [
          aws_sqs_queue.transfer_queue[0].arn
        ] : []
      },
      # DLQ permissions
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = var.enable_sqs_queue ? [
          aws_sqs_queue.dlq[0].arn
        ] : []
      },
      # CloudWatch Logs permissions
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      },
      # CloudWatch Metrics permissions
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

# Data source for AWS account ID
data "aws_caller_identity" "current" {}

# Outputs
output "source_bucket_arn" {
  description = "ARN of the source S3 bucket"
  value       = aws_s3_bucket.source.arn
}

output "destination_bucket_arn" {
  description = "ARN of the destination S3 bucket"
  value       = aws_s3_bucket.destination.arn
}

output "worker_role_arn" {
  description = "ARN of the IAM role for the transfer worker"
  value       = aws_iam_role.transfer_worker.arn
}

output "queue_url" {
  description = "URL of the SQS queue"
  value       = var.enable_sqs_queue ? aws_sqs_queue.transfer_queue[0].url : null
}

output "dlq_url" {
  description = "URL of the Dead Letter Queue"
  value       = var.enable_sqs_queue ? aws_sqs_queue.dlq[0].url : null
}