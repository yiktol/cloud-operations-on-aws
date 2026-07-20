#!/bin/bash
# Module 14 - Deploy Setup Stack
set -e
STACK_NAME="mod14-cost-optimization-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ALERT_EMAIL="${1:-placeholder@example.com}"

echo "[DEPLOY] Module 14 Demo Stack..."
echo "  Alert email: ${ALERT_EMAIL}"
aws cloudformation deploy \
  --template-file "${SCRIPT_DIR}/cfn-setup.yaml" \
  --stack-name ${STACK_NAME} \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides "AlertEmail=${ALERT_EMAIL}" \
  --no-fail-on-empty-changeset

echo ""
echo "[OUTPUTS]"
aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[*].{Key:OutputKey,Value:OutputValue}' --output table

echo ""
echo "[DONE] Setup complete!"
echo ""
echo "  Usage: ./deploy.sh your-email@example.com"
echo "  (Confirm the SNS subscription in your email inbox)"
