#!/bin/bash
# Module 02 - Deploy Setup Stack
set -e
STACK_NAME="mod02-access-management-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[DEPLOY] Module 02 Demo Stack..."
aws cloudformation deploy \
  --template-file "${SCRIPT_DIR}/cfn-setup.yaml" \
  --stack-name ${STACK_NAME} \
  --capabilities CAPABILITY_NAMED_IAM \
  --no-fail-on-empty-changeset

echo ""
echo "[OUTPUTS]"
aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[*].{Key:OutputKey,Value:OutputValue}' --output table

# Upload sample files
GENERAL_BUCKET=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`GeneralBucketName`].OutputValue' --output text)
CONFIDENTIAL_BUCKET=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`ConfidentialBucketName`].OutputValue' --output text)

echo "This is general data." | aws s3 cp - s3://${GENERAL_BUCKET}/general-file.txt
echo "This is CONFIDENTIAL data." | aws s3 cp - s3://${CONFIDENTIAL_BUCKET}/secret-file.txt

# Configure demo-user CLI profile
ACCESS_KEY=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`DemoUserAccessKeyId`].OutputValue' --output text)
SECRET_KEY=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`DemoUserSecretKey`].OutputValue' --output text)
REGION=$(aws configure get region)

aws configure set aws_access_key_id ${ACCESS_KEY} --profile demo-user
aws configure set aws_secret_access_key ${SECRET_KEY} --profile demo-user
aws configure set region ${REGION} --profile demo-user

echo ""
echo "[DONE] Setup complete! demo-user CLI profile configured."
