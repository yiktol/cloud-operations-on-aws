#!/bin/bash
# Mod-11 - Cleanup
set -e
STACK_NAME="mod11-secure-networks-demo"

echo "[CLEANUP] Mod-11 Demo..."

# Delete VPC resources created during live demo
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=Demo-SecureVPC" \
  --query 'Vpcs[0].VpcId' --output text 2>/dev/null) || true

if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
  echo "  Cleaning up demo VPC: ${VPC_ID}"

  # Delete flow logs
  echo "  [1] Deleting flow logs..."
  FLOW_LOG_IDS=$(aws ec2 describe-flow-logs --filter "Name=resource-id,Values=${VPC_ID}" \
    --query 'FlowLogs[*].FlowLogId' --output text 2>/dev/null) || true
  for FL in $FLOW_LOG_IDS; do
    [ -n "$FL" ] && [ "$FL" != "None" ] && aws ec2 delete-flow-logs --flow-log-ids ${FL} 2>/dev/null || true
  done

  # Delete GuardDuty VPC endpoints
  echo "  [2] Deleting VPC endpoints..."
  ENDPOINTS=$(aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query 'VpcEndpoints[*].VpcEndpointId' --output text 2>/dev/null) || true
  for EP in $ENDPOINTS; do
    [ -n "$EP" ] && [ "$EP" != "None" ] && aws ec2 delete-vpc-endpoints --vpc-endpoint-ids ${EP} 2>/dev/null || true
  done

  # Wait for endpoint ENIs to release
  if [ -n "$ENDPOINTS" ] && [ "$ENDPOINTS" != "None" ]; then
    echo "  [3] Waiting for endpoint ENIs to release (30s)..."
    sleep 30
    ENIS=$(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=${VPC_ID}" "Name=status,Values=available" \
      --query 'NetworkInterfaces[*].NetworkInterfaceId' --output text 2>/dev/null) || true
    for ENI in $ENIS; do
      [ -n "$ENI" ] && [ "$ENI" != "None" ] && aws ec2 delete-network-interface --network-interface-id ${ENI} 2>/dev/null || true
    done
  fi

  # Delete non-default security groups (including GuardDuty managed ones)
  echo "  [4] Deleting security groups..."
  SGS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text 2>/dev/null) || true
  for SG in $SGS; do
    [ -n "$SG" ] && [ "$SG" != "None" ] && aws ec2 delete-security-group --group-id ${SG} 2>/dev/null || true
  done

  # Delete non-default NACLs
  echo "  [5] Deleting NACLs..."
  NACLS=$(aws ec2 describe-network-acls --filters "Name=vpc-id,Values=${VPC_ID}" "Name=default,Values=false" \
    --query 'NetworkAcls[*].NetworkAclId' --output text 2>/dev/null) || true
  for NACL in $NACLS; do
    [ -n "$NACL" ] && [ "$NACL" != "None" ] && aws ec2 delete-network-acl --network-acl-id ${NACL} 2>/dev/null || true
  done

  # Delete subnets
  echo "  [6] Deleting subnets..."
  SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query 'Subnets[*].SubnetId' --output text 2>/dev/null) || true
  for SUBNET in $SUBNETS; do
    [ -n "$SUBNET" ] && [ "$SUBNET" != "None" ] && aws ec2 delete-subnet --subnet-id ${SUBNET} 2>/dev/null || true
  done

  # Detach and delete IGW
  echo "  [7] Deleting internet gateway..."
  IGW=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=${VPC_ID}" \
    --query 'InternetGateways[0].InternetGatewayId' --output text 2>/dev/null) || true
  if [ -n "$IGW" ] && [ "$IGW" != "None" ]; then
    aws ec2 detach-internet-gateway --internet-gateway-id ${IGW} --vpc-id ${VPC_ID} 2>/dev/null || true
    aws ec2 delete-internet-gateway --internet-gateway-id ${IGW} 2>/dev/null || true
  fi

  # Delete non-main route tables
  echo "  [8] Deleting route tables..."
  MAIN_RT=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=${VPC_ID}" "Name=association.main,Values=true" \
    --query 'RouteTables[0].RouteTableId' --output text 2>/dev/null) || true
  ALL_RTS=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query 'RouteTables[*].RouteTableId' --output text 2>/dev/null) || true
  for RT in $ALL_RTS; do
    if [ -n "$RT" ] && [ "$RT" != "None" ] && [ "$RT" != "$MAIN_RT" ]; then
      aws ec2 delete-route-table --route-table-id ${RT} 2>/dev/null || true
    fi
  done

  # Delete VPC
  echo "  [9] Deleting VPC..."
  aws ec2 delete-vpc --vpc-id ${VPC_ID} 2>/dev/null || echo "  ⚠ VPC deletion failed (may need manual cleanup)"
fi

echo "[LOGS] Deleting flow log group..."
aws logs delete-log-group --log-group-name "/demo/vpc-flow-logs" 2>/dev/null || true

echo "[STACK] Deleting CloudFormation stack..."
aws cloudformation delete-stack --stack-name ${STACK_NAME}
aws cloudformation wait stack-delete-complete --stack-name ${STACK_NAME}

echo "[DONE] Cleanup complete!"
