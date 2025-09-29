# Architecture Decision Record (ADR)

**Date**: September 2025  
**Status**: Initial  
**Context**: Event-driven transfer worker for cross-cloud file transfers

## Executive Summary

This document captures the key architectural decisions and trade-offs made in building the transfer worker service. The design prioritizes security, reliability, and operational simplicity while maintaining flexibility for future enhancements.

## Key Architectural Decisions

### 1. Async/Await Python with Event-Driven Architecture

**Decision**: Use Python async/await with event-driven processing

**Rationale**:
- **Pros**: Non-blocking I/O for network operations, efficient resource utilization, native cloud SDK support
- **Cons**: Requires Python 3.7+, complexity in error handling, potential for async/await proliferation

**Alternatives Considered**:
- Go: Better performance but less cloud SDK maturity
- Node.js: Good async support but weaker typing
- Java/Spring: Heavyweight for a simple worker

**Trade-off**: Chose developer productivity and ecosystem maturity over raw performance

### 2. Local Storage Simulation vs Real Cloud SDKs

**Decision**: Implement StorageSimulator abstraction with filesystem backend

**Rationale**:
- **Pros**: No cloud credentials needed for development, fast testing, deterministic behavior
- **Cons**: Doesn't test actual cloud APIs, potential behavior mismatch

**Trade-off**: Development velocity over production fidelity (can swap implementation)

### 3. Idempotency Through Event ID Tracking

**Decision**: In-memory set for processed event IDs

**Rationale**:
- **Pros**: Simple implementation, fast lookups, prevents duplicate processing
- **Cons**: Lost on restart, doesn't scale horizontally

**Alternatives Considered**:
- Redis: External dependency, operational complexity
- Database: Overhead for simple deduplication
- Cloud-native (DynamoDB/Firestore): Vendor lock-in

**Trade-off**: Simplicity over distributed state (can add Redis later)

### 4. Exponential Backoff with Jitter

**Decision**: Exponential backoff (2^n) with configurable limits

**Rationale**:
- **Pros**: Prevents thundering herd, reduces load on failing systems
- **Cons**: Increases latency for transient failures

**Future Enhancement**: Add jitter to prevent synchronized retries

### 5. Structured JSON Logging

**Decision**: All logs as structured JSON with correlation IDs

**Rationale**:
- **Pros**: Machine-parseable, queryable, trace requests across services
- **Cons**: Verbose for human reading, larger log volume

**Trade-off**: Observability over human readability

### 6. Dead Letter Queue (DLQ) Pattern

**Decision**: In-memory DLQ with configurable max attempts

**Rationale**:
- **Pros**: Prevents poison messages, enables manual intervention, preserves data
- **Cons**: Requires monitoring, potential for DLQ overflow

**Implementation**: Currently in-memory, production would use SQS DLQ/PubSub dead letter topic

### 7. Multi-Stage Docker Build

**Decision**: Three-stage build (builder, scanner, runtime)

**Rationale**:
- **Pros**: Smaller images (no build tools), security scanning integrated, non-root user
- **Cons**: Longer build times, complexity in debugging

**Security Wins**:
- No compiler/build tools in runtime
- Explicit vulnerability scanning
- Non-root user (UID 1001)
- Minimal base image

### 8. Workload Identity Federation Over Long-Lived Keys

**Decision**: No long-lived credentials, use WIF/OIDC

**Rationale**:
- **Pros**: Auto-rotating credentials, no secrets management, audit trail
- **Cons**: Complex setup, requires cloud IAM configuration

**Security Impact**: Eliminates credential leak risk

### 9. Prometheus Metrics Format

**Decision**: Prometheus exposition format for metrics

**Rationale**:
- **Pros**: Industry standard, rich ecosystem, built-in aggregations
- **Cons**: Pull-based model, requires service discovery

**Alternatives Considered**:
- CloudWatch/Stackdriver: Vendor lock-in
- StatsD: Less expressive
- OpenTelemetry: More complex

### 10. Queue Abstraction

**Decision**: QueueSimulator interface hiding implementation

**Rationale**:
- **Pros**: Swap SQS/PubSub without code changes
- **Cons**: Lowest common denominator features

**Trade-off**: Portability over cloud-specific features

## Performance Considerations

### Bottlenecks Identified

1. **Network I/O**: Mitigated with async/await
2. **Large Files**: Current implementation loads entire file in memory
3. **Checksum Calculation**: CPU-bound for large files

### Optimization Opportunities

1. **Streaming Transfers**: For files > 100MB
2. **Parallel Processing**: Multiple workers with queue partitioning
3. **Connection Pooling**: Reuse HTTP connections
4. **Caching**: Store frequently accessed files temporarily

## Security Considerations

### Threat Model

1. **Data Exfiltration**: Mitigated by least-privilege IAM
2. **Credential Compromise**: Eliminated with WIF
3. **Supply Chain**: SBOM + vulnerability scanning
4. **Container Escape**: Non-root user + minimal image

### Defense in Depth

```
Layer 1: Network (TLS, private endpoints)
Layer 2: Identity (WIF, no long-lived keys)
Layer 3: Authorization (least-privilege IAM)
Layer 4: Application (checksum validation, structured logging)
Layer 5: Container (non-root, minimal image, security scanning)
```

## Operational Considerations

### Observability Stack

```
Logs → CloudWatch/Stackdriver → ElasticSearch
Metrics → Prometheus → Grafana
Traces → OpenTelemetry → Jaeger/X-Ray
```

### Failure Modes

1. **Source Unavailable**: Exponential backoff + DLQ
2. **Destination Full**: Retry with backoff
3. **Network Partition**: Timeout + retry
4. **Corrupted Data**: Checksum validation
5. **Queue Overflow**: Autoscaling + backpressure

### Deployment Strategy

- **Blue/Green**: For breaking changes
- **Canary**: For gradual rollout (10% → 50% → 100%)
- **Rollback**: Automated on SLO breach

## Cost Optimization

### Decisions for Cost

1. **Compression**: Not implemented (CPU vs bandwidth trade-off)
2. **Caching**: Not implemented (storage vs transfer costs)
3. **Region Selection**: Process in source region (minimize egress)

### Future Optimizations

1. **Batch Processing**: Aggregate small files
2. **Lifecycle Policies**: Auto-delete processed files
3. **Reserved Capacity**: For predictable workloads

## Scalability Path

### Current Limitations

- Single worker process
- In-memory state
- No horizontal coordination

### Scale Evolution

1. **Phase 1** (Current): Single worker, <100 TPS
2. **Phase 2**: Multiple workers, Redis state, <1000 TPS
3. **Phase 3**: Kubernetes autoscaling, distributed state, <10000 TPS
4. **Phase 4**: Multi-region, event streaming (Kafka/Kinesis), >10000 TPS

## Technical Debt

### Acknowledged Shortcuts

1. **No Real Cloud Integration**: StorageSimulator instead of SDKs
2. **In-Memory State**: Not persistent across restarts
3. **No HTTP Server**: Metrics/health via CLI only
4. **Simple Retry Logic**: No circuit breaker pattern
5. **No Rate Limiting**: Could overwhelm destinations

### Remediation Plan

Priority order for production:
1. Add real cloud SDKs (boto3, google-cloud-storage)
2. Implement Redis for state
3. Add FastAPI/aiohttp for HTTP endpoints
4. Implement circuit breaker
5. Add rate limiting

## Compliance Considerations

### Data Governance

- **Data Residency**: Process in source region
- **Audit Logging**: All transfers logged with correlation IDs
- **Encryption**: TLS in transit, rely on cloud provider for at-rest
- **Retention**: No data retention in worker

### Regulatory Gaps

- GDPR: No PII detection/masking
- HIPAA: No BAA considerations
- SOC2: No formal audit trail
- PCI: No cardholder data detection

## Conclusion

The architecture balances simplicity, security, and operational excellence while maintaining flexibility for future enhancements. Key principles:

1. **Security First**: No long-lived credentials, least privilege, defense in depth
2. **Failure Resilient**: Retries, DLQ, exponential backoff
3. **Observable**: Structured logging, metrics, health checks
4. **Scalable Path**: Clear evolution from simple to distributed
5. **Cloud Agnostic**: Abstractions over vendor-specific services

The design deliberately chooses simplicity over complexity where possible, with clear upgrade paths as requirements evolve.

---

**Document Version**: 1.0  
**Last Updated**: September 2025  
**Author**: Daniel Alter - Cloud Team
**Review Status**: Initial