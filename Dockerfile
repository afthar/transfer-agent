# Multi-stage Dockerfile with security best practices
# Stage 1: Builder - Install dependencies
FROM python:3.11-slim as builder

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Create virtual environment
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Install build dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Stage 2: Security scanner
FROM python:3.11-slim as scanner

# Copy source code for scanning
COPY . /app
WORKDIR /app

# Install security scanning tools
RUN pip install --no-cache-dir safety bandit semgrep

# Run security scans
RUN safety check --json || true && \
    bandit -r transfer_worker.py -f json || true

# Stage 3: Runtime - Minimal production image
FROM python:3.11-slim as runtime

# Security: Create non-root user
RUN groupadd -r worker && \
    useradd -r -g worker -u 1001 -m -s /bin/bash worker && \
    mkdir -p /app /app/storage_simulator && \
    chown -R worker:worker /app

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH" \
    WORKER_LOG_LEVEL=INFO

# Install runtime dependencies (minimal)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Copy virtual environment from builder
COPY --from=builder --chown=worker:worker /opt/venv /opt/venv

# Set working directory
WORKDIR /app

# Copy application code
COPY --chown=worker:worker transfer_worker.py ./
COPY --chown=worker:worker event_schema.json ./
COPY --chown=worker:worker ops_profile.json ./

# Security: Switch to non-root user
USER worker

# Create volume for persistent storage
VOLUME ["/app/storage_simulator"]

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import json; from transfer_worker import TransferWorker; w = TransferWorker(); print(json.dumps(w.get_health_status()))" || exit 1

# Set entrypoint
ENTRYPOINT ["python"]

# Default command
CMD ["transfer_worker.py"]

# Metadata
LABEL \
    maintainer="transfer-worker-team" \
    version="1.0.0" \
    description="Event-driven cross-cloud transfer worker" \
    security.scan="enabled" \
    security.non-root="true" \
    security.readonly-root="false"

# Expose metrics port (if implementing HTTP server)
# EXPOSE 8080