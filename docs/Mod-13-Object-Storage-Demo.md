# Module 13 Demo: Object Storage — "S3 Lifecycle and Data Protection"

## Prerequisites
- AWS CLI configured with admin credentials
- Permission to create S3 buckets

---

## Part 1: Setup (do before class)

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
SUFFIX="demo-$(date +%Y%m%d)-${ACCOUNT_ID:0:6}"
BUCKET="s3-lifecycle-${SUFFIX}"

# Create the bucket
aws s3 mb s3://${BUCKET}

# Upload sample files of different "ages" and types
echo "Current transaction data - accessed frequently" > /tmp/hot-data.txt
echo "Last month's report - accessed occasionally" > /tmp/warm-data.txt
echo "Archived audit log from 2 years ago" > /tmp/cold-data.txt
dd if=/dev/urandom bs=1M count=5 of=/tmp/large-file.bin 2>/dev/null

aws s3 cp /tmp/hot-data.txt s3://${BUCKET}/transactions/today.txt
aws s3 cp /tmp/warm-data.txt s3://${BUCKET}/reports/monthly-report.txt
aws s3 cp /tmp/cold-data.txt s3://${BUCKET}/archive/audit-2024.txt
aws s3 cp /tmp/large-file.bin s3://${BUCKET}/uploads/dataset.bin
```

---

## Part 2: Live Demo (in class)

### 🎬 Act 1: S3 Storage Classes — Pay for What You Need

> **Say:** "Not all data is accessed equally. S3 offers storage classes from hot to cold — each cheaper but with higher retrieval costs."

```bash
# Show current storage class (default = STANDARD)
aws s3api head-object --bucket ${BUCKET} --key transactions/today.txt \\
  --query '{StorageClass:StorageClass,Size:ContentLength}' --output table

# Copy an object to a different storage class
aws s3 cp s3://${BUCKET}/archive/audit-2024.txt s3://${BUCKET}/archive/audit-2024.txt \\
  --storage-class GLACIER_IR

# Verify it changed
aws s3api head-object --bucket ${BUCKET} --key archive/audit-2024.txt \\
  --query '{StorageClass:StorageClass}' --output table

# Show the pricing tiers (talk through)
echo "
Storage Class Comparison:
─────────────────────────────────────────────────────────
Class                    Storage $/GB   Retrieval   Min Duration
─────────────────────────────────────────────────────────
S3 Standard              \$0.023         Free        None
S3 Standard-IA           \$0.0125        \$0.01/GB    30 days
S3 One Zone-IA           \$0.01          \$0.01/GB    30 days
S3 Glacier Instant       \$0.004         \$0.03/GB    90 days
S3 Glacier Flexible      \$0.0036        Minutes-hrs 90 days
S3 Glacier Deep Archive  \$0.00099       12-48 hrs   180 days
─────────────────────────────────────────────────────────
"
```

> **Talking points:**
> - "Standard costs 23x more than Deep Archive per GB — move cold data down!"
> - "Intelligent-Tiering does this automatically if you're unsure about access patterns."
> - "Minimum duration charges mean you pay for 30/90/180 days even if you delete early."

---

### 🎬 Act 2: Lifecycle Policies — Automated Data Tiering

> **Say:** "You don't want to manually move millions of objects between tiers. Lifecycle policies automate it."

```bash
# Create a lifecycle policy
cat > /tmp/lifecycle.json << 'EOF'
{
  "Rules": [
    {
      "ID": "TransitionToIA",
      "Status": "Enabled",
      "Filter": {"Prefix": "reports/"},
      "Transitions": [
        {
          "Days": 30,
          "StorageClass": "STANDARD_IA"
        },
        {
          "Days": 90,
          "StorageClass": "GLACIER"
        }
      ]
    },
    {
      "ID": "ExpireOldLogs",
      "Status": "Enabled",
      "Filter": {"Prefix": "logs/"},
      "Expiration": {
        "Days": 365
      },
      "Transitions": [
        {
          "Days": 30,
          "StorageClass": "STANDARD_IA"
        }
      ]
    },
    {
      "ID": "CleanupIncompleteUploads",
      "Status": "Enabled",
      "Filter": {"Prefix": ""},
      "AbortIncompleteMultipartUpload": {
        "DaysAfterInitiation": 7
      }
    }
  ]
}
EOF

# Apply the lifecycle configuration
aws s3api put-bucket-lifecycle-configuration \\
  --bucket ${BUCKET} \\
  --lifecycle-configuration file:///tmp/lifecycle.json

# Verify
aws s3api get-bucket-lifecycle-configuration --bucket ${BUCKET} \\
  --query 'Rules[*].{ID:ID,Status:Status,Transitions:Transitions[*].{Days:Days,Class:StorageClass},Expiration:Expiration}' \\
  --output table
```

> **Talking points:**
> - "Rule 1: Reports move to IA after 30 days, then Glacier after 90. Automatic cost savings."
> - "Rule 2: Logs expire (delete) after 1 year — no manual cleanup."
> - "Rule 3: Abort incomplete multipart uploads after 7 days — stops hidden costs."
> - "These rules run daily. Millions of objects managed without human intervention."

---

### 🎬 Act 3: Versioning + Replication — Data Protection

> **Say:** "What if someone accidentally deletes or overwrites a critical file? Versioning keeps every version forever."

```bash
# Enable versioning
aws s3api put-bucket-versioning --bucket ${BUCKET} \\
  --versioning-configuration Status=Enabled

# Upload a file, then overwrite it
echo "Version 1: Original content" | aws s3 cp - s3://${BUCKET}/important-doc.txt
echo "Version 2: Updated content" | aws s3 cp - s3://${BUCKET}/important-doc.txt
echo "Version 3: Final content" | aws s3 cp - s3://${BUCKET}/important-doc.txt

# Show all versions
aws s3api list-object-versions --bucket ${BUCKET} --prefix important-doc.txt \\
  --query 'Versions[*].{Key:Key,VersionId:VersionId,IsLatest:IsLatest,Modified:LastModified,Size:Size}' \\
  --output table

# Read an old version
FIRST_VERSION=$(aws s3api list-object-versions --bucket ${BUCKET} \\
  --prefix important-doc.txt \\
  --query 'Versions[-1].VersionId' --output text)

aws s3api get-object --bucket ${BUCKET} --key important-doc.txt \\
  --version-id ${FIRST_VERSION} /tmp/recovered.txt
cat /tmp/recovered.txt

# Simulate accidental deletion
aws s3 rm s3://${BUCKET}/important-doc.txt

# Show it's just a delete marker — not really gone!
aws s3api list-object-versions --bucket ${BUCKET} --prefix important-doc.txt \\
  --query '{Versions:Versions[0].{VersionId:VersionId,IsLatest:IsLatest},DeleteMarkers:DeleteMarkers[0].{VersionId:VersionId,IsLatest:IsLatest}}' \\
  --output json

echo "The file appears deleted, but ALL versions are still recoverable!"
```

> **Talking points:**
> - "Versioning keeps EVERY version — accidental overwrites are recoverable."
> - "Delete just adds a 'delete marker' — the data is still there."
> - "Combine with lifecycle rules to expire old versions after N days (control costs)."
> - "For disaster recovery, add Cross-Region Replication to copy to another region."

---

## Part 3: Cleanup

```bash
# Must delete all versions to remove a versioned bucket
aws s3api list-object-versions --bucket ${BUCKET} \
  --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
  --output json > /tmp/versions.json

aws s3api list-object-versions --bucket ${BUCKET} \
  --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
  --output json > /tmp/markers.json

# Delete all versions
aws s3api delete-objects --bucket ${BUCKET} --delete file:///tmp/versions.json 2>/dev/null
aws s3api delete-objects --bucket ${BUCKET} --delete file:///tmp/markers.json 2>/dev/null

# Delete bucket
aws s3 rb s3://${BUCKET} --force
```

---

## Summary Table

| Concept | What students see | Key takeaway |
|---------|------------------|------|
| **Storage classes** | Same object, different cost tiers | Pay for access patterns, not just size |
| **Lifecycle policies** | Automated transitions + expiration | Set-and-forget cost optimization |
| **Versioning** | Multiple versions preserved | Protection against accidental delete/overwrite |
| **Delete markers** | "Deleted" file is recoverable | Safety net for human error |

---

## Timing Guide

| Section | Duration |
|---------|----------|
| Act 1 (Storage Classes) | 4 min |
| Act 2 (Lifecycle Policies) | 5 min |
| Act 3 (Versioning) | 5 min |
| **Total** | **~14 min** |
