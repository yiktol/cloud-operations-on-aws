#!/bin/bash
# Module 13 - Live Demo: S3 Lifecycle and Data Protection

STACK_NAME="mod13-object-storage-demo"
BUCKET=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' --output text)

echo "Bucket: ${BUCKET}"
echo ""

echo "============================================"
echo "  ACT 1: STORAGE CLASSES"
echo "============================================"
read -p "Press Enter to show current storage class of objects..."
aws s3api list-objects-v2 --bucket ${BUCKET} \
  --query 'Contents[*].{Key:Key,StorageClass:StorageClass,Size:Size}' --output table

read -p "Press Enter to move archive file to Glacier Instant Retrieval..."
aws s3 cp s3://${BUCKET}/archive/audit-2024.txt s3://${BUCKET}/archive/audit-2024.txt \
  --storage-class GLACIER_IR
aws s3api head-object --bucket ${BUCKET} --key archive/audit-2024.txt \
  --query '{StorageClass:StorageClass}' --output table

echo ""
echo "Storage class comparison (approx $/GB/month):"
echo "  S3 Standard           = \$0.023"
echo "  S3 Standard-IA        = \$0.0125  (30-day minimum)"
echo "  S3 Glacier Instant    = \$0.004   (90-day minimum)"
echo "  S3 Glacier Deep       = \$0.00099 (180-day minimum)"
echo ""
echo ">> RESULT: Moving cold data down tiers can reduce storage costs by up to 23x."
echo ""

echo "============================================"
echo "  ACT 2: LIFECYCLE POLICIES"
echo "============================================"
read -p "Press Enter to create a lifecycle policy..."
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

aws s3api get-bucket-lifecycle-configuration --bucket ${BUCKET} \
  --query 'Rules[*].{ID:ID,Status:Status}' --output table

echo ""
echo ">> RESULT: Reports auto-tier to IA after 30d, Glacier after 90d. Set once, run forever."
echo ""

echo "============================================"
echo "  ACT 3: VERSIONING AND DATA PROTECTION"
echo "============================================"
read -p "Press Enter to enable versioning..."
aws s3api put-bucket-versioning --bucket ${BUCKET} \
  --versioning-configuration Status=Enabled
echo "Versioning enabled."

read -p "Press Enter to create 3 versions of important-doc.txt..."
echo "Version 1: Original content" | aws s3 cp - s3://${BUCKET}/important-doc.txt
echo "Version 2: Updated content" | aws s3 cp - s3://${BUCKET}/important-doc.txt
echo "Version 3: Final content" | aws s3 cp - s3://${BUCKET}/important-doc.txt

echo ">> All versions:"
aws s3api list-object-versions --bucket ${BUCKET} --prefix important-doc.txt \
  --query 'Versions[*].{VersionId:VersionId,IsLatest:IsLatest,Modified:LastModified}' \
  --output table

read -p "Press Enter to RESTORE version 1 (recover original)..."
V1_ID=$(aws s3api list-object-versions --bucket ${BUCKET} --prefix important-doc.txt \
  --query 'Versions[-1].VersionId' --output text)
aws s3api get-object --bucket ${BUCKET} --key important-doc.txt \
  --version-id ${V1_ID} /tmp/recovered.txt
echo "Recovered content: $(cat /tmp/recovered.txt)"

read -p "Press Enter to SIMULATE accidental deletion..."
aws s3 rm s3://${BUCKET}/important-doc.txt
echo "File 'deleted'. Now checking versions..."

aws s3api list-object-versions --bucket ${BUCKET} --prefix important-doc.txt \
  --query '{Versions:Versions[0].VersionId,DeleteMarkers:DeleteMarkers[0].IsLatest}' --output json

echo ""
echo ">> RESULT: Delete just added a marker. ALL versions still exist and are recoverable!"
echo ""
echo "============ DEMO COMPLETE ============"
