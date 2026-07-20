#!/bin/bash
# Mod-04 - Cleanup
set -e
STACK_NAME="mod04-deploy-update-demo"

echo "[CLEANUP] Mod-04 Demo..."

# Terminate any instances launched from demo AMIs
echo "[EC2] Terminating instances deployed from Golden AMI..."
DEMO_INSTANCES=$(aws ec2 describe-instances \
  --filters "Name=tag:DeployedFrom,Values=ami-*" "Name=instance-state-name,Values=running,stopped,pending" \
  --query 'Reservations[*].Instances[*].InstanceId' --output text 2>/dev/null) || true
if [ -n "$DEMO_INSTANCES" ] && [ "$DEMO_INSTANCES" != "None" ]; then
  echo "  Terminating: ${DEMO_INSTANCES}"
  aws ec2 terminate-instances --instance-ids ${DEMO_INSTANCES} 2>/dev/null || true
  echo "  Waiting for termination..."
  aws ec2 wait instance-terminated --instance-ids ${DEMO_INSTANCES} 2>/dev/null || true
fi

# Deregister any AMIs and delete snapshots created during demo
echo "[AMI] Deregistering Golden AMIs..."
AMIS=$(aws ec2 describe-images --owners self \
  --filters "Name=name,Values=GoldenAMI-WebServer-*" \
  --query 'Images[*].ImageId' --output text 2>/dev/null) || true
for AMI_ID in $AMIS; do
  if [ -n "$AMI_ID" ] && [ "$AMI_ID" != "None" ]; then
    SNAPS=$(aws ec2 describe-images --image-ids ${AMI_ID} \
      --query 'Images[0].BlockDeviceMappings[*].Ebs.SnapshotId' --output text 2>/dev/null) || true
    echo "  Deregistering: ${AMI_ID}"
    aws ec2 deregister-image --image-id ${AMI_ID} 2>/dev/null || true
    for SNAP in $SNAPS; do
      if [ -n "$SNAP" ] && [ "$SNAP" != "None" ]; then
        echo "  Deleting snapshot: ${SNAP}"
        aws ec2 delete-snapshot --snapshot-id ${SNAP} 2>/dev/null || true
      fi
    done
  fi
done

echo "[RESOURCE-GROUPS] Deleting Dev-Environment group..."
aws resource-groups delete-group --group-name "Dev-Environment" 2>/dev/null || true

echo "[STACK] Deleting CloudFormation stack..."
aws cloudformation delete-stack --stack-name ${STACK_NAME}
aws cloudformation wait stack-delete-complete --stack-name ${STACK_NAME}

echo "[DONE] Cleanup complete!"
