#!/bin/bash
# Module 12 - Live Demo: "Mountable Storage"
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

echo "============================================"
echo "  ACT 1: EBS VOLUME - Attach and Inspect"
echo "============================================"
read -p "Press Enter..."

echo ">> Volume details (gp3, not yet attached)..."
aws ec2 describe-volumes --volume-ids ${VOLUME_ID} \
  --query 'Volumes[0].{State:State,Type:VolumeType,IOPS:Iops,Throughput:Throughput,Size:Size}' \
  --output table

read -p "Press Enter to attach the volume to the instance..."
aws ec2 attach-volume \
  --volume-id ${VOLUME_ID} \
  --instance-id ${INSTANCE_ID} \
  --device /dev/xvdf

echo "Waiting for attachment..."
aws ec2 wait volume-in-use --volume-ids ${VOLUME_ID}

aws ec2 describe-volumes --volume-ids ${VOLUME_ID} \
  --query 'Volumes[0].{State:State,Attachments:Attachments[0].State}' \
  --output table

echo ""
echo ">> Format and mount (via SSM)..."
aws ssm send-command \
  --instance-ids ${INSTANCE_ID} \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["sudo mkfs -t xfs /dev/xvdf","sudo mkdir -p /data","sudo mount /dev/xvdf /data","df -h /data"]' \
  --query Command.CommandId --output text > /tmp/cmd_id.txt
sleep 15
aws ssm get-command-invocation \
  --command-id $(cat /tmp/cmd_id.txt) --instance-id ${INSTANCE_ID} \
  --query 'StandardOutputContent' --output text

echo "[RESULT] gp3 = baseline 3000 IOPS + 125 MB/s free. Modify IOPS without downtime."
echo ""

echo "============================================"
echo "  ACT 2: SNAPSHOT + DLM BACKUP POLICY"
echo "============================================"
read -p "Press Enter..."

SNAPSHOT_ID=$(aws ec2 create-snapshot \
  --volume-id ${VOLUME_ID} \
  --description "Demo snapshot" \
  --tag-specifications 'ResourceType=snapshot,Tags=[{Key=Name,Value=Demo-Snapshot-Manual}]' \
  --query SnapshotId --output text)
echo "Snapshot started: ${SNAPSHOT_ID}"

# Create DLM policy (automated daily snapshots)
aws dlm create-lifecycle-policy \
  --description "Demo-EBS-Backup" \
  --state ENABLED \
  --execution-role-arn "arn:aws:iam::${ACCOUNT_ID}:role/AWSDataLifecycleManagerDefaultRole" \
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
  }' 2>/dev/null && echo "DLM policy created: daily snapshots, 7-day retention" || \
  echo "(DLM default role may need to be created first - see AWS docs)"

echo "[RESULT] Snapshots = incremental, stored in S3, cross-region copyable."
echo ""

echo "============================================"
echo "  ACT 3: AWS BACKUP - Centralized Policy"
echo "============================================"
read -p "Press Enter..."

VAULT=$(aws backup list-backup-vaults --query 'BackupVaultList[0].BackupVaultName' --output text)

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

aws backup create-backup-selection \
  --backup-plan-id ${PLAN_ID} \
  --backup-selection '{
    "SelectionName": "TaggedResources",
    "IamRoleArn": "'"${BACKUP_ROLE}"'",
    "ListOfTags": [{"ConditionType": "STRINGEQUALS", "ConditionKey": "Backup", "ConditionValue": "true"}]
  }'

echo "Backup plan created: ${PLAN_ID}"
echo "ALL resources tagged Backup=true are now protected."
echo "[RESULT] AWS Backup = one policy protects EC2, EBS, RDS, EFS, DynamoDB."
echo ""
echo "============ DEMO COMPLETE ============"
