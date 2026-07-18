# Module 12: Mountable Storage — Live CLI Demo Script

**Course:** Cloud Operations on AWS (200-SYSOPS 5.6)
**Module:** 12 — Mountable Storage
**Demo Duration:** ~15 minutes
**Companion Lab:** Lab 5 — Automating with AWS Backup for Archiving and Recovery

---

## Prerequisites

| Requirement | Details |
|---|---|
| AWS CLI version | 2.x (`aws --version`) |
| IAM permissions | `ec2:*`, `elasticfilesystem:*`, `backup:*`, `cloudwatch:GetMetricStatistics` |
| Region | `ap-southeast-1` (or set `AWS_DEFAULT_REGION`) |
| Running EC2 instance | At least one instance to demonstrate attach/detach |
| AWS CLI profile | Configured with `aws configure` or an instance profile |

> **Instructor tip:** Run all commands in a terminal window students can see clearly. Pre-export your `INSTANCE_ID` and `AZ` so substitutions are instant.

---

## Setup (Before Class)

> Complete the following steps **before** students arrive. These create the baseline resources used throughout the demo.

```bash
# ── 0. Set environment variables ────────────────────────────────────────────
export AWS_DEFAULT_REGION="ap-southeast-1"
export AZ="ap-southeast-1a"

# Get a running instance ID (pick the first one in the AZ, or hard-code yours)
export INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=availability-zone,Values=${AZ}" \
             "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" \
  --output text)

echo "Using instance: ${INSTANCE_ID} in ${AZ}"

# ── 1. Create a gp3 demo volume (used in Act 1) ────────────────────────────
export DEMO_VOL=$(aws ec2 create-volume \
  --availability-zone "${AZ}" \
  --volume-type gp3 \
  --size 20 \
  --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value=demo-mod12-gp3},{Key=Env,Value=demo}]' \
  --query "VolumeId" --output text)

echo "Demo volume created: ${DEMO_VOL}"

# Wait for the volume to become available
aws ec2 wait volume-available --volume-ids "${DEMO_VOL}"
echo "Volume is available."
```

---

## Live Demo

### Timing Overview

| Act | Topic | Time |
|---|---|---|
| Act 1 | EBS Volume Types, Creation & Attachment | ~4 min |
| Act 2 | Monitoring with CloudWatch & Volume Resizing | ~3 min |
| Act 3 | Snapshots & Data Lifecycle Manager | ~4 min |
| Act 4 | AWS Backup & Shared Storage (EFS / FSx) | ~4 min |
| **Total** | | **~15 min** |

---

### Act 1 — EBS Volume Types, Creation & Attachment (~4 min)

**Key concepts:** Volume types (gp2 vs gp3 vs io2), Availability Zone constraint, attaching volumes, instance store ephemeral behavior.

#### Talking Points

> *"Amazon EBS is network-attached, persistent block storage — think of it as a USB drive that lives in the AWS network. Unlike instance store, which disappears when you stop or terminate an instance, EBS persists independently."*
>
> *"There are six EBS volume types grouped into SSDs — gp2, gp3, io1, io2 — and HDDs — st1 and sc1. The best choice depends on whether your bottleneck is IOPS or throughput."*
>
> *"A critical rule: EBS volumes are tied to a single Availability Zone. If your instance is in ap-southeast-1a, your volume must also be in ap-southeast-1a."*

#### Commands

```bash
# ── 1a. Show existing volumes and their types ────────────────────────────────
aws ec2 describe-volumes \
  --filters "Name=tag:Env,Values=demo" \
  --query "Volumes[*].{ID:VolumeId,Type:VolumeType,Size:Size,IOPS:Iops,State:State,AZ:AvailabilityZone}" \
  --output table
```

> 💬 *"Notice our gp3 volume. A gp3 gives you 3,000 baseline IOPS and 125 MiBps included — no burst credits, predictable performance."*

```bash
# ── 1b. Compare: create a higher-performance io2 volume ─────────────────────
export IO2_VOL=$(aws ec2 create-volume \
  --availability-zone "${AZ}" \
  --volume-type io2 \
  --size 10 \
  --iops 5000 \
  --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value=demo-mod12-io2},{Key=Env,Value=demo}]' \
  --query "VolumeId" --output text)

echo "io2 volume: ${IO2_VOL}"
```

> 💬 *"With io2, we explicitly provision 5,000 IOPS. You can go up to 500 IOPS per GiB — for a 10 GiB volume that's a max of 5,000. For mission-critical databases, io2 Block Express can reach 256,000 IOPS and 99.999% durability."*

```bash
# ── 1c. Attach the gp3 volume to the running instance ───────────────────────
aws ec2 attach-volume \
  --volume-id "${DEMO_VOL}" \
  --instance-id "${INSTANCE_ID}" \
  --device /dev/sdf

# Confirm attachment
aws ec2 describe-volumes \
  --volume-ids "${DEMO_VOL}" \
  --query "Volumes[0].Attachments[0].{State:State,Device:Device,Instance:InstanceId}" \
  --output table
```

> 💬 *"The volume is now in the 'attaching' then 'attached' state. New EBS volumes reach maximum performance immediately — no initialization or pre-warming required."*

```bash
# ── 1d. Show Multi-Attach would require io1/io2 ────────────────────────────
# (Informational only — no attach to second instance needed)
aws ec2 describe-volume-attribute \
  --volume-id "${DEMO_VOL}" \
  --attribute multiAttachEnabled \
  --query "MultiAttachEnabled.Value" \
  --output text
```

> 💬 *"Multi-Attach is only available on io1/io2 volumes, and you can attach to up to 16 instances in the same AZ simultaneously — but you need a clustered file system at the OS level to manage concurrent writes safely."*

---

### Act 2 — Monitoring with CloudWatch & Volume Resizing (~3 min)

**Key concepts:** CloudWatch metrics for EBS, EBS volume status checks, live volume modification (no downtime).

#### Talking Points

> *"Unlike EC2 instances, EBS volumes don't have a built-in CPU metric. Instead, we watch IOPS, throughput, queue length, and burst balance. Queue length is your first warning sign — if it grows, you're I/O-bound."*
>
> *"One killer feature of EBS: you can resize a volume, change its type, or adjust IOPS while the volume is still attached and the instance is running. Zero downtime."*

#### Commands

```bash
# ── 2a. Pull recent CloudWatch metrics for our volume ───────────────────────
ENDTIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
STARTTIME=$(date -u -d "-1 hour" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
            date -u -v-1H +"%Y-%m-%dT%H:%M:%SZ")  # macOS fallback

aws cloudwatch get-metric-statistics \
  --namespace AWS/EBS \
  --metric-name VolumeQueueLength \
  --dimensions Name=VolumeId,Value="${DEMO_VOL}" \
  --start-time "${STARTTIME}" \
  --end-time "${ENDTIME}" \
  --period 300 \
  --statistics Average \
  --output table
```

> 💬 *"VolumeQueueLength shows how many I/O operations are waiting. Sustained values above 1 mean the volume can't keep up. For gp3, also watch BurstBalance — though gp3 has no burst, it's still emitted and is useful for gp2 migration comparison."*

```bash
# ── 2b. Check EBS volume status ─────────────────────────────────────────────
aws ec2 describe-volume-status \
  --volume-ids "${DEMO_VOL}" \
  --query "VolumeStatuses[0].{VolumeStatus:VolumeStatus.Status,IOEnabled:VolumeStatus.Details[0].Status}" \
  --output table
```

> 💬 *"EBS performs automated background checks. The status will be 'ok' for healthy volumes. 'impaired' status triggers an I/O-enabled event — you'd receive a CloudWatch alarm and potentially need to replace the volume from a snapshot."*

```bash
# ── 2c. Resize the volume live (gp3, 20 GiB → 40 GiB, bump IOPS to 6000) ───
aws ec2 modify-volume \
  --volume-id "${DEMO_VOL}" \
  --size 40 \
  --iops 6000 \
  --throughput 250

# Check modification state
aws ec2 describe-volumes-modifications \
  --volume-ids "${DEMO_VOL}" \
  --query "VolumesModifications[0].{State:ModificationState,OldSize:OriginalSize,NewSize:TargetSize,OldIOPS:OriginalIops,NewIOPS:TargetIops}" \
  --output table
```

> 💬 *"The state will show 'modifying', then 'optimizing', then 'completed'. The OS still sees the old size until you run `resize2fs` or `growpart`. And once you modify a volume, wait at least 6 hours before modifying it again."*

---

### Act 3 — Snapshots & Data Lifecycle Manager (~4 min)

**Key concepts:** Incremental snapshots to S3, cross-region copy, DLM lifecycle policies, snapshot restore latency and Fast Snapshot Restore.

#### Talking Points

> *"EBS snapshots are stored in S3 — you never interact with that bucket directly, but AWS handles the durability. Snapshots are incremental: only the changed blocks since the last snapshot are saved. But each snapshot is a complete restore point — you can create a new volume from any snapshot without needing a chain."*
>
> *"Data Lifecycle Manager (DLM) automates the create-copy-retain-delete cycle so you don't have to write Lambda functions for this. Use tags on your volumes and DLM does the rest."*

#### Commands

```bash
# ── 3a. Create a manual snapshot ────────────────────────────────────────────
export SNAP_ID=$(aws ec2 create-snapshot \
  --volume-id "${DEMO_VOL}" \
  --description "Module 12 demo snapshot" \
  --tag-specifications 'ResourceType=snapshot,Tags=[{Key=Name,Value=demo-snap-mod12},{Key=Env,Value=demo}]' \
  --query "SnapshotId" --output text)

echo "Snapshot initiated: ${SNAP_ID}"

# Check status (will be 'pending' then 'completed')
aws ec2 describe-snapshots \
  --snapshot-ids "${SNAP_ID}" \
  --query "Snapshots[0].{ID:SnapshotId,State:State,Progress:Progress,StartTime:StartTime}" \
  --output table
```

> 💬 *"Even for a 40 GiB volume that's mostly empty, the first snapshot only captures the written blocks. Subsequent snapshots only capture changed blocks — huge cost savings for long-running volumes."*

```bash
# ── 3b. Create a DLM lifecycle policy for daily snapshots ───────────────────
# First, get/create a DLM service role (use the default AWSDataLifecycleManagerDefaultRole)
# This command shows existing lifecycle policies
aws dlm get-lifecycle-policies \
  --query "Policies[*].{ID:PolicyId,Description:Description,State:State}" \
  --output table

# Create a new policy (tags volumes with Env=demo, daily at 03:00 UTC, keep 7 days)
aws dlm create-lifecycle-policy \
  --description "Demo: daily EBS snapshot, 7-day retention" \
  --state ENABLED \
  --execution-role-arn "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/AWSDataLifecycleManagerDefaultRole" \
  --policy-details '{
    "PolicyType": "EBS_SNAPSHOT_MANAGEMENT",
    "ResourceTypes": ["VOLUME"],
    "TargetTags": [{"Key": "Env", "Value": "demo"}],
    "Schedules": [{
      "Name": "DailySnapshots",
      "CreateRule": {
        "Interval": 24,
        "IntervalUnit": "HOURS",
        "Times": ["03:00"]
      },
      "RetainRule": {
        "Count": 7
      },
      "TagsToAdd": [{"Key": "ManagedBy", "Value": "DLM"}],
      "CopyTags": true
    }]
  }' \
  --query "PolicyId" --output text
```

> 💬 *"DLM uses tags to target volumes — I've tagged our volume with Env=demo. The policy fires daily at 03:00 UTC and keeps the last 7 snapshots. When the 8th is created, the oldest is automatically deleted. No Lambda, no cron jobs."*

```bash
# ── 3c. Restore a snapshot to a new volume ──────────────────────────────────
export RESTORED_VOL=$(aws ec2 create-volume \
  --availability-zone "${AZ}" \
  --snapshot-id "${SNAP_ID}" \
  --volume-type gp3 \
  --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value=demo-restored},{Key=Env,Value=demo}]' \
  --query "VolumeId" --output text)

echo "Restored volume: ${RESTORED_VOL}"
```

> 💬 *"Volumes restored from snapshots have first-access latency because blocks are lazily loaded from S3. For production recoveries where latency matters, enable Fast Snapshot Restore — it pre-warms the volume at a per-AZ cost. Otherwise, you can pre-warm by reading every block with dd before putting the volume in service."*

---

### Act 4 — AWS Backup & Shared Storage (EFS / FSx) (~4 min)

**Key concepts:** AWS Backup plans and vaults, cross-service backup, Amazon EFS shared file systems, Amazon FSx options.

#### Talking Points

> *"DLM is EBS-specific. AWS Backup is a centralized service that can back up EBS, EFS, RDS, DynamoDB, S3, and more — all in one backup plan with a single retention and compliance framework."*
>
> *"Amazon EFS is a fully managed NFS file system. Unlike EBS, EFS can be mounted simultaneously by thousands of EC2 instances across multiple AZs — perfect for shared configuration, content management, or home directories."*

#### Commands

```bash
# ── 4a. List existing AWS Backup vaults ─────────────────────────────────────
aws backup list-backup-vaults \
  --query "BackupVaultList[*].{Name:BackupVaultName,ARN:BackupVaultArn,RecoveryPoints:NumberOfRecoveryPoints}" \
  --output table
```

> 💬 *"Vaults are the destinations for backups. The Default vault is encrypted with the AWS managed key. For compliance scenarios, you'd create a separate vault with a customer-managed KMS key and apply a vault access policy to prevent deletion."*

```bash
# ── 4b. Create a demo backup plan ───────────────────────────────────────────
export BACKUP_PLAN_ID=$(aws backup create-backup-plan \
  --backup-plan '{
    "BackupPlanName": "Demo-Mod12-DailyBackup",
    "Rules": [{
      "RuleName": "DailyRule",
      "TargetBackupVaultName": "Default",
      "ScheduleExpression": "cron(0 5 * * ? *)",
      "StartWindowMinutes": 60,
      "CompletionWindowMinutes": 180,
      "Lifecycle": {
        "DeleteAfterDays": 14
      }
    }]
  }' \
  --query "BackupPlanId" --output text)

echo "Backup plan created: ${BACKUP_PLAN_ID}"
```

> 💬 *"The backup rule fires at 05:00 UTC. The start window is 60 minutes — if the backup hasn't started within that window, it fails. Completion window is 3 hours. Lifecycle here deletes recovery points after 14 days."*

```bash
# ── 4c. Assign resources to the backup plan via tags ─────────────────────────
aws backup create-backup-selection \
  --backup-plan-id "${BACKUP_PLAN_ID}" \
  --backup-selection '{
    "SelectionName": "DemoVolumesAndEFS",
    "IamRoleArn": "arn:aws:iam::'"$(aws sts get-caller-identity --query Account --output text)"':role/AWSBackupDefaultServiceRole",
    "ListOfTags": [{
      "ConditionType": "STRINGEQUALS",
      "ConditionKey": "Env",
      "ConditionValue": "demo"
    }]
  }' \
  --query "SelectionId" --output text
```

> 💬 *"Again, we're using tag-based targeting — Env=demo. This means any EBS volume, EFS file system, or RDS database with that tag in this account will automatically be included in this backup plan. No per-resource configuration needed."*

```bash
# ── 4d. Show EFS file systems (shared storage) ──────────────────────────────
aws efs describe-file-systems \
  --query "FileSystems[*].{ID:FileSystemId,Name:Name,State:LifeCycleState,SizeGiB:SizeInBytes.Value,Throughput:ThroughputMode}" \
  --output table
```

> 💬 *"EFS is a fully managed NFS v4 file system. It scales automatically — no capacity planning required. You mount it with a standard mount command on Linux. Unlike EBS which is tied to one AZ, EFS is multi-AZ by default. It supports two throughput modes: Bursting (scales with storage size) and Provisioned (you set MiBps independently of size)."*

```bash
# ── 4e. Show FSx file systems ────────────────────────────────────────────────
aws fsx describe-file-systems \
  --query "FileSystems[*].{ID:FileSystemId,Type:FileSystemType,State:Lifecycle,StorageGiB:StorageCapacityGiB}" \
  --output table 2>/dev/null || echo "(No FSx file systems in this account/region)"
```

> 💬 *"FSx gives you four managed file system flavors: Windows File Server for SMB/NTFS workloads, Lustre for HPC and ML training, NetApp ONTAP for enterprise NAS, and OpenZFS for Linux NFS workloads. Pick the one your application already speaks."*

---

## Cleanup

> Run after the demo to avoid ongoing charges.

```bash
# ── Detach the demo volume ───────────────────────────────────────────────────
aws ec2 detach-volume --volume-id "${DEMO_VOL}"
aws ec2 wait volume-available --volume-ids "${DEMO_VOL}"
echo "Volume detached."

# ── Delete DLM lifecycle policy ─────────────────────────────────────────────
# List and delete policies tagged for demo
aws dlm get-lifecycle-policies \
  --query "Policies[?Description=='Demo: daily EBS snapshot, 7-day retention'].PolicyId" \
  --output text | xargs -I {} aws dlm delete-lifecycle-policy --policy-id {}

# ── Delete AWS Backup plan (must remove selections first) ────────────────────
SELECTION_ID=$(aws backup list-backup-selections \
  --backup-plan-id "${BACKUP_PLAN_ID}" \
  --query "BackupSelectionsList[0].SelectionId" --output text)
aws backup delete-backup-selection --backup-plan-id "${BACKUP_PLAN_ID}" --selection-id "${SELECTION_ID}"
aws backup delete-backup-plan --backup-plan-id "${BACKUP_PLAN_ID}"
echo "Backup plan deleted."

# ── Delete snapshots ─────────────────────────────────────────────────────────
aws ec2 delete-snapshot --snapshot-id "${SNAP_ID}"

# ── Delete volumes ───────────────────────────────────────────────────────────
aws ec2 delete-volume --volume-id "${DEMO_VOL}"
aws ec2 delete-volume --volume-id "${IO2_VOL}" 2>/dev/null || true
aws ec2 delete-volume --volume-id "${RESTORED_VOL}" 2>/dev/null || true

echo "Cleanup complete."
```

---

## Summary Table

| Concept | CLI Service | Key Command(s) | Key Talking Point |
|---|---|---|---|
| EBS Volume Types | `ec2` | `create-volume --volume-type gp3\|io2\|st1` | gp3 = 3K IOPS baseline; io2 = provisioned up to 256K IOPS |
| Volume Attachment | `ec2` | `attach-volume`, `detach-volume` | Volumes tied to a single AZ; new volumes need no pre-warming |
| Multi-Attach | `ec2` | `--multi-attach-enabled` on io1/io2 | Up to 16 instances in same AZ; requires clustered FS |
| CloudWatch Metrics | `cloudwatch` | `get-metric-statistics --namespace AWS/EBS` | Watch VolumeQueueLength & BurstBalance for gp2 |
| Volume Status Checks | `ec2` | `describe-volume-status` | ok / impaired; impaired triggers I/O enabled event |
| Live Resize/Modify | `ec2` | `modify-volume --size --iops --throughput` | Zero downtime; wait 6 hrs before next modification |
| Manual Snapshot | `ec2` | `create-snapshot`, `describe-snapshots` | Incremental; each is a full restore point |
| Snapshot Restore | `ec2` | `create-volume --snapshot-id` | First-access latency; mitigate with Fast Snapshot Restore |
| Data Lifecycle Mgr | `dlm` | `create-lifecycle-policy` | Tag-based; automates create/copy/retain/delete |
| AWS Backup Plan | `backup` | `create-backup-plan`, `create-backup-selection` | Multi-service; tag-based; compliance-friendly vault policies |
| Amazon EFS | `efs` | `describe-file-systems` | NFS; multi-AZ; auto-scaling; shared across many instances |
| Amazon FSx | `fsx` | `describe-file-systems` | 4 flavors: Windows/Lustre/ONTAP/OpenZFS |

---

## Timing Guide

```
00:00 - 00:30  Intro — module objectives, scenario recap
00:30 - 04:30  ACT 1 — EBS volume types, create gp3 + io2, attach
04:30 - 07:30  ACT 2 — CloudWatch metrics, status checks, live resize
07:30 - 11:30  ACT 3 — Manual snapshot, DLM lifecycle policy, restore
11:30 - 15:00  ACT 4 — AWS Backup plan, EFS & FSx overview
15:00          Transition to Lab 5 instructions
```

> **Buffer tip:** Acts 3 and 4 have the most "while that's running" moments — use the waiting time to reinforce talking points or field questions. The DLM policy creation and snapshot commands are quick; the AWS Backup plan creation provides a natural pause.

---

## Instructor Notes

- **Lab 5 tie-in:** This demo previews the exact services students will configure in Lab 5 (AWS Backup). Emphasize the tag-based selection strategy — students will use tags in the lab.
- **Common student questions:**
  - *"Can I move an EBS volume to another AZ?"* — Not directly. Take a snapshot, then create a volume from the snapshot in the target AZ.
  - *"What's the difference between DLM and AWS Backup?"* — DLM is EBS-only and lightweight; AWS Backup spans 11+ services and supports compliance/vault lock requirements.
  - *"Does EFS support Windows?"* — No, EFS is NFS-only (Linux). For Windows shared storage, use FSx for Windows File Server (SMB/NTFS).
- **gp2 vs gp3:** gp3 is the current recommendation. gp3 is cheaper per GB and decouples IOPS from capacity (no burst credit bucket to manage). Encourage students to migrate existing gp2 volumes using `modify-volume`.
- **Restore latency:** For the restore command in Act 3, the volume may still say `creating` — that's fine and actually reinforces the talking point about lazy loading from S3.
