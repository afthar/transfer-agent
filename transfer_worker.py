"""
Event-driven cross-cloud transfer worker.
Handles file transfers between cloud storage providers with retry logic,
idempotency, and comprehensive observability.
"""

import asyncio
import hashlib
import json
import logging
import os
import time
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from pathlib import Path
from typing import Any, Dict, Optional, Set
from contextlib import asynccontextmanager

# Configure structured logging
logging.basicConfig(
    level=logging.INFO,
    format='%(message)s',
    handlers=[logging.StreamHandler()]
)
logger = logging.getLogger(__name__)

class CloudProvider(Enum):
    """Supported cloud storage providers."""
    AWS_S3 = "aws_s3"
    GCP_GCS = "gcp_gcs"

class TransferStatus(Enum):
    """Transfer operation status."""
    PENDING = "pending"
    IN_PROGRESS = "in_progress"
    SUCCESS = "success"
    FAILED = "failed"
    RETRYING = "retrying"
    DLQ = "dead_letter_queue"

@dataclass
class RetryConfig:
    """Retry configuration for transfer operations."""
    max_attempts: int = 3
    initial_delay_ms: int = 1000
    max_delay_ms: int = 30000
    multiplier: int = 2

@dataclass
class TransferEvent:
    """Transfer event data model."""
    schema_version: str
    event_id: str
    correlation_id: str
    timestamp: str
    source: Dict[str, str]
    destination: Dict[str, str]
    metadata: Dict[str, Any] = field(default_factory=dict)
    
    @classmethod
    def from_json(cls, data: Dict[str, Any]) -> "TransferEvent":
        """Create TransferEvent from JSON dictionary."""
        return cls(
            schema_version=data["schemaVersion"],
            event_id=data["eventId"],
            correlation_id=data["correlationId"],
            timestamp=data["timestamp"],
            source=data["source"],
            destination=data["destination"],
            metadata=data.get("metadata", {})
        )
    
    def to_json(self) -> Dict[str, Any]:
        """Convert to JSON-serializable dictionary."""
        return {
            "schemaVersion": self.schema_version,
            "eventId": self.event_id,
            "correlationId": self.correlation_id,
            "timestamp": self.timestamp,
            "source": self.source,
            "destination": self.destination,
            "metadata": self.metadata
        }

class StructuredLogger:
    """Structured JSON logger with correlation tracking."""
    
    def __init__(self, service_name: str = "transfer-worker"):
        self.service_name = service_name
        self.correlation_id: Optional[str] = None
        self.event_id: Optional[str] = None
    
    def set_context(self, correlation_id: str, event_id: str):
        """Set logging context for current operation."""
        self.correlation_id = correlation_id
        self.event_id = event_id
    
    def _format_message(self, level: str, message: str, **kwargs) -> str:
        """Format log message as structured JSON."""
        log_entry = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "level": level,
            "service": self.service_name,
            "message": message,
            "correlation_id": self.correlation_id,
            "event_id": self.event_id,
            **kwargs
        }
        return json.dumps(log_entry)
    
    def info(self, message: str, **kwargs):
        logger.info(self._format_message("INFO", message, **kwargs))
    
    def error(self, message: str, **kwargs):
        logger.error(self._format_message("ERROR", message, **kwargs))
    
    def warning(self, message: str, **kwargs):
        logger.warning(self._format_message("WARNING", message, **kwargs))
    
    def debug(self, message: str, **kwargs):
        logger.debug(self._format_message("DEBUG", message, **kwargs))

class MetricsCollector:
    """Simple metrics collector for monitoring."""
    
    def __init__(self):
        self.metrics = {
            "transfer_success_total": 0,
            "transfer_failure_total": 0,
            "transfer_duration_seconds": [],
            "transfer_bytes": [],
            "retry_count": 0
        }
    
    def record_success(self, duration: float, bytes_transferred: int):
        """Record successful transfer metrics."""
        self.metrics["transfer_success_total"] += 1
        self.metrics["transfer_duration_seconds"].append(duration)
        self.metrics["transfer_bytes"].append(bytes_transferred)
    
    def record_failure(self):
        """Record failed transfer."""
        self.metrics["transfer_failure_total"] += 1
    
    def record_retry(self):
        """Record retry attempt."""
        self.metrics["retry_count"] += 1
    
    def get_metrics(self) -> Dict[str, Any]:
        """Get current metrics snapshot."""
        return {
            "transfer_success_total": self.metrics["transfer_success_total"],
            "transfer_failure_total": self.metrics["transfer_failure_total"],
            "transfer_success_rate": self._calculate_success_rate(),
            "retry_count": self.metrics["retry_count"],
            "avg_duration_seconds": self._calculate_avg_duration(),
            "total_bytes_transferred": sum(self.metrics["transfer_bytes"])
        }
    
    def _calculate_success_rate(self) -> float:
        """Calculate success rate percentage."""
        total = self.metrics["transfer_success_total"] + self.metrics["transfer_failure_total"]
        if total == 0:
            return 100.0
        return (self.metrics["transfer_success_total"] / total) * 100
    
    def _calculate_avg_duration(self) -> float:
        """Calculate average transfer duration."""
        durations = self.metrics["transfer_duration_seconds"]
        if not durations:
            return 0.0
        return sum(durations) / len(durations)

class StorageSimulator:
    """Simulates cloud storage operations for local testing."""
    
    def __init__(self, base_dir: str = "./storage_simulator"):
        self.base_dir = Path(base_dir)
        self.base_dir.mkdir(parents=True, exist_ok=True)
        self.failure_injection = False
        self.failure_count = 0
    
    def _get_storage_path(self, provider: str, bucket: str, key: str) -> Path:
        """Get local path for simulated storage."""
        return self.base_dir / provider / bucket / key
    
    async def upload(self, provider: str, bucket: str, key: str, data: bytes):
        """Simulate upload operation."""
        # Simulate network delay
        await asyncio.sleep(0.1)
        
        # Inject failures for testing
        if self.failure_injection and self.failure_count < 2:
            self.failure_count += 1
            raise Exception(f"Simulated upload failure #{self.failure_count}")
        
        path = self._get_storage_path(provider, bucket, key)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    
    async def download(self, provider: str, bucket: str, key: str) -> bytes:
        """Simulate download operation."""
        # Simulate network delay
        await asyncio.sleep(0.1)
        
        # Inject failures for testing
        if self.failure_injection and self.failure_count < 2:
            self.failure_count += 1
            raise Exception(f"Simulated download failure #{self.failure_count}")
        
        path = self._get_storage_path(provider, bucket, key)
        if not path.exists():
            # Create dummy file for simulation
            path.parent.mkdir(parents=True, exist_ok=True)
            dummy_data = f"Simulated content for {key}".encode()
            path.write_bytes(dummy_data)
        
        return path.read_bytes()
    
    def enable_failure_injection(self):
        """Enable failure injection for testing."""
        self.failure_injection = True
        self.failure_count = 0
    
    def disable_failure_injection(self):
        """Disable failure injection."""
        self.failure_injection = False
        self.failure_count = 0

class TransferWorker:
    """Main transfer worker implementation."""
    
    def __init__(
        self,
        storage: Optional[StorageSimulator] = None,
        retry_config: Optional[RetryConfig] = None,
        enable_dlq: bool = True
    ):
        self.storage = storage or StorageSimulator()
        self.retry_config = retry_config or RetryConfig()
        self.enable_dlq = enable_dlq
        self.logger = StructuredLogger()
        self.metrics = MetricsCollector()
        self.processed_events: Set[str] = set()  # Idempotency tracking
        self.dlq: list = []  # Dead letter queue
    
    async def process_event(self, event: TransferEvent) -> bool:
        """
        Process a transfer event with retry logic and idempotency.
        
        Returns:
            bool: True if transfer successful, False otherwise
        """
        # Set logging context
        self.logger.set_context(event.correlation_id, event.event_id)
        
        # Check idempotency
        if event.event_id in self.processed_events:
            self.logger.info(
                "Event already processed (idempotent check)",
                event_id=event.event_id
            )
            return True
        
        self.logger.info(
            "Starting transfer",
            source=event.source,
            destination=event.destination
        )
        
        start_time = time.time()
        attempt = 0
        
        while attempt < self.retry_config.max_attempts:
            try:
                attempt += 1
                if attempt > 1:
                    self.metrics.record_retry()
                    self.logger.info(f"Retry attempt {attempt}/{self.retry_config.max_attempts}")
                
                # Execute transfer
                bytes_transferred = await self._execute_transfer(event)
                
                # Record success
                duration = time.time() - start_time
                self.metrics.record_success(duration, bytes_transferred)
                self.processed_events.add(event.event_id)
                
                self.logger.info(
                    "Transfer completed successfully",
                    duration_seconds=duration,
                    bytes_transferred=bytes_transferred
                )
                return True
                
            except Exception as e:
                self.logger.error(
                    f"Transfer failed on attempt {attempt}",
                    error=str(e),
                    attempt=attempt
                )
                
                if attempt < self.retry_config.max_attempts:
                    delay = self._calculate_backoff_delay(attempt)
                    self.logger.info(f"Waiting {delay}ms before retry")
                    await asyncio.sleep(delay / 1000)
                else:
                    # Max retries exceeded - send to DLQ
                    self.metrics.record_failure()
                    if self.enable_dlq:
                        await self._send_to_dlq(event, str(e))
                    return False
        
        return False
    
    async def _execute_transfer(self, event: TransferEvent) -> int:
        """
        Execute the actual file transfer between clouds.
        
        Returns:
            int: Number of bytes transferred
        """
        # Download from source
        self.logger.info("Downloading from source", provider=event.source["provider"])
        data = await self.storage.download(
            event.source["provider"],
            event.source["bucket"],
            event.source["key"]
        )
        
        # Verify checksum if provided
        if "checksumSHA256" in event.metadata:
            calculated_checksum = hashlib.sha256(data).hexdigest()
            expected_checksum = event.metadata["checksumSHA256"]
            
            if calculated_checksum != expected_checksum:
                raise ValueError(
                    f"Checksum mismatch: expected={expected_checksum}, "
                    f"calculated={calculated_checksum}"
                )
        
        # Upload to destination
        self.logger.info("Uploading to destination", provider=event.destination["provider"])
        await self.storage.upload(
            event.destination["provider"],
            event.destination["bucket"],
            event.destination["key"],
            data
        )
        
        return len(data)
    
    def _calculate_backoff_delay(self, attempt: int) -> int:
        """Calculate exponential backoff delay in milliseconds."""
        delay = min(
            self.retry_config.initial_delay_ms * (self.retry_config.multiplier ** (attempt - 1)),
            self.retry_config.max_delay_ms
        )
        return int(delay)
    
    async def _send_to_dlq(self, event: TransferEvent, error: str):
        """Send failed event to dead letter queue."""
        dlq_entry = {
            "event": event.to_json(),
            "error": error,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "attempts": self.retry_config.max_attempts
        }
        self.dlq.append(dlq_entry)
        self.logger.error(
            "Event sent to DLQ",
            dlq_size=len(self.dlq)
        )
    
    def get_health_status(self) -> Dict[str, Any]:
        """Get health check status."""
        metrics = self.metrics.get_metrics()
        return {
            "status": "healthy" if metrics["transfer_success_rate"] > 95 else "degraded",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "metrics": metrics,
            "dlq_size": len(self.dlq)
        }
    
    def get_readiness_status(self) -> Dict[str, Any]:
        """Get readiness check status."""
        return {
            "ready": True,
            "timestamp": datetime.now(timezone.utc).isoformat()
        }

class QueueSimulator:
    """Simulates message queue for local testing."""
    
    def __init__(self):
        self.queue: asyncio.Queue = asyncio.Queue()
        self.processed_count = 0
    
    async def send_message(self, event: TransferEvent):
        """Send message to queue."""
        await self.queue.put(event)
    
    async def receive_message(self, timeout: Optional[float] = None) -> Optional[TransferEvent]:
        """Receive message from queue."""
        try:
            if timeout:
                return await asyncio.wait_for(self.queue.get(), timeout=timeout)
            else:
                return await self.queue.get()
        except asyncio.TimeoutError:
            return None
    
    def get_queue_size(self) -> int:
        """Get current queue size."""
        return self.queue.qsize()

async def main():
    """Main entry point for the transfer worker."""
    # Initialize components
    worker = TransferWorker()
    queue = QueueSimulator()
    
    # Create sample event
    sample_event = TransferEvent(
        schema_version="1.0.0",
        event_id=str(uuid.uuid4()),
        correlation_id=str(uuid.uuid4()),
        timestamp=datetime.now(timezone.utc).isoformat(),
        source={
            "provider": "aws_s3",
            "bucket": "source-bucket",
            "key": "sample-file.txt",
            "region": "us-east-1"
        },
        destination={
            "provider": "gcp_gcs",
            "bucket": "dest-bucket",
            "key": "transferred-file.txt",
            "region": "us-central1"
        },
        metadata={
            "contentType": "text/plain",
            "priority": "normal"
        }
    )
    
    # Send event to queue
    await queue.send_message(sample_event)
    
    # Process event
    event = await queue.receive_message()
    if event:
        success = await worker.process_event(event)
        print(f"\nTransfer {'succeeded' if success else 'failed'}")
    
    # Print health status
    health = worker.get_health_status()
    print(f"\nHealth Status: {json.dumps(health, indent=2)}")

if __name__ == "__main__":
    asyncio.run(main())