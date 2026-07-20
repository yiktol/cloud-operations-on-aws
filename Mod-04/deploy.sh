#!/bin/bash
# Mod-04 - Deploy Setup Stack
set -e
STACK_NAME="mod04-deploy-update-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Use subnet and VPC from CloudFormation exports
SUBNET_ID=$(aws cloudformation list-exports \
  --query "Exports[?Name=='PrivateSubnetOne'].Value" --output text)
VPC_ID=$(aws cloudformation list-exports \
  --query "Exports[?Name=='VpcId'].Value" --output text)

echo "[DEPLOY] Mod-04 Demo Stack..."
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
  echo "  ⚠ SSM agent not yet online. Check instance networking."
  exit 1
fi

echo ""
echo "[SETUP] Pre-installing httpd for golden AMI demo..."
CMD_ID=$(aws ssm send-command \
  --instance-ids ${INSTANCE_ID} \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["sudo yum install -y httpd","sudo systemctl enable httpd","sudo mkdir -p /var/www/html","echo HealthCheck | sudo tee /var/www/html/index.html"]' \
  --comment "Pre-install for golden AMI" \
  --query Command.CommandId --output text)

echo "  Command ID: ${CMD_ID}"
echo "  Waiting for command to complete..."
aws ssm wait command-executed --command-id ${CMD_ID} --instance-id ${INSTANCE_ID} 2>/dev/null || true
sleep 5

STATUS=$(aws ssm get-command-invocation --command-id ${CMD_ID} --instance-id ${INSTANCE_ID} \
  --query Status --output text 2>/dev/null)
echo "  Command status: ${STATUS}"

echo ""
echo "[DONE] Setup complete!"
echo "  export INSTANCE_ID=${INSTANCE_ID}"
