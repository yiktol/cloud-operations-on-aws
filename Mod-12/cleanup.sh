#!/bin/bash
# Module 12 - Cleanup
set -e
STACK_NAME="mod12-mountable-storage-demo"

echo "[CLEANUP] Module 12 Demo..."

INSTANCE_ID=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`InstanceId`].OutputValue' --output text 2>/dev/null) || true
VOLUME_ID=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`VolumeId`].OutputValue' --output text 2>/dev/null) || true

# Detach volume if attached
echo "[EBS] Detaching volume..."
if [ -n "$VOLUME_ID" ] && [ "$VOLUME_ID" != "None" ]; then
  aws ec2 detach-volume --volume-id ${VOLUME_ID} 2>/dev/null || true
  sleep 10
fi

# Delete DLM policy
echo "[DLM] Deleting lifecycle policy..."
DLM_ID=$(aws dlm get-lifecycle-policies \
  --query "Policies[?Description=='Demo-EBS-Backup'].PolicyId" \
  --output text 2>/dev/null) || true
if [ -n "$DLM_ID" ] && [ "$DLM_ID" != "None" ]; then
  aws dlm delete-lifecycle-policy --policy-id ${DLM_ID} 2>/dev/null || true
fi

# Delete AWS Backup plan
echo "[BACKUP] Deleting backup plan..."
PLAN_ID=$(aws backup list-backup-plans \
  --query "BackupPlansList[?BackupPlanName=='Demo-DailyBackupPlan'].BackupPlanId" \
  --output text 2>/dev/null) || true
if [ -n "$PLAN_ID" ] && [ "$PLAN_ID" != "None" ]; then
  # Must delete selections first
  SEL_IDS=$(aws backup list-backup-selections --backup-plan-id ${PLAN_ID} \
    --query 'BackupSelectionsList[*].SelectionId' --output text 2>/dev/null) || true
  for SEL_ID in $SEL_IDS; do
    [ -n "$SEL_ID" ] && [ "$SEL_ID" != "None" ] && \
      aws backup delete-backup-selection --backup-plan-id ${PLAN_ID} --selection-id ${SEL_ID} 2>/dev/null || true
  done
  aws backup delete-backup-plan --backup-plan-id ${PLAN_ID} 2>/dev/null || true
fi

# Delete demo snapshots
echo "[SNAP] Deleting demo snapshots..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
SNAP_IDS=$(aws ec2 describe-snapshots --owner-ids ${ACCOUNT_ID} \
  --filters "Name=tag:Name,Values=Demo-Snapshot*" \
  --query 'Snapshots[*].SnapshotId' --output text 2>/dev/null) || true
for SID in $SNAP_IDS; do
  [ -n "$SID" ] && [ "$SID" != "None" ] && aws ec2 delete-snapshot --snapshot-id ${SID} 2>/dev/null || true
done

# Delete stack
echo "[STACK] Deleting CloudFormation stack..."
aws cloudformation delete-stack --stack-name ${STACK_NAME}
aws cloudformation wait stack-delete-complete --stack-name ${STACK_NAME}

echo "[DONE] Cleanup complete!"
