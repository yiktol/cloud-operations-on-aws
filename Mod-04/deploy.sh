#!/bin/bash
# Mod-04 - Deploy Setup Stack
set -e
STACK_NAME="mod04-deploy-update-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[DEPLOY] Mod-04 Demo Stack..."
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

echo "[WAIT] Waiting for instance to be SSM-managed..."
sleep 60

echo "[SETUP] Pre-installing httpd for golden AMI demo..."
aws ssm send-command \
  --instance-ids ${INSTANCE_ID} \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["sudo yum install -y httpd","sudo systemctl enable httpd","echo HealthCheck > /var/www/html/index.html"]' \
  --comment "Pre-install for golden AMI" 2>/dev/null || true

echo "[DONE] Setup complete!"
echo "  export INSTANCE_ID=${INSTANCE_ID}"
