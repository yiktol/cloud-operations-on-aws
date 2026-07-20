#!/bin/bash
# Mod-03 - Deploy Setup Stack
set -e
STACK_NAME="mod03-system-discovery-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Use subnet and VPC from CloudFormation exports
SUBNET_ID=$(aws cloudformation list-exports \
  --query "Exports[?Name=='PrivateSubnetOne'].Value" --output text)
VPC_ID=$(aws cloudformation list-exports \
  --query "Exports[?Name=='VpcId'].Value" --output text)

echo "[DEPLOY] Mod-03 Demo Stack..."
echo "  Using subnet: ${SUBNET_ID} (VPC: ${VPC_ID})"
aws cloudformation deploy \
  --template-file "${SCRIPT_DIR}/cfn-setup.yaml" \
  --stack-name ${STACK_NAME} \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides SubnetId=${SUBNET_ID} VpcId=${VPC_ID} \
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

# Ensure S3 bucket policy allows Config to write
echo "[SETUP] Applying Config bucket policy..."
aws s3api put-bucket-policy --bucket ${CONFIG_BUCKET} --policy "{
  \"Version\": \"2012-10-17\",
  \"Statement\": [
    {
      \"Sid\": \"AWSConfigBucketPermissionsCheck\",
      \"Effect\": \"Allow\",
      \"Principal\": {\"Service\": \"config.amazonaws.com\"},
      \"Action\": \"s3:GetBucketAcl\",
      \"Resource\": \"arn:aws:s3:::${CONFIG_BUCKET}\",
      \"Condition\": {\"StringEquals\": {\"AWS:SourceAccount\": \"${ACCOUNT_ID}\"}}
    },
    {
      \"Sid\": \"AWSConfigBucketDelivery\",
      \"Effect\": \"Allow\",
      \"Principal\": {\"Service\": \"config.amazonaws.com\"},
      \"Action\": \"s3:PutObject\",
      \"Resource\": \"arn:aws:s3:::${CONFIG_BUCKET}/AWSLogs/${ACCOUNT_ID}/Config/*\",
      \"Condition\": {\"StringEquals\": {\"s3:x-amz-acl\": \"bucket-owner-full-control\", \"AWS:SourceAccount\": \"${ACCOUNT_ID}\"}}
    }
  ]
}"

aws configservice put-configuration-recorder \
  --configuration-recorder name=default,roleARN=arn:aws:iam::${ACCOUNT_ID}:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig \
  --recording-group allSupported=true,includeGlobalResourceTypes=false 2>/dev/null || true

aws configservice put-delivery-channel \
  --delivery-channel "{\"name\":\"default\",\"s3BucketName\":\"${CONFIG_BUCKET}\"}" 2>/dev/null || true

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

# Trigger immediate inventory collection
ASSOC_ID=$(aws ssm list-associations \
  --query "Associations[?Name=='AWS-GatherSoftwareInventory'].AssociationId" --output text 2>/dev/null)
[ -n "$ASSOC_ID" ] && aws ssm start-associations-once --association-ids ${ASSOC_ID} 2>/dev/null || true

echo ""
echo "[DONE] Setup complete!"
echo "  export INSTANCE_ID=${INSTANCE_ID}"
echo ""
echo "[WAIT] Waiting for SSM agent to register..."
for i in {1..12}; do
  PING=$(aws ssm describe-instance-information \
    --filters "Key=InstanceIds,Values=${INSTANCE_ID}" \
    --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null)
  if [ "$PING" = "Online" ]; then
    echo "  ✓ SSM agent is Online"
    break
  fi
  echo "  Attempt ${i}/12 - waiting 10s..."
  sleep 10
done
if [ "$PING" != "Online" ]; then
  echo "  ⚠ SSM agent not yet online. Check instance networking (NAT Gateway or VPC endpoints required)."
fi
