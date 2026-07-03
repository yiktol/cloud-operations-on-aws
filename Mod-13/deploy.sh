#!/bin/bash
# Module 13 - Deploy Setup Stack
set -e
STACK_NAME="mod13-object-storage-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[DEPLOY] Module 13 Demo Stack..."
aws cloudformation deploy \
  --template-file "${SCRIPT_DIR}/cfn-setup.yaml" \
  --stack-name ${STACK_NAME} \
  --capabilities CAPABILITY_NAMED_IAM \
  --no-fail-on-empty-changeset

echo ""
echo "[OUTPUTS]"
aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[*].{Key:OutputKey,Value:OutputValue}' --output table

BUCKET=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' --output text)

# Upload sample files
echo "Current transaction data - accessed frequently" | aws s3 cp - s3://${BUCKET}/transactions/today.txt
echo "Last months report - accessed occasionally" | aws s3 cp - s3://${BUCKET}/reports/monthly-report.txt
echo "Archived audit log from 2 years ago" | aws s3 cp - s3://${BUCKET}/archive/audit-2024.txt

echo ""
echo "[DONE] Bucket created and seeded with sample files: ${BUCKET}"
