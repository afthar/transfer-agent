# Transfer Worker - Event-Driven Cross-Cloud File Transfer Service

A secure, testable, and production-ready Python service that reacts to events and transfers files between cloud storage providers (AWS S3 and GCP GCS). Built with container-first design, comprehensive security scanning, and full observability.

## 🚀 Quick Start

### One-Command Run

```bash
# Run with Docker
docker build -t transfer-worker . && docker run --rm transfer-worker

# Run locally
python transfer_worker.py

# Run with docker-compose (if available)
docker-compose up
```

### One-Command Test

```bash
# Run all tests
pytest test_transfer_worker.py -v

# Run with coverage
pytest test_transfer_worker.py --cov=transfer_worker --cov-report=term

# Run in Docker
docker build -t transfer-worker-test --target=builder . && docker run --rm transfer-worker-test pytest test_transfer_worker.py
```

## 📋 Event Schema

The service processes events conforming to this schema:

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

## 🎯 SLOs (Service Level Objectives)

| SLO | Target | Measurement Window | Description |
|-----|--------|-------------------|-------------|
| **Transfer Success Rate** | 99.5% | 30 days | Percentage of successful transfers (excluding client errors) |
| **Transfer Latency P99** | < 60 seconds | 7 days | 99th percentile transfer completion time |

## 🔐 Security Architecture

### Identity & Authentication

#### Workload Identity Federation (WIF) / STS Approach

**NO LONG-LIVED KEYS** - This service uses short-lived, automatically rotated credentials through:

1. **AWS → GCP Transfers**:
   ```yaml
   # AWS assumes IAM role, exchanges for GCP credentials
   AWS IAM Role → AWS STS → Workload Identity Pool → GCP Service Account
   ```

2. **GCP → AWS Transfers**:
   ```yaml
   # GCP Service Account exchanges for AWS credentials
   GCP Service Account → Workload Identity Federation → AWS IAM Role
   ```

### Least-Privilege Permissions

**Source Storage** (Read Only):
- `s3:GetObject`
- `storage.objects.get`

**Destination Storage** (Write Only):
- `s3:PutObject`
- `storage.objects.create`

**Queue** (Consume Only):
- `sqs:ReceiveMessage`, `sqs:DeleteMessage`
- `pubsub.subscriptions.consume`

### Security Features

- ✅ **Non-root container** (UID 1001)
- ✅ **Multi-stage Docker build** (minimal attack surface)
- ✅ **Security scanning** (Trivy, Bandit, Safety, Semgrep)
- ✅ **SBOM generation** (CycloneDX format)
- ✅ **Health checks** built-in
- ✅ **Structured JSON logging** (no sensitive data)
- ✅ **Checksum validation** (SHA256)

## 🏗️ Architecture

### Core Components

1. **TransferWorker**: Main orchestrator with retry logic and idempotency
2. **StorageSimulator**: Local testing interface (replaceable with cloud SDKs)
3. **QueueSimulator**: Message queue abstraction
4. **MetricsCollector**: Prometheus-compatible metrics
5. **StructuredLogger**: JSON logging with correlation IDs

### Failure Handling

```yaml
Retry Strategy:
  - Max Attempts: 3
  - Backoff: Exponential (1s → 2s → 4s → max 30s)
  - Retryable Errors: Network, Timeout, Rate Limit, Service Unavailable

Dead Letter Queue:
  - Enabled: true
  - Max Receive Count: 3
  - Contains: Failed events + error details + retry count
```

### Observability

**Logs** (JSON structured):
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

**Metrics** (Prometheus format):
- `transfer_success_total`
- `transfer_failure_total`
- `transfer_duration_seconds`
- `transfer_bytes`
- `retry_count`

**Health Endpoints**:
- `/health` - Liveness probe
- `/ready` - Readiness probe
- `/metrics` - Prometheus metrics

## 🧪 Testing

### Test Coverage

- ✅ **Unit Tests**: Core logic, retry mechanism, idempotency
- ✅ **Edge Cases**: Network failures, checksum mismatches, DLQ overflow
- ✅ **Integration Tests**: End-to-end transfer simulation
- ✅ **Security Tests**: Container scanning, dependency vulnerabilities

### Running Tests

```bash
# Unit tests only
pytest test_transfer_worker.py::TestTransferWorker -v

# Integration tests
pytest test_transfer_worker.py::TestIntegration -v

# With failure injection
pytest test_transfer_worker.py::test_retry_with_eventual_success -v
```

## 🚢 Deployment

### Container

```bash
# Build
docker build -t transfer-worker:latest .

# Run with volume for persistence
docker run -v $(pwd)/storage:/app/storage_simulator transfer-worker:latest

# With environment variables
docker run -e WORKER_LOG_LEVEL=DEBUG transfer-worker:latest
```

### Kubernetes (Example)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: transfer-worker
spec:
  replicas: 3
  template:
    spec:
      serviceAccountName: transfer-worker-sa  # For Workload Identity
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
        livenessProbe:
          exec:
            command: ["python", "-c", "..."]
          periodSeconds: 30
        readinessProbe:
          exec:
            command: ["python", "-c", "..."]
          periodSeconds: 10
```

## 📊 Monitoring

### Dashboards

Recommended Grafana queries:

```promql
# Success Rate
rate(transfer_success_total[5m]) / rate(transfer_success_total[5m] + transfer_failure_total[5m])

# P99 Latency
histogram_quantile(0.99, rate(transfer_duration_seconds_bucket[5m]))

# Throughput
rate(transfer_bytes[5m])
```

### Alerts

```yaml
- alert: HighFailureRate
  expr: rate(transfer_failure_total[5m]) > 0.05
  for: 5m
  annotations:
    summary: "Transfer failure rate above 5%"

- alert: HighLatency
  expr: histogram_quantile(0.99, rate(transfer_duration_seconds_bucket[5m])) > 60
  for: 5m
  annotations:
    summary: "P99 latency exceeds 60 seconds"
```

## 📝 Assumptions & Unknowns

### Assumptions

1. **Queue Integration**: Service assumes a queue consumer pattern (SQS/PubSub/Service Bus)
2. **File Sizes**: Optimized for files < 1GB (streaming required for larger files)
3. **Network**: Assumes reliable network between service and cloud providers
4. **Idempotency**: Based on `eventId` - requires unique IDs from upstream
5. **Local Testing**: Uses file system simulation - production uses native SDKs

### Unknowns

1. **Queue Configuration**: Actual queue (SQS/PubSub) not specified
2. **Authentication Details**: Specific WIF/OIDC provider configurations
3. **Scale Requirements**: Expected TPS and concurrent transfers
4. **Data Sensitivity**: Encryption requirements beyond TLS
5. **Compliance**: Specific regulatory requirements (GDPR, HIPAA, etc.)
6. **Cost Constraints**: Cross-region/cross-cloud egress cost limits

## 🛠️ Development

### Prerequisites

```bash
# Python 3.9+
python --version

# Install dependencies
pip install -r requirements.txt

# Run locally
python transfer_worker.py
```

### Project Structure

```
.
├── transfer_worker.py       # Main application
├── test_transfer_worker.py  # Test suite
├── event_schema.json       # Event JSON schema
├── ops_profile.json        # Operational profile
├── requirements.txt        # Python dependencies
├── Dockerfile             # Multi-stage container build
├── .github/
│   └── workflows/
│       └── ci.yml         # CI/CD pipeline
├── terraform/             # IaC (optional)
└── README.md             # This file
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## 📄 License

[Specify your license]

## 🆘 Support

For issues or questions:
1. Check the [ADR document](./ADR.md) for architectural decisions
2. Review the [ops profile](./ops_profile.json) for operational details
3. Create an issue with logs and event JSON

---

**Version**: 1.0.0  
**Last Updated**: January 2024  
**Maintainer**: Transfer Worker Team