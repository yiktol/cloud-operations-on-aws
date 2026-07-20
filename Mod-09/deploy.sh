#!/bin/bash
# Mod-09 - Deploy Setup Stack
set -e
STACK_NAME="mod09-monitoring-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Use subnet and VPC from CloudFormation exports
SUBNET_ID=$(aws cloudformation list-exports \
  --query "Exports[?Name=='PrivateSubnetOne'].Value" --output text)
VPC_ID=$(aws cloudformation list-exports \
  --query "Exports[?Name=='VpcId'].Value" --output text)

echo "[DEPLOY] Mod-09 Demo Stack..."
echo "  Using subnet: ${SUBNET_ID} (VPC: ${VPC_ID})"
aws cloudformation deploy \
  --template-file "${SCRIPT_DIR}/cfn-setup.yaml" \
  --stack-name ${STACK_NAME} \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides SubnetId=${SUBNET_ID} VpcId=${VPC_ID} \
  --no-fail-on-empty-changeset

echo ""
echo "[OUTPUTS]"
aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[*].{Key:OutputKey,Value:OutputValue}' --output table

INSTANCE_ID=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`InstanceId`].OutputValue' --output text)

echo ""
echo "[WAIT] Waiting for SSM agent to register..."
for i in {1..12}; do
  PING=$(aws ssm describe-instance-information \
    --filters "Key=InstanceIds,Values=${INSTANCE_ID}" \
    --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null)
  if [ "$PING" = "Online" ]; then
    echo "  ✓ SSM agent is Online"
    break
  fi
  echo "  Attempt ${i}/12 - waiting 10s..."
  sleep 10
done
if [ "$PING" != "Online" ]; then
  echo "  ⚠ SSM agent not yet online."
  exit 1
fi

echo ""
echo "[SETUP] Generating sample log data on instance..."
aws ssm send-command \
  --instance-ids ${INSTANCE_ID} \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["for i in $(seq 1 30); do logger -t demo-app INFO: Request processed status=200; done","for i in $(seq 1 5); do logger -t demo-app ERROR: Connection timeout; done"]' \
  --comment "Generate sample logs" \
  --query 'Command.CommandId' --output text 2>/dev/null || true

echo ""
echo "[DONE] Setup complete!"
echo "  export INSTANCE_ID=${INSTANCE_ID}"
