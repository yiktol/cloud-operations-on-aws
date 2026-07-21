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
| Module 12 CFN stack | Deployed (`Mod-12/cfn-setup.yaml`) |

---

## Setup (Before Class)

### Deploy the CloudFormation stack
The stack creates: EC2 instance with SSM access, a gp3 demo volume, IAM roles for AWS Backup and DLM.

```bash
aws cloudformation deploy \
  --template-file Mod-12/cfn-setup.yaml \
  --stack-name mod12-demo \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    SubnetId=<your-subnet-id> \
    VpcId=<your-vpc-id>
```

### Get resource IDs for the demo
```bash
export INSTANCE_ID=$(aws cloudformation describe-stacks --stack-name mod12-demo --query "Stacks[0].Outputs[?OutputKey=='InstanceId'].OutputValue" --output text)
export DEMO_VOL=$(aws cloudformation describe-stacks --stack-name mod12-demo --query "Stacks[0].Outputs[?OutputKey=='VolumeId'].OutputValue" --output text)
export AZ=$(aws cloudformation describe-stacks --stack-name mod12-demo --query "Stacks[0].Outputs[?OutputKey=='InstanceAZ'].OutputValue" --output text)
export BACKUP_ROLE_ARN=$(aws cloudformation describe-stacks --stack-name mod12-demo --query "Stacks[0].Outputs[?OutputKey=='BackupRoleArn'].OutputValue" --output text)
export DLM_ROLE_ARN=$(aws cloudformation describe-stacks --stack-name mod12-demo --query "Stacks[0].Outputs[?OutputKey=='DLMRoleArn'].OutputValue" --output text)
export AWS_DEFAULT_REGION="ap-southeast-1"

echo "Using instance: ${INSTANCE_ID} in ${AZ}"
echo "Demo volume: ${DEMO_VOL}"
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

#### Talking Points

> *"Amazon EBS is network-attached, persistent block storage. Unlike instance store, which disappears when you stop or terminate an instance, EBS persists independently."*
>
> *"A critical rule: EBS volumes are tied to a single Availability Zone."*

#### Commands

```bash
# ── 1a. Show existing volumes and their types
aws ec2 describe-volumes \
  --volume-ids ${DEMO_VOL} \
  --query "Volumes[*].{ID:VolumeId,Type:VolumeType,Size:Size,IOPS:Iops,State:State,AZ:AvailabilityZone}" \
  --output table
```

> 💬 *"Notice our gp3 volume. A gp3 gives you 3,000 baseline IOPS and 125 MiBps included — no burst credits, predictable performance."*

```bash
# ── 1b. Compare: create a higher-performance io2 volume
export IO2_VOL=$(aws ec2 create-volume \
  --availability-zone "${AZ}" \
  --volume-type io2 \
  --size 10 \
  --iops 5000 \
  --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value=demo-mod12-io2},{Key=Env,Value=demo}]' \
  --query "VolumeId" --output text)

echo "io2 volume: ${IO2_VOL}"
```

```bash
# ── 1c. Attach the gp3 volume to the running instance
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

---

### Act 2 — Monitoring with CloudWatch & Volume Resizing (~3 min)

#### Commands

```bash
# ── 2a. Pull recent CloudWatch metrics for our volume
ENDTIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
STARTTIME=$(date -u -v-1H +"%Y-%m-%dT%H:%M:%SZ")

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

```bash
# ── 2b. Check EBS volume status
aws ec2 describe-volume-status \
  --volume-ids "${DEMO_VOL}" \
  --query "VolumeStatuses[0].{VolumeStatus:VolumeStatus.Status,IOEnabled:VolumeStatus.Details[0].Status}" \
  --output table
```

```bash
# ── 2c. Resize the volume live (10 GiB → 40 GiB, bump IOPS to 6000)
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

> 💬 *"Zero downtime. The OS still sees the old size until you run `growpart`. And once you modify a volume, wait at least 6 hours before modifying it again."*

---

### Act 3 — Snapshots & Data Lifecycle Manager (~4 min)

```bash
# ── 3a. Create a manual snapshot
export SNAP_ID=$(aws ec2 create-snapshot \
  --volume-id "${DEMO_VOL}" \
  --description "Module 12 demo snapshot" \
  --tag-specifications 'ResourceType=snapshot,Tags=[{Key=Name,Value=demo-snap-mod12},{Key=Env,Value=demo}]' \
  --query "SnapshotId" --output text)

echo "Snapshot initiated: ${SNAP_ID}"

aws ec2 describe-snapshots \
  --snapshot-ids "${SNAP_ID}" \
  --query "Snapshots[0].{ID:SnapshotId,State:State,Progress:Progress,StartTime:StartTime}" \
  --output table
```

```bash
# ── 3b. Create a DLM lifecycle policy for daily snapshots
aws dlm create-lifecycle-policy \
  --description "Demo: daily EBS snapshot, 7-day retention" \
  --state ENABLED \
  --execution-role-arn "${DLM_ROLE_ARN}" \
  --policy-details '{
    "PolicyType": "EBS_SNAPSHOT_MANAGEMENT",
    "ResourceTypes": ["VOLUME"],
    "TargetTags": [{"Key": "Backup", "Value": "true"}],
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

```bash
# ── 3c. Restore a snapshot to a new volume
export RESTORED_VOL=$(aws ec2 create-volume \
  --availability-zone "${AZ}" \
  --snapshot-id "${SNAP_ID}" \
  --volume-type gp3 \
  --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value=demo-restored},{Key=Env,Value=demo}]' \
  --query "VolumeId" --output text)

echo "Restored volume: ${RESTORED_VOL}"
```

---

### Act 4 — AWS Backup & Shared Storage (EFS / FSx) (~4 min)

```bash
# ── 4a. List existing AWS Backup vaults
aws backup list-backup-vaults \
  --query "BackupVaultList[*].{Name:BackupVaultName,ARN:BackupVaultArn,RecoveryPoints:NumberOfRecoveryPoints}" \
  --output table
```

```bash
# ── 4b. Create a demo backup plan
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

```bash
# ── 4c. Assign resources to the backup plan via tags
aws backup create-backup-selection \
  --backup-plan-id "${BACKUP_PLAN_ID}" \
  --backup-selection '{
    "SelectionName": "DemoVolumes",
    "IamRoleArn": "'"${BACKUP_ROLE_ARN}"'",
    "ListOfTags": [{
      "ConditionType": "STRINGEQUALS",
      "ConditionKey": "Backup",
      "ConditionValue": "true"
    }]
  }' \
  --query "SelectionId" --output text
```

```bash
# ── 4d. Show EFS and FSx file systems (shared storage overview)
aws efs describe-file-systems \
  --query "FileSystems[*].{ID:FileSystemId,Name:Name,State:LifeCycleState,Throughput:ThroughputMode}" \
  --output table

aws fsx describe-file-systems \
  --query "FileSystems[*].{ID:FileSystemId,Type:FileSystemType,State:Lifecycle,StorageGiB:StorageCapacityGiB}" \
  --output table 2>/dev/null || echo "(No FSx file systems in this account/region)"
```

---

## Cleanup

```bash
# Detach the demo volume
aws ec2 detach-volume --volume-id "${DEMO_VOL}"
aws ec2 wait volume-available --volume-ids "${DEMO_VOL}"

# Delete DLM lifecycle policy
aws dlm get-lifecycle-policies \
  --query "Policies[?Description=='Demo: daily EBS snapshot, 7-day retention'].PolicyId" \
  --output text | xargs -I {} aws dlm delete-lifecycle-policy --policy-id {}

# Delete AWS Backup plan
SELECTION_ID=$(aws backup list-backup-selections \
  --backup-plan-id "${BACKUP_PLAN_ID}" \
  --query "BackupSelectionsList[0].SelectionId" --output text)
aws backup delete-backup-selection --backup-plan-id "${BACKUP_PLAN_ID}" --selection-id "${SELECTION_ID}"
aws backup delete-backup-plan --backup-plan-id "${BACKUP_PLAN_ID}"

# Delete snapshots and volumes
aws ec2 delete-snapshot --snapshot-id "${SNAP_ID}"
aws ec2 delete-volume --volume-id "${IO2_VOL}" 2>/dev/null || true
aws ec2 delete-volume --volume-id "${RESTORED_VOL}" 2>/dev/null || true

# Delete the stack (removes instance, demo volume, IAM roles)
aws cloudformation delete-stack --stack-name mod12-demo
```

---

## Summary Table

| Concept | Key Command(s) | Key Talking Point |
|---|---|---|
| EBS Volume Types | `create-volume --volume-type gp3\|io2` | gp3 = 3K IOPS baseline; io2 = provisioned up to 256K IOPS |
| Volume Attachment | `attach-volume`, `detach-volume` | Volumes tied to a single AZ |
| Live Resize/Modify | `modify-volume --size --iops --throughput` | Zero downtime; wait 6 hrs before next modification |
| Manual Snapshot | `create-snapshot` | Incremental; each is a full restore point |
| Data Lifecycle Mgr | `create-lifecycle-policy` | Tag-based; automates create/retain/delete |
| AWS Backup Plan | `create-backup-plan` | Multi-service; tag-based; compliance-friendly |
| Amazon EFS | `describe-file-systems` | NFS; multi-AZ; auto-scaling; shared across instances |
| Amazon FSx | `describe-file-systems` | 4 flavors: Windows/Lustre/ONTAP/OpenZFS |

---

## Timing Guide

| Segment | Time |
|---------|------|
| Act 1 — EBS volume types, attach | ~4 min |
| Act 2 — CloudWatch metrics, live resize | ~3 min |
| Act 3 — Snapshot, DLM policy, restore | ~4 min |
| Act 4 — AWS Backup, EFS & FSx overview | ~4 min |
| **Total** | **~15 min** |
