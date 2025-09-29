# Architecture Decision Record

Date: September 2025  
Status: Initial  

## Decisions

### 1. Python with Async/Await

Using Python with async/await for non-blocking I/O operations.

Alternatives considered: Go (better performance, less mature SDKs), Node.js (good async, weak typing), Java (too heavyweight).

Trade-off: Developer productivity over raw performance.

### 2. Storage Abstraction

StorageSimulator with filesystem backend for local development. Production uses actual cloud SDKs.

Trade-off: Development speed over production fidelity.

### 3. Idempotency

In-memory event ID tracking. Simple but doesn't survive restarts.

Alternatives: Redis (external dependency), Database (overkill), Cloud-native (vendor lock-in).

### 4. Retry Strategy

Exponential backoff (2^n) with limits. Prevents thundering herd.

### 5. JSON Logging

Structured JSON with correlation IDs for all logs. Machine-parseable but verbose.

### 6. Dead Letter Queue

In-memory DLQ with max attempts. Production would use SQS DLQ or PubSub dead letter topic.

### 7. Container Build

Three-stage build: builder, scanner, runtime. Smaller images, integrated security scanning, non-root user.

### 8. Authentication

Workload Identity Federation instead of long-lived keys. Auto-rotating credentials.

### 9. Metrics

Prometheus exposition format. Industry standard, rich ecosystem.

### 10. Queue Interface

Abstraction hiding implementation details. Allows swapping SQS/PubSub.

## Performance

### Bottlenecks

1. Network I/O - mitigated with async
2. Large files - loads entire file in memory
3. Checksum calculation - CPU-bound

### Optimizations

- Streaming for files > 100MB
- Parallel processing with queue partitioning
- Connection pooling
- Temporary caching

## Security

### Threat Model

- Data exfiltration: Least-privilege IAM
- Credential compromise: WIF eliminates risk
- Supply chain: SBOM + scanning
- Container escape: Non-root user, minimal image

### Defense Layers

1. Network: TLS, private endpoints
2. Identity: WIF, no long-lived keys
3. Authorization: Least-privilege IAM
4. Application: Checksum validation
5. Container: Non-root, minimal image

## Operations

### Observability

- Logs → CloudWatch/Stackdriver → ElasticSearch
- Metrics → Prometheus → Grafana
- Traces → OpenTelemetry → Jaeger/X-Ray

### Failure Modes

- Source unavailable: Backoff + DLQ
- Destination full: Retry
- Network partition: Timeout + retry
- Corrupted data: Checksum validation
- Queue overflow: Autoscaling

### Deployment

- Blue/Green for breaking changes
- Canary for gradual rollout
- Automated rollback on SLO breach

## Cost

### Current Decisions

- No compression (CPU vs bandwidth)
- No caching (storage vs transfer)
- Process in source region (minimize egress)

### Future

- Batch small files
- Auto-delete processed files
- Reserved capacity

## Scalability

### Current

Single worker, in-memory state, <100 TPS

### Evolution

1. Current: Single worker
2. Multiple workers, Redis, <1000 TPS
3. K8s autoscaling, distributed state, <10000 TPS
4. Multi-region, event streaming, >10000 TPS

## Technical Debt

### Known Issues

- No real cloud integration
- In-memory state
- No HTTP server
- Simple retry logic
- No rate limiting

### Priority

1. Add cloud SDKs
2. Redis for state
3. FastAPI/aiohttp
4. Circuit breaker
5. Rate limiting

## Compliance

### Data Governance

- Process in source region
- All transfers logged
- TLS in transit
- No data retention

### Gaps

- No PII detection
- No HIPAA considerations
- No formal audit trail
- No PCI detection

Document Version: 1.0  
Author: Daniel Alter - Cloud Team