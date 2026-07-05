#!/bin/bash
# Module 01 - Deploy Setup Stack (Well-Architected workload)
set -e
STACK_NAME="mod01-cloud-operations-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[DEPLOY] Module 01 Demo Stack..."
aws cloudformation deploy \
  --template-file "${SCRIPT_DIR}/cfn-setup.yaml" \
  --stack-name ${STACK_NAME} \
  --no-fail-on-empty-changeset

echo ""
echo "[OUTPUTS]"
aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[*].{Key:OutputKey,Value:OutputValue}' --output table

WORKLOAD_ID=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`WorkloadId`].OutputValue' --output text)

echo ""
echo "[DONE] Setup complete!"
echo "   Workload ID: ${WORKLOAD_ID}"
echo "   Note: The Well-Architected Tool is free - no resource costs."
