"""
Unit tests for the transfer worker service.
Tests happy path, edge cases, and negative scenarios.
"""

import asyncio
import json
import uuid
from datetime import datetime, timezone
from pathlib import Path
import pytest
from unittest.mock import Mock, AsyncMock, patch

from transfer_worker import (
    TransferWorker,
    TransferEvent,
    StorageSimulator,
    QueueSimulator,
    RetryConfig,
    CloudProvider,
    StructuredLogger,
    MetricsCollector
)

class TestTransferEvent:
    """Tests for TransferEvent data model."""
    
    def test_from_json_valid(self):
        """Test creating TransferEvent from valid JSON."""
        json_data = {
            "schemaVersion": "1.0.0",
            "eventId": str(uuid.uuid4()),
            "correlationId": str(uuid.uuid4()),
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "source": {
                "provider": "aws_s3",
                "bucket": "test-bucket",
                "key": "test-file.txt"
            },
            "destination": {
                "provider": "gcp_gcs",
                "bucket": "dest-bucket",
                "key": "output-file.txt"
            },
            "metadata": {
                "contentType": "text/plain"
            }
        }
        
        event = TransferEvent.from_json(json_data)
        
        assert event.schema_version == "1.0.0"
        assert event.source["provider"] == "aws_s3"
        assert event.destination["provider"] == "gcp_gcs"
        assert event.metadata["contentType"] == "text/plain"
    
    def test_to_json(self):
        """Test converting TransferEvent to JSON."""
        event = TransferEvent(
            schema_version="1.0.0",
            event_id="test-id",
            correlation_id="correlation-id",
            timestamp="2024-01-01T00:00:00Z",
            source={"provider": "aws_s3", "bucket": "test", "key": "file.txt"},
            destination={"provider": "gcp_gcs", "bucket": "dest", "key": "output.txt"}
        )
        
        json_data = event.to_json()
        
        assert json_data["schemaVersion"] == "1.0.0"
        assert json_data["eventId"] == "test-id"
        assert json_data["source"]["provider"] == "aws_s3"

class TestStorageSimulator:
    """Tests for StorageSimulator."""
    
    @pytest.mark.asyncio
    async def test_upload_download(self, tmp_path):
        """Test upload and download operations."""
        storage = StorageSimulator(str(tmp_path / "storage"))
        test_data = b"test content"
        
        # Upload
        await storage.upload("aws_s3", "test-bucket", "test-key", test_data)
        
        # Download
        downloaded = await storage.download("aws_s3", "test-bucket", "test-key")
        
        assert downloaded == test_data
    
    @pytest.mark.asyncio
    async def test_download_nonexistent_creates_dummy(self, tmp_path):
        """Test downloading non-existent file creates dummy data."""
        storage = StorageSimulator(str(tmp_path / "storage"))
        
        # Download non-existent
        data = await storage.download("aws_s3", "new-bucket", "new-key")
        
        assert b"Simulated content" in data
    
    @pytest.mark.asyncio
    async def test_failure_injection(self, tmp_path):
        """Test failure injection for testing."""
        storage = StorageSimulator(str(tmp_path / "storage"))
        storage.enable_failure_injection()
        
        # First two attempts should fail
        with pytest.raises(Exception, match="Simulated upload failure #1"):
            await storage.upload("aws_s3", "bucket", "key", b"data")
        
        with pytest.raises(Exception, match="Simulated upload failure #2"):
            await storage.upload("aws_s3", "bucket", "key", b"data")
        
        # Third attempt should succeed
        await storage.upload("aws_s3", "bucket", "key", b"data")

class TestTransferWorker:
    """Tests for TransferWorker."""
    
    @pytest.fixture
    def sample_event(self):
        """Create a sample transfer event."""
        return TransferEvent(
            schema_version="1.0.0",
            event_id=str(uuid.uuid4()),
            correlation_id=str(uuid.uuid4()),
            timestamp=datetime.now(timezone.utc).isoformat(),
            source={
                "provider": "aws_s3",
                "bucket": "source-bucket",
                "key": "test-file.txt"
            },
            destination={
                "provider": "gcp_gcs",
                "bucket": "dest-bucket",
                "key": "output-file.txt"
            },
            metadata={
                "contentType": "text/plain"
            }
        )
    
    @pytest.mark.asyncio
    async def test_successful_transfer(self, sample_event, tmp_path):
        """Test successful file transfer (happy path)."""
        worker = TransferWorker(
            storage=StorageSimulator(str(tmp_path / "storage"))
        )
        
        # Process event
        result = await worker.process_event(sample_event)
        
        assert result is True
        assert worker.metrics.metrics["transfer_success_total"] == 1
        assert worker.metrics.metrics["transfer_failure_total"] == 0
        assert sample_event.event_id in worker.processed_events
    
    @pytest.mark.asyncio
    async def test_idempotency(self, sample_event, tmp_path):
        """Test idempotent event processing."""
        worker = TransferWorker(
            storage=StorageSimulator(str(tmp_path / "storage"))
        )
        
        # Process event twice
        result1 = await worker.process_event(sample_event)
        result2 = await worker.process_event(sample_event)
        
        assert result1 is True
        assert result2 is True
        # Should only count as one success
        assert worker.metrics.metrics["transfer_success_total"] == 1
    
    @pytest.mark.asyncio
    async def test_retry_with_eventual_success(self, sample_event, tmp_path):
        """Test retry mechanism with eventual success."""
        storage = StorageSimulator(str(tmp_path / "storage"))
        storage.enable_failure_injection()
        
        worker = TransferWorker(
            storage=storage,
            retry_config=RetryConfig(max_attempts=3, initial_delay_ms=10)
        )
        
        # Should succeed on third attempt
        result = await worker.process_event(sample_event)
        
        assert result is True
        assert worker.metrics.metrics["retry_count"] == 2  # 2 retries after first failure
        assert worker.metrics.metrics["transfer_success_total"] == 1
    
    @pytest.mark.asyncio
    async def test_max_retries_exceeded_dlq(self, sample_event, tmp_path):
        """Test DLQ when max retries exceeded."""
        storage = StorageSimulator(str(tmp_path / "storage"))
        
        # Mock storage to always fail
        async def always_fail(*args, **kwargs):
            raise Exception("Persistent failure")
        
        storage.download = always_fail
        
        worker = TransferWorker(
            storage=storage,
            retry_config=RetryConfig(max_attempts=2, initial_delay_ms=10),
            enable_dlq=True
        )
        
        # Should fail and send to DLQ
        result = await worker.process_event(sample_event)
        
        assert result is False
        assert worker.metrics.metrics["transfer_failure_total"] == 1
        assert len(worker.dlq) == 1
        assert worker.dlq[0]["event"]["eventId"] == sample_event.event_id
    
    @pytest.mark.asyncio
    async def test_checksum_validation(self, tmp_path):
        """Test checksum validation during transfer."""
        storage = StorageSimulator(str(tmp_path / "storage"))
        worker = TransferWorker(storage=storage)
        
        # Create event with checksum
        event = TransferEvent(
            schema_version="1.0.0",
            event_id=str(uuid.uuid4()),
            correlation_id=str(uuid.uuid4()),
            timestamp=datetime.now(timezone.utc).isoformat(),
            source={
                "provider": "aws_s3",
                "bucket": "source-bucket",
                "key": "test-file.txt"
            },
            destination={
                "provider": "gcp_gcs",
                "bucket": "dest-bucket",
                "key": "output-file.txt"
            },
            metadata={
                "checksumSHA256": "invalid_checksum"
            }
        )
        
        # Should fail due to checksum mismatch
        result = await worker.process_event(event)
        
        assert result is False
        assert worker.metrics.metrics["transfer_failure_total"] == 1
    
    @pytest.mark.asyncio
    async def test_exponential_backoff(self):
        """Test exponential backoff calculation."""
        worker = TransferWorker(
            retry_config=RetryConfig(
                initial_delay_ms=100,
                max_delay_ms=10000,
                multiplier=2
            )
        )
        
        # Test backoff delays
        assert worker._calculate_backoff_delay(1) == 100
        assert worker._calculate_backoff_delay(2) == 200
        assert worker._calculate_backoff_delay(3) == 400
        assert worker._calculate_backoff_delay(4) == 800
        
        # Should cap at max_delay
        assert worker._calculate_backoff_delay(10) == 10000
    
    def test_health_status(self):
        """Test health status reporting."""
        worker = TransferWorker()
        
        # Initially healthy
        health = worker.get_health_status()
        assert health["status"] == "healthy"
        assert health["dlq_size"] == 0
        
        # Add failures to degrade health
        for _ in range(10):
            worker.metrics.record_failure()
        
        health = worker.get_health_status()
        assert health["status"] == "degraded"
    
    def test_readiness_status(self):
        """Test readiness status."""
        worker = TransferWorker()
        
        readiness = worker.get_readiness_status()
        assert readiness["ready"] is True
        assert "timestamp" in readiness

class TestQueueSimulator:
    """Tests for QueueSimulator."""
    
    @pytest.mark.asyncio
    async def test_send_receive_message(self):
        """Test sending and receiving messages."""
        queue = QueueSimulator()
        event = TransferEvent(
            schema_version="1.0.0",
            event_id="test-id",
            correlation_id="corr-id",
            timestamp="2024-01-01T00:00:00Z",
            source={"provider": "aws_s3", "bucket": "test", "key": "file"},
            destination={"provider": "gcp_gcs", "bucket": "dest", "key": "out"}
        )
        
        # Send message
        await queue.send_message(event)
        assert queue.get_queue_size() == 1
        
        # Receive message
        received = await queue.receive_message()
        assert received == event
        assert queue.get_queue_size() == 0
    
    @pytest.mark.asyncio
    async def test_receive_timeout(self):
        """Test receive timeout."""
        queue = QueueSimulator()
        
        # Should timeout and return None
        received = await queue.receive_message(timeout=0.1)
        assert received is None

class TestMetricsCollector:
    """Tests for MetricsCollector."""
    
    def test_record_metrics(self):
        """Test recording various metrics."""
        metrics = MetricsCollector()
        
        # Record successes
        metrics.record_success(1.5, 1000)
        metrics.record_success(2.0, 2000)
        
        # Record failure
        metrics.record_failure()
        
        # Record retries
        metrics.record_retry()
        metrics.record_retry()
        
        # Check metrics
        snapshot = metrics.get_metrics()
        assert snapshot["transfer_success_total"] == 2
        assert snapshot["transfer_failure_total"] == 1
        assert snapshot["retry_count"] == 2
        assert snapshot["avg_duration_seconds"] == 1.75
        assert snapshot["total_bytes_transferred"] == 3000
        assert abs(snapshot["transfer_success_rate"] - 66.67) < 0.1
    
    def test_success_rate_calculation(self):
        """Test success rate calculation edge cases."""
        metrics = MetricsCollector()
        
        # No transfers yet - should be 100%
        snapshot = metrics.get_metrics()
        assert snapshot["transfer_success_rate"] == 100.0
        
        # All successful
        metrics.record_success(1.0, 100)
        metrics.record_success(1.0, 100)
        snapshot = metrics.get_metrics()
        assert snapshot["transfer_success_rate"] == 100.0
        
        # All failed
        metrics2 = MetricsCollector()
        metrics2.record_failure()
        metrics2.record_failure()
        snapshot2 = metrics2.get_metrics()
        assert snapshot2["transfer_success_rate"] == 0.0

class TestStructuredLogger:
    """Tests for StructuredLogger."""
    
    def test_log_formatting(self):
        """Test structured log formatting."""
        logger = StructuredLogger("test-service")
        logger.set_context("corr-123", "event-456")
        
        # Mock the underlying logger
        with patch('transfer_worker.logger') as mock_logger:
            logger.info("Test message", extra_field="value")
            
            # Check that JSON was logged
            call_args = mock_logger.info.call_args[0][0]
            log_data = json.loads(call_args)
            
            assert log_data["level"] == "INFO"
            assert log_data["service"] == "test-service"
            assert log_data["message"] == "Test message"
            assert log_data["correlation_id"] == "corr-123"
            assert log_data["event_id"] == "event-456"
            assert log_data["extra_field"] == "value"
            assert "timestamp" in log_data

# Integration test
class TestIntegration:
    """Integration tests for the complete system."""
    
    @pytest.mark.asyncio
    async def test_end_to_end_transfer(self, tmp_path):
        """Test complete end-to-end transfer workflow."""
        # Setup
        storage = StorageSimulator(str(tmp_path / "storage"))
        worker = TransferWorker(storage=storage)
        queue = QueueSimulator()
        
        # Create and queue multiple events
        events = []
        for i in range(3):
            event = TransferEvent(
                schema_version="1.0.0",
                event_id=f"event-{i}",
                correlation_id=f"corr-{i}",
                timestamp=datetime.now(timezone.utc).isoformat(),
                source={
                    "provider": "aws_s3",
                    "bucket": "source-bucket",
                    "key": f"file-{i}.txt"
                },
                destination={
                    "provider": "gcp_gcs",
                    "bucket": "dest-bucket",
                    "key": f"output-{i}.txt"
                }
            )
            events.append(event)
            await queue.send_message(event)
        
        # Process all events
        results = []
        while queue.get_queue_size() > 0:
            event = await queue.receive_message()
            if event:
                result = await worker.process_event(event)
                results.append(result)
        
        # Verify all succeeded
        assert all(results)
        assert worker.metrics.metrics["transfer_success_total"] == 3
        assert worker.metrics.metrics["transfer_failure_total"] == 0
        assert len(worker.processed_events) == 3

if __name__ == "__main__":
    pytest.main([__file__, "-v"])