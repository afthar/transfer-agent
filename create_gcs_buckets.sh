#!/bin/bash

# Create new GCS buckets with unique names
NEW_GCS_SOURCE="transfer-worker-source-${RANDOM}"
NEW_GCS_DEST="transfer-worker-dest-${RANDOM}"

echo "Creating new GCS buckets:"
echo "Source: gs://${NEW_GCS_SOURCE}"
echo "Dest: gs://${NEW_GCS_DEST}"

# Create buckets
gsutil mb -p testops-458808 -l us-central1 gs://${NEW_GCS_SOURCE}
gsutil mb -p testops-458808 -l us-central1 gs://${NEW_GCS_DEST}

# Enable versioning
gsutil versioning set on gs://${NEW_GCS_SOURCE}
gsutil versioning set on gs://${NEW_GCS_DEST}

# Update the configuration
echo "" >> .env.cloud
echo "# Updated GCS buckets (accessible)" >> .env.cloud
echo "export GCS_SOURCE_BUCKET=${NEW_GCS_SOURCE}" >> .env.cloud
echo "export GCS_DEST_BUCKET=${NEW_GCS_DEST}" >> .env.cloud

echo "✅ New GCS buckets created successfully!"
echo "Source: gs://${NEW_GCS_SOURCE}"
echo "Dest: gs://${NEW_GCS_DEST}"