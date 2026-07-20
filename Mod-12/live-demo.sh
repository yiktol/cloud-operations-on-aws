#!/bin/bash
# Module 12 - Live Demo: Mountable Storage
# Prereq: Run deploy.sh first
set -e

STACK_NAME="mod12-mountable-storage-demo"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

INSTANCE_ID=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`InstanceId`].OutputValue' --output text)
VOLUME_ID=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`VolumeId`].OutputValue' --output text)
AZ=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`InstanceAZ`].OutputValue' --output text)
BACKUP_ROLE=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`BackupRoleArn`].OutputValue' --output text)
DLM_ROLE=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`DLMRoleArn`].OutputValue' --output text)

echo "========================================"
echo " Module 12: Mountable Storage"
echo " Instance: ${INSTANCE_ID}"
echo " Volume: ${VOLUME_ID} (AZ: ${AZ})"
echo "========================================"
echo ""

# --- ACT 1: EBS Volume - Attach and Inspect ---
echo "--- ACT 1: EBS Volume - Attach and Inspect ---"
echo ""

# Show volume details
echo "[1.1] Volume details (gp3, unattached):"
aws ec2 describe-volumes --volume-ids ${VOLUME_ID} \
  --query 'Volumes[0].{State:State,Type:VolumeType,IOPS:Iops,Throughput:Throughput,Size:Size}' \
  --output table
echo ""

# Attach the volume to the instance
echo "[1.2] Attaching volume to instance..."
aws ec2 attach-volume \
  --volume-id ${VOLUME_ID} \
  --instance-id ${INSTANCE_ID} \
  --device /dev/xvdf \
  --query '{State:State,Device:Device}' --output table
echo ""

echo "[1.3] Waiting for attachment..."
aws ec2 wait volume-in-use --volume-ids ${VOLUME_ID}
aws ec2 describe-volumes --volume-ids ${VOLUME_ID} \
  --query 'Volumes[0].{State:State,AttachState:Attachments[0].State}' \
  --output table
echo ""

# Format and mount the volume via SSM
echo "[1.4] Formatting and mounting via SSM..."
CMD_ID=$(aws ssm send-command \
  --instance-ids ${INSTANCE_ID} \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["sudo mkfs -t xfs /dev/xvdf","sudo mkdir -p /data","sudo mount /dev/xvdf /data","df -h /data"]' \
  --query Command.CommandId --output text)
sleep 15
aws ssm get-command-invocation \
  --command-id ${CMD_ID} --instance-id ${INSTANCE_ID} \
  --query 'StandardOutputContent' --output text
echo ""

# --- ACT 2: Snapshot + DLM Backup Policy ---
echo "--- ACT 2: Snapshots & Data Lifecycle Manager ---"
echo ""

# Create a manual snapshot
echo "[2.1] Creating manual snapshot..."
SNAPSHOT_ID=$(aws ec2 create-snapshot \
  --volume-id ${VOLUME_ID} \
  --description "Demo snapshot" \
  --tag-specifications 'ResourceType=snapshot,Tags=[{Key=Name,Value=Demo-Snapshot-Manual}]' \
  --query SnapshotId --output text)
echo "  Snapshot: ${SNAPSHOT_ID}"
echo ""

# Show snapshot status
echo "[2.2] Snapshot status:"
aws ec2 describe-snapshots --snapshot-ids ${SNAPSHOT_ID} \
  --query 'Snapshots[0].{ID:SnapshotId,State:State,Progress:Progress}' \
  --output table
echo ""

# Create DLM policy for automated daily snapshots
echo "[2.3] Creating DLM lifecycle policy (daily, 7-day retention)..."
aws dlm create-lifecycle-policy \
  --description "Demo-EBS-Backup" \
  --state ENABLED \
  --execution-role-arn "${DLM_ROLE}" \
  --policy-details '{
    "PolicyType": "EBS_SNAPSHOT_MANAGEMENT",
    "ResourceTypes": ["VOLUME"],
    "TargetTags": [{"Key": "Backup", "Value": "true"}],
    "Schedules": [{
      "Name": "DailySnapshots",
      "CreateRule": {"Interval": 24, "IntervalUnit": "HOURS", "Times": ["03:00"]},
      "RetainRule": {"Count": 7},
      "CopyTags": true
    }]
  }' --query 'PolicyId' --output text 2>/dev/null || echo "  (DLM policy may already exist)"
echo ""

# --- ACT 3: AWS Backup - Centralized Policy ---
echo "--- ACT 3: AWS Backup - Centralized Policy ---"
echo ""

# Get or create the Default backup vault
echo "[3.1] Ensuring backup vault exists:"
aws backup create-backup-vault --backup-vault-name Default 2>/dev/null || true
aws backup list-backup-vaults \
  --query 'BackupVaultList[*].{Name:BackupVaultName,RecoveryPoints:NumberOfRecoveryPoints}' \
  --output table
VAULT="Default"
echo ""

# Create a backup plan
echo "[3.2] Creating backup plan (daily, 30-day retention)..."
PLAN_ID=$(aws backup create-backup-plan --backup-plan '{
  "BackupPlanName": "Demo-DailyBackupPlan",
  "Rules": [{
    "RuleName": "DailyBackups",
    "TargetBackupVaultName": "'"${VAULT}"'",
    "ScheduleExpression": "cron(0 3 * * ? *)",
    "StartWindowMinutes": 60,
    "CompletionWindowMinutes": 180,
    "Lifecycle": {"DeleteAfterDays": 30}
  }]
}' --query 'BackupPlanId' --output text)
echo "  Plan ID: ${PLAN_ID}"
echo ""

# Select all resources tagged Backup=true
echo "[3.3] Assigning tag-based resource selection (Backup=true)..."
aws backup create-backup-selection \
  --backup-plan-id ${PLAN_ID} \
  --backup-selection '{
    "SelectionName": "TaggedResources",
    "IamRoleArn": "'"${BACKUP_ROLE}"'",
    "ListOfTags": [{"ConditionType": "STRINGEQUALS", "ConditionKey": "Backup", "ConditionValue": "true"}]
  }' --query 'SelectionId' --output text
echo ""

echo "========================================"
echo " Demo Complete!"
echo "========================================"
