#!/bin/bash
# Module 14 - Deploy Setup Stack
set -e
STACK_NAME="mod14-cost-optimization-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

read -p "Enter your email for cost alerts (or press Enter to skip): " ALERT_EMAIL
ALERT_EMAIL=${ALERT_EMAIL:-"placeholder@example.com"}

echo "[DEPLOY] Module 14 Demo Stack (SNS topic for cost alerts)..."
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
echo "[INFO] Pre-class checklist:"
echo "  1. Enable Compute Optimizer (Settings > Opt in) - takes 24h to generate recommendations"
echo "  2. Enable Cost Explorer (Billing > Cost Explorer) if not already active"
echo "  3. Enable billing alerts in Billing preferences > Billing Alerts"
echo "  4. Confirm SNS subscription in your email inbox"
echo ""
echo "[DONE] Setup complete!"
