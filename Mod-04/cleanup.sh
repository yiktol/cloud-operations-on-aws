#!/bin/bash
# Mod-04 - Cleanup
set -e
STACK_NAME="mod04-deploy-update-demo"

echo "[CLEANUP] Mod-04 Demo..."

# Deregister any AMIs and delete snapshots created during demo
AMIS=$(aws ec2 describe-images --owners self \
  --filters "Name=name,Values=GoldenAMI-WebServer-*" \
  --query 'Images[*].ImageId' --output text 2>/dev/null)
for AMI_ID in $AMIS; do
  SNAP=$(aws ec2 describe-images --image-ids ${AMI_ID} \
    --query 'Images[0].BlockDeviceMappings[0].Ebs.SnapshotId' --output text 2>/dev/null)
  aws ec2 deregister-image --image-id ${AMI_ID} 2>/dev/null || true
  [ -n "$SNAP" ] && aws ec2 delete-snapshot --snapshot-id ${SNAP} 2>/dev/null || true
done

# Terminate any instances launched from demo AMIs
DEMO_INSTANCES=$(aws ec2 describe-instances \
  --filters "Name=tag:DeployedFrom,Values=ami-*" "Name=instance-state-name,Values=running,stopped" \
  --query 'Reservations[*].Instances[*].InstanceId' --output text 2>/dev/null)
[ -n "$DEMO_INSTANCES" ] && aws ec2 terminate-instances --instance-ids ${DEMO_INSTANCES} 2>/dev/null || true

aws resource-groups delete-group --group-name "Dev-Environment" 2>/dev/null || true

echo "[STACK] Deleting CloudFormation stack..."
aws cloudformation delete-stack --stack-name ${STACK_NAME}
aws cloudformation wait stack-delete-complete --stack-name ${STACK_NAME}

echo "[DONE] Cleanup complete!"
