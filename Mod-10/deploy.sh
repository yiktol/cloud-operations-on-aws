#!/bin/bash
# Mod-10 - Deploy Setup Stack
set -e
STACK_NAME="mod10-security-auditing-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[DEPLOY] Mod-10 Demo Stack..."
aws cloudformation deploy \
  --template-file "${SCRIPT_DIR}/cfn-setup.yaml" \
  --stack-name ${STACK_NAME} \
  --capabilities CAPABILITY_NAMED_IAM \
  --no-fail-on-empty-changeset

echo ""
echo "[OUTPUTS]"
aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[*].{Key:OutputKey,Value:OutputValue}' --output table

TOPIC_ARN=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`SecurityAlertsTopicArn`].OutputValue' --output text)

echo ""
echo "[DONE] Setup complete!"
echo "  export TOPIC_ARN=${TOPIC_ARN}"
echo ""
echo "  (Optional) Subscribe to alerts:"
echo "  aws sns subscribe --topic-arn ${TOPIC_ARN} --protocol email --notification-endpoint YOUR_EMAIL"
