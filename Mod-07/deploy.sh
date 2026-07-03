#!/bin/bash
# Mod-07 - Deploy Setup Stack
set -e
STACK_NAME="mod07-high-availability-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[DEPLOY] Mod-07 Demo Stack..."
aws cloudformation deploy \
  --template-file "${SCRIPT_DIR}/cfn-setup.yaml" \
  --stack-name ${STACK_NAME} \
  --capabilities CAPABILITY_NAMED_IAM \
  --no-fail-on-empty-changeset

echo ""
echo "[OUTPUTS]"
aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[*].{Key:OutputKey,Value:OutputValue}' --output table

echo "[DONE] Setup complete! Instances are bootstrapping (httpd via user-data, ~60s)."
INSTANCE_1=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`Instance1Id`].OutputValue' --output text)
INSTANCE_2=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`Instance2Id`].OutputValue' --output text)
echo "  export INSTANCE_1=${INSTANCE_1}"
echo "  export INSTANCE_2=${INSTANCE_2}"
