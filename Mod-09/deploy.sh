#!/bin/bash
# Mod-09 - Deploy Setup Stack
set -e
STACK_NAME="mod09-monitoring-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[DEPLOY] Mod-09 Demo Stack..."
aws cloudformation deploy \
  --template-file "${SCRIPT_DIR}/cfn-setup.yaml" \
  --stack-name ${STACK_NAME} \
  --capabilities CAPABILITY_NAMED_IAM \
  --no-fail-on-empty-changeset

echo ""
echo "[OUTPUTS]"
aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[*].{Key:OutputKey,Value:OutputValue}' --output table

INSTANCE_ID=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`InstanceId`].OutputValue' --output text)
echo "[WAIT] Waiting for SSM agent (60s)..."
sleep 60

echo "[SETUP] Generating sample log data..."
aws ssm send-command \
  --instance-ids ${INSTANCE_ID} \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=[
    "for i in $(seq 1 30); do logger -t demo-app INFO: Request processed: status=200; done",
    "for i in $(seq 1 5); do logger -t demo-app ERROR: Connection timeout; done"
  ]' 2>/dev/null || true

echo "[DONE] Setup complete! export INSTANCE_ID=${INSTANCE_ID}"
