#!/bin/bash
# Module 02 - Cleanup
set -e
STACK_NAME="mod02-access-management-demo"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "[CLEANUP] Module 02 Demo..."

# Empty buckets
GENERAL_BUCKET=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`GeneralBucketName`].OutputValue' --output text 2>/dev/null)
CONFIDENTIAL_BUCKET=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`ConfidentialBucketName`].OutputValue' --output text 2>/dev/null)

[ -n "$GENERAL_BUCKET" ] && aws s3 rm s3://${GENERAL_BUCKET} --recursive 2>/dev/null || true
[ -n "$CONFIDENTIAL_BUCKET" ] && aws s3 rm s3://${CONFIDENTIAL_BUCKET} --recursive 2>/dev/null || true

# Detach policies attached during demo
aws iam detach-user-policy --user-name demo-user --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/AllowS3Read-Demo 2>/dev/null || true
aws iam detach-user-policy --user-name demo-user --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/DenyConfidentialBucket-Demo 2>/dev/null || true
aws iam detach-user-policy --user-name demo-user --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/AllowAssumeEmergencyRole-Demo 2>/dev/null || true

# Delete stack
aws cloudformation delete-stack --stack-name ${STACK_NAME}
aws cloudformation wait stack-delete-complete --stack-name ${STACK_NAME}

echo "[DONE] Cleanup complete!"
