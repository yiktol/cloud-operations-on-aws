#!/bin/bash
# Module 05 - Live Demo: Infrastructure as Code with CloudFormation
# Prereq: Run deploy.sh first (creates webapp-stack.yaml in this folder)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${SCRIPT_DIR}/webapp-stack.yaml"

echo "========================================"
echo " Module 05: Infrastructure as Code"
echo " Template: webapp-stack.yaml"
echo "========================================"
echo ""

# --- ACT 1: Validate and Deploy a Stack ---
echo "--- ACT 1: Validate and Deploy ---"
echo ""

# Show the template structure (key sections)
echo "[1.1] Template sections:"
grep -E "^(Parameters|Conditions|Mappings|Resources|Outputs):" ${TEMPLATE}
echo ""

# Validate template syntax
echo "[1.2] Validating template:"
aws cloudformation validate-template --template-body file://${TEMPLATE} \
  --query '{Description:Description,Parameters:Parameters[*].ParameterKey}' --output table
echo ""

# Deploy stack as Development environment
echo "[1.3] Deploying stack as Development..."
aws cloudformation create-stack \
  --stack-name demo-webapp-dev \
  --template-body file://${TEMPLATE} \
  --parameters ParameterKey=EnvironmentType,ParameterValue=Development \
  --query 'StackId' --output text
echo ""

# Watch real-time creation events
echo "[1.4] Stack creation events (waiting 10s)..."
sleep 10
aws cloudformation describe-stack-events \
  --stack-name demo-webapp-dev \
  --query 'StackEvents[0:8].{Time:Timestamp,Resource:LogicalResourceId,Status:ResourceStatus}' \
  --output table
echo ""

# --- ACT 2: Stack Outputs and Drift Detection ---
echo "--- ACT 2: Stack Outputs and Drift Detection ---"
echo ""

# Wait for stack creation to complete
echo "[2.1] Waiting for stack creation to complete..."
aws cloudformation wait stack-create-complete --stack-name demo-webapp-dev
echo "  ✓ Stack created"
echo ""

# Show stack outputs
echo "[2.2] Stack outputs:"
aws cloudformation describe-stacks --stack-name demo-webapp-dev \
  --query 'Stacks[0].Outputs[*].{Key:OutputKey,Value:OutputValue}' --output table
echo ""

# List all resources created by the stack
echo "[2.3] Resources created:"
aws cloudformation list-stack-resources --stack-name demo-webapp-dev \
  --query 'StackResourceSummaries[*].{Type:ResourceType,Logical:LogicalResourceId,Status:ResourceStatus}' \
  --output table
echo ""

# Run drift detection to catch manual changes
echo "[2.4] Running drift detection..."
DRIFT_ID=$(aws cloudformation detect-stack-drift \
  --stack-name demo-webapp-dev --query StackDriftDetectionId --output text)
sleep 15
aws cloudformation describe-stack-drift-detection-status \
  --stack-drift-detection-id ${DRIFT_ID} \
  --query '{Status:DetectionStatus,DriftStatus:StackDriftStatus}' --output table
echo ""

# --- ACT 3: Change Sets - Preview Before Apply ---
echo "--- ACT 3: Change Sets - Preview Before Apply ---"
echo ""

# Create change set to upgrade to Production
echo "[3.1] Creating change set (Development → Production)..."
aws cloudformation create-change-set \
  --stack-name demo-webapp-dev \
  --change-set-name upgrade-to-production \
  --use-previous-template \
  --parameters ParameterKey=EnvironmentType,ParameterValue=Production \
  --query 'Id' --output text
echo ""

echo "[3.2] Waiting for change set to be ready..."
aws cloudformation wait change-set-create-complete \
  --stack-name demo-webapp-dev \
  --change-set-name upgrade-to-production 2>/dev/null || true
echo ""

# Preview what will change before executing
echo "[3.3] Changes that would be applied:"
aws cloudformation describe-change-set \
  --stack-name demo-webapp-dev \
  --change-set-name upgrade-to-production \
  --query 'Changes[*].ResourceChange.{Action:Action,Resource:LogicalResourceId,Replacement:Replacement}' \
  --output table
echo ""

# Cleanup demo stack
echo "--- Cleanup ---"
echo ""
echo "[4.1] Deleting change set..."
aws cloudformation delete-change-set --stack-name demo-webapp-dev --change-set-name upgrade-to-production
echo ""

echo "[4.2] Deleting demo stack..."
# Get VPC ID before deletion for GuardDuty cleanup
VPC_ID=$(aws cloudformation describe-stacks --stack-name demo-webapp-dev \
  --query 'Stacks[0].Outputs[?OutputKey==`VPCId`].OutputValue' --output text 2>/dev/null) || true

aws cloudformation delete-stack --stack-name demo-webapp-dev

# GuardDuty auto-creates VPC endpoints and security groups in new VPCs
# These block CloudFormation from deleting the VPC - clean them up
if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
  sleep 10
  GD_ENDPOINTS=$(aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query 'VpcEndpoints[*].VpcEndpointId' --output text 2>/dev/null) || true
  for EP in $GD_ENDPOINTS; do
    [ -n "$EP" ] && [ "$EP" != "None" ] && aws ec2 delete-vpc-endpoints --vpc-endpoint-ids ${EP} 2>/dev/null || true
  done
  if [ -n "$GD_ENDPOINTS" ] && [ "$GD_ENDPOINTS" != "None" ]; then
    sleep 30
    ENIS=$(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=${VPC_ID}" "Name=status,Values=available" \
      --query 'NetworkInterfaces[*].NetworkInterfaceId' --output text 2>/dev/null) || true
    for ENI in $ENIS; do
      [ -n "$ENI" ] && [ "$ENI" != "None" ] && aws ec2 delete-network-interface --network-interface-id ${ENI} 2>/dev/null || true
    done
  fi
  for attempt in 1 2 3; do
    GD_SGS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=${VPC_ID}" "Name=group-name,Values=GuardDuty*" \
      --query 'SecurityGroups[*].GroupId' --output text 2>/dev/null) || true
    if [ -z "$GD_SGS" ] || [ "$GD_SGS" = "None" ]; then break; fi
    for SG in $GD_SGS; do
      [ -n "$SG" ] && [ "$SG" != "None" ] && aws ec2 delete-security-group --group-id ${SG} 2>/dev/null || true
    done
    [ $attempt -lt 3 ] && sleep 10
  done
fi

aws cloudformation wait stack-delete-complete --stack-name demo-webapp-dev 2>/dev/null || true
echo "  ✓ Stack deleted"
echo ""

echo "========================================"
echo " Demo Complete!"
echo "========================================"
