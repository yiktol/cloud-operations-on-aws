#!/bin/bash
# Mod-03 - Cleanup
set -e
STACK_NAME="mod03-system-discovery-demo"

echo "[CLEANUP] Mod-03 Demo..."

# Get stack outputs (may fail if stack doesn't exist)
INSTANCE_ID=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`InstanceId`].OutputValue' --output text 2>/dev/null) || true
CONFIG_BUCKET=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`ConfigBucketName`].OutputValue' --output text 2>/dev/null) || true

echo "[CONFIG] Removing Config rule..."
aws configservice delete-config-rule --config-rule-name ec2-instance-managed-by-ssm 2>/dev/null || true

echo "[CONFIG] Stopping Config recorder..."
aws configservice stop-configuration-recorder --configuration-recorder-name default 2>/dev/null || true

echo "[SSM] Removing inventory association..."
ASSOC_IDS=$(aws ssm list-associations \
  --query "Associations[?Name=='AWS-GatherSoftwareInventory'].AssociationId" \
  --output text 2>/dev/null) || true
for ASSOC_ID in ${ASSOC_IDS}; do
  [ -n "$ASSOC_ID" ] && aws ssm delete-association --association-id ${ASSOC_ID} 2>/dev/null || true
done

echo "[S3] Emptying Config bucket..."
if [ -n "$CONFIG_BUCKET" ] && [ "$CONFIG_BUCKET" != "None" ]; then
  aws s3 rm s3://${CONFIG_BUCKET} --recursive 2>/dev/null || true
fi

echo "[STACK] Deleting CloudFormation stack..."
aws cloudformation delete-stack --stack-name ${STACK_NAME}
aws cloudformation wait stack-delete-complete --stack-name ${STACK_NAME}

echo "[DONE] Cleanup complete!"
