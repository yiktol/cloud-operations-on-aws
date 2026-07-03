#!/bin/bash
# Mod-11 - Deploy Setup Stack
set -e
STACK_NAME="mod11-secure-networks-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[DEPLOY] Mod-11 Demo Stack..."
aws cloudformation deploy \
  --template-file "${SCRIPT_DIR}/cfn-setup.yaml" \
  --stack-name ${STACK_NAME} \
  --capabilities CAPABILITY_NAMED_IAM \
  --no-fail-on-empty-changeset

echo ""
echo "[OUTPUTS]"
aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[*].{Key:OutputKey,Value:OutputValue}' --output table

FLOW_LOGS_ROLE=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`FlowLogsRoleArn`].OutputValue' --output text)
echo "[DONE] Setup complete! Flow Logs IAM role ready."
echo "  export FLOW_LOGS_ROLE=${FLOW_LOGS_ROLE}"
