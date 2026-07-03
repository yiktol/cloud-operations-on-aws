#!/bin/bash
# Mod-03 - Deploy Setup Stack
set -e
STACK_NAME="mod03-system-discovery-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[DEPLOY] Mod-03 Demo Stack..."
aws cloudformation deploy \
  --template-file "${SCRIPT_DIR}/cfn-setup.yaml" \
  --stack-name ${STACK_NAME} \
  --capabilities CAPABILITY_NAMED_IAM \
  --no-fail-on-empty-changeset

echo ""
echo "[OUTPUTS]"
aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[*].{Key:OutputKey,Value:OutputValue}' --output table

INSTANCE_ID=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`InstanceId`].OutputValue' --output text)
CONFIG_BUCKET=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`ConfigBucketName`].OutputValue' --output text)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "[SETUP] Enabling AWS Config recording..."
aws configservice put-configuration-recorder \
  --configuration-recorder name=default,roleARN=arn:aws:iam::${ACCOUNT_ID}:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig \
  --recording-group allSupported=true,includeGlobalResourceTypes=false 2>/dev/null || true

aws configservice put-delivery-channel \
  --delivery-channel name=default,s3BucketName=${CONFIG_BUCKET} 2>/dev/null || true

aws configservice start-configuration-recorder --configuration-recorder-name default 2>/dev/null || true

echo "[SETUP] Adding Config rule for SSM management..."
aws configservice put-config-rule --config-rule '{
  "ConfigRuleName": "ec2-instance-managed-by-ssm",
  "Source": {"Owner": "AWS", "SourceIdentifier": "EC2_INSTANCE_MANAGED_BY_SSM"},
  "Scope": {"ComplianceResourceTypes": ["AWS::EC2::Instance"]}
}' 2>/dev/null || true

echo "[SETUP] Setting up SSM Inventory association..."
aws ssm create-association \
  --name "AWS-GatherSoftwareInventory" \
  --targets "Key=InstanceIds,Values=${INSTANCE_ID}" \
  --schedule-expression "rate(30 minutes)" \
  --parameters '{"applications":["Enabled"],"awsComponents":["Enabled"],"networkConfig":["Enabled"]}' \
  2>/dev/null || true

echo ""
echo "[DONE] Setup complete!"
echo "  export INSTANCE_ID=${INSTANCE_ID}"
