#!/bin/bash
# Module 13 - Live Demo: S3 Lifecycle and Data Protection
# Prereq: Run deploy.sh first
set -e

STACK_NAME="mod13-object-storage-demo"
BUCKET=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' --output text)

echo "========================================"
echo " Module 13: Object Storage (S3)"
echo " Bucket: ${BUCKET}"
echo "========================================"
echo ""

# --- ACT 1: Storage Classes ---
echo "--- ACT 1: Storage Classes ---"
echo ""

# Show current storage class of objects
echo "[1.1] Current objects and storage classes:"
aws s3api list-objects-v2 --bucket ${BUCKET} \
  --query 'Contents[*].{Key:Key,StorageClass:StorageClass,Size:Size}' --output table
echo ""

# Move archive file to Glacier Instant Retrieval
echo "[1.2] Moving archive to GLACIER_IR..."
aws s3 cp s3://${BUCKET}/archive/audit-2024.txt s3://${BUCKET}/archive/audit-2024.txt \
  --storage-class GLACIER_IR
echo ""

# Verify storage class change
echo "[1.3] Verify storage class:"
aws s3api head-object --bucket ${BUCKET} --key archive/audit-2024.txt \
  --query '{StorageClass:StorageClass}' --output table
echo ""

# --- ACT 2: Lifecycle Policies ---
echo "--- ACT 2: Lifecycle Policies ---"
echo ""

# Create lifecycle rules
echo "[2.1] Applying lifecycle rules..."
aws s3api put-bucket-lifecycle-configuration \
  --bucket ${BUCKET} \
  --lifecycle-configuration '{
    "Rules": [
      {
        "ID": "TransitionReports",
        "Status": "Enabled",
        "Filter": {"Prefix": "reports/"},
        "Transitions": [
          {"Days": 30, "StorageClass": "STANDARD_IA"},
          {"Days": 90, "StorageClass": "GLACIER"}
        ]
      },
      {
        "ID": "ExpireLogs",
        "Status": "Enabled",
        "Filter": {"Prefix": "logs/"},
        "Expiration": {"Days": 365}
      },
      {
        "ID": "CleanupMultipart",
        "Status": "Enabled",
        "Filter": {"Prefix": ""},
        "AbortIncompleteMultipartUpload": {"DaysAfterInitiation": 7}
      }
    ]
  }'
echo "  ✓ 3 lifecycle rules applied"
echo ""

# Verify lifecycle configuration
echo "[2.2] Lifecycle rules:"
aws s3api get-bucket-lifecycle-configuration --bucket ${BUCKET} \
  --query 'Rules[*].{ID:ID,Status:Status}' --output table
echo ""

# --- ACT 3: Versioning and Data Protection ---
echo "--- ACT 3: Versioning and Data Protection ---"
echo ""

# Enable versioning on the bucket
echo "[3.1] Enabling versioning..."
aws s3api put-bucket-versioning --bucket ${BUCKET} \
  --versioning-configuration Status=Enabled
echo "  ✓ Versioning enabled"
echo ""

# Create 3 versions of a file
echo "[3.2] Creating 3 versions of important-doc.txt..."
echo "Version 1: Original content" | aws s3 cp - s3://${BUCKET}/important-doc.txt
echo "Version 2: Updated content" | aws s3 cp - s3://${BUCKET}/important-doc.txt
echo "Version 3: Final content" | aws s3 cp - s3://${BUCKET}/important-doc.txt
echo ""

# List all versions
echo "[3.3] All versions:"
aws s3api list-object-versions --bucket ${BUCKET} --prefix important-doc.txt \
  --query 'Versions[*].{VersionId:VersionId,IsLatest:IsLatest,Modified:LastModified}' \
  --output table
echo ""

# Restore version 1 (recover original content)
echo "[3.4] Restoring version 1 (original content):"
V1_ID=$(aws s3api list-object-versions --bucket ${BUCKET} --prefix important-doc.txt \
  --query 'Versions[-1].VersionId' --output text)
aws s3api get-object --bucket ${BUCKET} --key important-doc.txt \
  --version-id ${V1_ID} /tmp/recovered.txt > /dev/null
echo -n "  Content: "
cat /tmp/recovered.txt
echo ""

# Simulate accidental deletion (adds a delete marker, versions still exist)
echo "[3.5] Simulating accidental deletion..."
aws s3 rm s3://${BUCKET}/important-doc.txt
echo ""

# Show that versions are preserved despite deletion
echo "[3.6] Versions still preserved after delete:"
aws s3api list-object-versions --bucket ${BUCKET} --prefix important-doc.txt \
  --query '{Versions:Versions[0].VersionId,DeleteMarkers:DeleteMarkers[0].IsLatest}' --output json
echo ""

echo "========================================"
echo " Demo Complete!"
echo "========================================"
