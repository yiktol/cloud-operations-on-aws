#!/bin/bash
# Mod-05 - Cleanup
set -e
STACK_NAME="mod05-automate-deployment-demo"

echo "[CLEANUP] Mod-05 Demo..."

# Delete the demo webapp stack if still running
aws cloudformation delete-stack --stack-name demo-webapp-dev 2>/dev/null || true
aws cloudformation wait stack-delete-complete --stack-name demo-webapp-dev 2>/dev/null || true

TEMPLATE_BUCKET=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`TemplateBucketName`].OutputValue' --output text 2>/dev/null)
[ -n "$TEMPLATE_BUCKET" ] && aws s3 rm s3://${TEMPLATE_BUCKET} --recursive 2>/dev/null || true

echo "[STACK] Deleting CloudFormation stack..."
aws cloudformation delete-stack --stack-name ${STACK_NAME}
aws cloudformation wait stack-delete-complete --stack-name ${STACK_NAME}

echo "[DONE] Cleanup complete!"
