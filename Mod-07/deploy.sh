#!/bin/bash
# Mod-07 - Deploy Setup Stack
set -e
STACK_NAME="mod07-high-availability-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Use networking from CloudFormation exports
VPC_ID=$(aws cloudformation list-exports --query "Exports[?Name=='VpcId'].Value" --output text)
PUBLIC_SUBNET_1=$(aws cloudformation list-exports --query "Exports[?Name=='PublicSubnetOne'].Value" --output text)
PUBLIC_SUBNET_2=$(aws cloudformation list-exports --query "Exports[?Name=='PublicSubnetTwo'].Value" --output text)
PRIVATE_SUBNET_1=$(aws cloudformation list-exports --query "Exports[?Name=='PrivateSubnetOne'].Value" --output text)
PRIVATE_SUBNET_2=$(aws cloudformation list-exports --query "Exports[?Name=='PrivateSubnetTwo'].Value" --output text)

echo "[DEPLOY] Mod-07 Demo Stack..."
echo "  VPC: ${VPC_ID}"
echo "  ALB subnets (public): ${PUBLIC_SUBNET_1}, ${PUBLIC_SUBNET_2}"
echo "  Instance subnets (private): ${PRIVATE_SUBNET_1}, ${PRIVATE_SUBNET_2}"

aws cloudformation deploy \
  --template-file "${SCRIPT_DIR}/cfn-setup.yaml" \
  --stack-name ${STACK_NAME} \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    VpcId=${VPC_ID} \
    PublicSubnet1=${PUBLIC_SUBNET_1} \
    PublicSubnet2=${PUBLIC_SUBNET_2} \
    PrivateSubnet1=${PRIVATE_SUBNET_1} \
    PrivateSubnet2=${PRIVATE_SUBNET_2} \
  --no-fail-on-empty-changeset

echo ""
echo "[OUTPUTS]"
aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[*].{Key:OutputKey,Value:OutputValue}' --output table

INSTANCE_1=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`Instance1Id`].OutputValue' --output text)
INSTANCE_2=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`Instance2Id`].OutputValue' --output text)

echo ""
echo "[WAIT] Waiting for instances to pass status checks..."
aws ec2 wait instance-status-ok --instance-ids ${INSTANCE_1} ${INSTANCE_2}
echo "  ✓ Both instances running and status checks passing"

echo ""
echo "[DONE] Setup complete!"
echo "  export INSTANCE_1=${INSTANCE_1}"
echo "  export INSTANCE_2=${INSTANCE_2}"
