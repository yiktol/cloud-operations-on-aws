#!/bin/bash
# Mod-11 - Cleanup
set -e
STACK_NAME="mod11-secure-networks-demo"

echo "[CLEANUP] Mod-11 Demo..."

# Delete VPC resources created during live demo
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=Demo-SecureVPC" \
  --query 'Vpcs[0].VpcId' --output text 2>/dev/null)
if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
  echo "  Cleaning up demo VPC: ${VPC_ID}"
  # Delete flow logs
  aws ec2 describe-flow-logs --filter "Name=resource-id,Values=${VPC_ID}" \
    --query 'FlowLogs[*].FlowLogId' --output text | xargs -r aws ec2 delete-flow-logs 2>/dev/null || true
  # Delete subnets
  aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query 'Subnets[*].SubnetId' --output text | xargs -I {} aws ec2 delete-subnet --subnet-id {} 2>/dev/null || true
  # Delete security groups (non-default)
  aws ec2 describe-security-groups --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
    --output text | xargs -I {} aws ec2 delete-security-group --group-id {} 2>/dev/null || true
  # Delete NACLs (non-default)
  aws ec2 describe-network-acls --filters "Name=vpc-id,Values=${VPC_ID}" "Name=default,Values=false" \
    --query 'NetworkAcls[*].NetworkAclId' \
    --output text | xargs -I {} aws ec2 delete-network-acl --network-acl-id {} 2>/dev/null || true
  # Detach and delete IGW
  IGW=$(aws ec2 describe-internet-gateways \
    --filters "Name=attachment.vpc-id,Values=${VPC_ID}" \
    --query 'InternetGateways[0].InternetGatewayId' --output text 2>/dev/null)
  if [ -n "$IGW" ] && [ "$IGW" != "None" ]; then
    aws ec2 detach-internet-gateway --internet-gateway-id ${IGW} --vpc-id ${VPC_ID}
    aws ec2 delete-internet-gateway --internet-gateway-id ${IGW}
  fi
  # Delete route tables (non-main)
  aws ec2 describe-route-tables --filters "Name=vpc-id,Values=${VPC_ID}" "Name=association.main,Values=false" \
    --query 'RouteTables[*].RouteTableId' \
    --output text | xargs -I {} aws ec2 delete-route-table --route-table-id {} 2>/dev/null || true
  # Delete VPC
  aws ec2 delete-vpc --vpc-id ${VPC_ID}
fi
aws logs delete-log-group --log-group-name "/demo/vpc-flow-logs" 2>/dev/null || true

echo "[STACK] Deleting CloudFormation stack..."
aws cloudformation delete-stack --stack-name ${STACK_NAME}
aws cloudformation wait stack-delete-complete --stack-name ${STACK_NAME}

echo "[DONE] Cleanup complete!"
