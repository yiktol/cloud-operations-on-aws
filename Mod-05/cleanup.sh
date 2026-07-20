#!/bin/bash
# Mod-05 - Cleanup
set -e
STACK_NAME="mod05-automate-deployment-demo"

echo "[CLEANUP] Mod-05 Demo..."

# Delete the demo webapp stack if still running
echo "[WEBAPP] Checking for demo-webapp-dev stack..."
WEBAPP_STATUS=$(aws cloudformation describe-stacks --stack-name demo-webapp-dev \
  --query 'Stacks[0].StackStatus' --output text 2>/dev/null) || true

if [ -n "$WEBAPP_STATUS" ] && [ "$WEBAPP_STATUS" != "None" ] && [ "$WEBAPP_STATUS" != "DELETE_COMPLETE" ]; then
  # Get VPC ID before deletion for cleanup
  VPC_ID=$(aws cloudformation describe-stacks --stack-name demo-webapp-dev \
    --query 'Stacks[0].Outputs[?OutputKey==`VPCId`].OutputValue' --output text 2>/dev/null) || true

  echo "  Deleting demo-webapp-dev (status: ${WEBAPP_STATUS})..."
  aws cloudformation delete-stack --stack-name demo-webapp-dev 2>/dev/null || true

  # GuardDuty auto-creates VPC endpoints and security groups in new VPCs
  # These block CloudFormation from deleting the VPC - clean them up
  if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
    echo "  Cleaning up GuardDuty resources in ${VPC_ID}..."
    sleep 10

    # Delete VPC endpoints first
    GD_ENDPOINTS=$(aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=${VPC_ID}" \
      --query 'VpcEndpoints[*].VpcEndpointId' --output text 2>/dev/null) || true
    for EP in $GD_ENDPOINTS; do
      [ -n "$EP" ] && [ "$EP" != "None" ] && aws ec2 delete-vpc-endpoints --vpc-endpoint-ids ${EP} 2>/dev/null || true
    done

    # Wait for ENIs to detach and delete them
    if [ -n "$GD_ENDPOINTS" ] && [ "$GD_ENDPOINTS" != "None" ]; then
      echo "  Waiting for endpoint ENIs to release..."
      sleep 30
      ENIS=$(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=${VPC_ID}" "Name=status,Values=available" \
        --query 'NetworkInterfaces[*].NetworkInterfaceId' --output text 2>/dev/null) || true
      for ENI in $ENIS; do
        [ -n "$ENI" ] && [ "$ENI" != "None" ] && aws ec2 delete-network-interface --network-interface-id ${ENI} 2>/dev/null || true
      done
    fi

    # Delete GuardDuty managed security groups (retry to handle timing)
    for attempt in 1 2 3; do
      GD_SGS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=${VPC_ID}" "Name=group-name,Values=GuardDuty*" \
        --query 'SecurityGroups[*].GroupId' --output text 2>/dev/null) || true
      if [ -z "$GD_SGS" ] || [ "$GD_SGS" = "None" ]; then
        break
      fi
      for SG in $GD_SGS; do
        [ -n "$SG" ] && [ "$SG" != "None" ] && aws ec2 delete-security-group --group-id ${SG} 2>/dev/null || true
      done
      [ $attempt -lt 3 ] && sleep 10
    done
  fi

  echo "  Waiting for stack deletion..."
  aws cloudformation wait stack-delete-complete --stack-name demo-webapp-dev 2>/dev/null || true
fi

echo "[TEMPLATES] Emptying template bucket..."
TEMPLATE_BUCKET=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`TemplateBucketName`].OutputValue' --output text 2>/dev/null) || true
if [ -n "$TEMPLATE_BUCKET" ] && [ "$TEMPLATE_BUCKET" != "None" ]; then
  aws s3 rm s3://${TEMPLATE_BUCKET} --recursive 2>/dev/null || true
fi

echo "[STACK] Deleting CloudFormation stack..."
aws cloudformation delete-stack --stack-name ${STACK_NAME}
aws cloudformation wait stack-delete-complete --stack-name ${STACK_NAME}

echo "[DONE] Cleanup complete!"
