# Transfer Worker

Event-driven service for transferring files between AWS S3 and GCP GCS.

## Quick Start

Run with Docker:
```bash
docker build -t transfer-worker . && docker run --rm transfer-worker
```

Run locally:
```bash
python transfer_worker.py
```

## Event Schema

```json
{
  "schemaVersion": "1.0.0",
  "eventId": "550e8400-e29b-41d4-a716-446655440000",
  "correlationId": "7c9b5a3e-4f2d-4b8e-9c7a-2d1e3f4a5b6c",
  "timestamp": "2024-01-15T10:30:00Z",
  "source": {
    "provider": "aws_s3",
    "bucket": "source-data-bucket",
    "key": "data/2024/01/file.parquet",
    "region": "us-east-1"
  },
  "destination": {
    "provider": "gcp_gcs",
    "bucket": "destination-data-bucket",
    "key": "imports/2024/01/file.parquet",
    "region": "us-central1"
  },
  "metadata": {
    "contentType": "application/octet-stream",
    "checksumSHA256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    "maxRetries": 3,
    "priority": "normal"
  }
}
```

## SLOs

| Metric | Target | Window |
|--------|--------|---------|
| Transfer Success Rate | 99.5% | 30 days |
| Transfer Latency P99 | < 60s | 7 days |

## Security

### Authentication

Uses Workload Identity Federation for cross-cloud authentication without long-lived credentials.

AWS to GCP:
```
AWS IAM Role → AWS STS → Workload Identity Pool → GCP Service Account
```

GCP to AWS:
```
GCP Service Account → Workload Identity Federation → AWS IAM Role
```

### Permissions

Source (Read Only):
- `s3:GetObject`
- `storage.objects.get`

Destination (Write Only):
- `s3:PutObject`
- `storage.objects.create`

Queue (Consume Only):
- `sqs:ReceiveMessage`, `sqs:DeleteMessage`
- `pubsub.subscriptions.consume`

### Security Features

- Non-root container (UID 1001)
- Multi-stage Docker build
- Security scanning (Trivy, Bandit, Safety, Semgrep)
- SBOM generation (CycloneDX)
- Health checks
- Structured JSON logging
- SHA256 checksum validation

## Architecture

### Components

- **TransferWorker**: Main orchestrator with retry logic
- **StorageSimulator**: Local testing interface
- **QueueSimulator**: Message queue abstraction
- **MetricsCollector**: Prometheus metrics
- **StructuredLogger**: JSON logging with correlation IDs

### Failure Handling

- Max retry attempts: 3
- Exponential backoff: 1s, 2s, 4s (max 30s)
- Retryable errors: Network, Timeout, Rate Limit, Service Unavailable
- Dead letter queue for failed events

### Observability

Logs (JSON):
```json
{
  "timestamp": "2024-01-15T10:30:00Z",
  "level": "INFO",
  "correlation_id": "7c9b5a3e-4f2d-4b8e-9c7a-2d1e3f4a5b6c",
  "event_id": "550e8400-e29b-41d4-a716-446655440000",
  "service": "transfer-worker",
  "message": "Transfer completed successfully",
  "duration_seconds": 2.5,
  "bytes_transferred": 1048576
}
```

Metrics (Prometheus):
- `transfer_success_total`
- `transfer_failure_total`
- `transfer_duration_seconds`
- `transfer_bytes`
- `retry_count`

Health endpoints:
- `/health` - Liveness
- `/ready` - Readiness
- `/metrics` - Prometheus metrics

## Testing

```bash
# All tests
pytest test_transfer_worker.py -v

# With coverage
pytest test_transfer_worker.py --cov=transfer_worker --cov-report=term

# Specific tests
pytest test_transfer_worker.py::TestTransferWorker -v
```

## Deployment

### Docker

```bash
docker build -t transfer-worker:latest .
docker run -v $(pwd)/storage:/app/storage_simulator transfer-worker:latest
```

### Kubernetes

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: transfer-worker
spec:
  replicas: 3
  template:
    spec:
      serviceAccountName: transfer-worker-sa
      containers:
      - name: worker
        image: transfer-worker:latest
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "500m"
```

## Monitoring

Grafana queries:

```promql
# Success rate
rate(transfer_success_total[5m]) / rate(transfer_success_total[5m] + transfer_failure_total[5m])

# P99 latency
histogram_quantile(0.99, rate(transfer_duration_seconds_bucket[5m]))

# Throughput
rate(transfer_bytes[5m])
```

Alert examples:

```yaml
- alert: HighFailureRate
  expr: rate(transfer_failure_total[5m]) > 0.05
  for: 5m

- alert: HighLatency
  expr: histogram_quantile(0.99, rate(transfer_duration_seconds_bucket[5m])) > 60
  for: 5m
```

## Assumptions

- Queue consumer pattern (SQS/PubSub/Service Bus)
- Optimized for files < 1GB
- Reliable network between service and cloud providers
- Idempotency based on event ID
- Local testing uses filesystem simulation

## Known Limitations

- Queue configuration not specified
- Authentication provider details missing
- Scale requirements unknown
- Data encryption requirements unclear
- Compliance requirements not defined
- Cost constraints not specified

## Development

Requirements:
```bash
python --version  # 3.9+
pip install -r requirements.txt
python transfer_worker.py
```

Structure:
```
.
├── transfer_worker.py
├── test_transfer_worker.py
├── event_schema.json
├── ops_profile.json
├── requirements.txt
├── Dockerfile
├── .github/
│   └── workflows/
│       └── ci.yml
├── terraform/
└── README.md
```

## ADR

See ADR.md for architectural decisions and ops_profile.json for operational details.
