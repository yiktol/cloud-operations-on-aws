#!/bin/bash
# Mod-08 - Deploy Setup Stack
set -e
STACK_NAME="mod08-auto-scaling-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Use networking from CloudFormation exports
VPC_ID=$(aws cloudformation list-exports --query "Exports[?Name=='VpcId'].Value" --output text)
PRIVATE_SUBNET_1=$(aws cloudformation list-exports --query "Exports[?Name=='PrivateSubnetOne'].Value" --output text)
PRIVATE_SUBNET_2=$(aws cloudformation list-exports --query "Exports[?Name=='PrivateSubnetTwo'].Value" --output text)

echo "[DEPLOY] Mod-08 Demo Stack..."
echo "  VPC: ${VPC_ID}"
echo "  Subnets (private): ${PRIVATE_SUBNET_1}, ${PRIVATE_SUBNET_2}"

aws cloudformation deploy \
  --template-file "${SCRIPT_DIR}/cfn-setup.yaml" \
  --stack-name ${STACK_NAME} \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    VpcId=${VPC_ID} \
    PrivateSubnet1=${PRIVATE_SUBNET_1} \
    PrivateSubnet2=${PRIVATE_SUBNET_2} \
  --no-fail-on-empty-changeset

echo ""
echo "[OUTPUTS]"
aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[*].{Key:OutputKey,Value:OutputValue}' --output table

echo ""
echo "[DONE] Setup complete!"
