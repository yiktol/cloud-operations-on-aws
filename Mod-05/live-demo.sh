#!/bin/bash
# Module 05 - Live Demo: Infrastructure as Code with CloudFormation
# Prereq: Run deploy.sh first (creates webapp-stack.yaml in this folder).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${SCRIPT_DIR}/webapp-stack.yaml"

echo "============================================"
echo "  ACT 1: VALIDATE AND DEPLOY A STACK"
echo "============================================"
echo ""
echo ">> Show the template structure (key sections)..."
read -p "Press Enter to show template..."
grep -E "^(Parameters|Conditions|Mappings|Resources|Outputs):" ${TEMPLATE}

echo ""
echo ">> Validate template..."
aws cloudformation validate-template --template-body file://${TEMPLATE}

echo ""
echo ">> Deploy stack as Development environment..."
read -p "Press Enter to deploy..."
aws cloudformation create-stack \
  --stack-name demo-webapp-dev \
  --template-body file://${TEMPLATE} \
  --parameters ParameterKey=EnvironmentType,ParameterValue=Development

echo ""
echo ">> Watch real-time creation events..."
sleep 5
aws cloudformation describe-stack-events \
  --stack-name demo-webapp-dev \
  --query 'StackEvents[0:8].{Time:Timestamp,Resource:LogicalResourceId,Status:ResourceStatus}' \
  --output table

echo ""
echo ">> RESULT: One YAML file created VPC + Subnet + SecurityGroup + EC2."
echo ""

echo "============================================"
echo "  ACT 2: STACK OUTPUTS AND DRIFT DETECTION"
echo "============================================"
read -p "Press Enter (waiting for stack to complete)..."

aws cloudformation wait stack-create-complete --stack-name demo-webapp-dev
echo "  Stack complete!"
echo ""
echo ">> Show stack outputs..."
aws cloudformation describe-stacks --stack-name demo-webapp-dev \
  --query 'Stacks[0].Outputs[*].{Key:OutputKey,Value:OutputValue}' --output table

echo ""
echo ">> List all resources created..."
aws cloudformation list-stack-resources --stack-name demo-webapp-dev \
  --query 'StackResourceSummaries[*].{Type:ResourceType,Logical:LogicalResourceId,Status:ResourceStatus}' \
  --output table

echo ""
echo ">> Run drift detection..."
read -p "Press Enter..."
DRIFT_ID=$(aws cloudformation detect-stack-drift \
  --stack-name demo-webapp-dev --query StackDriftDetectionId --output text)
sleep 15
aws cloudformation describe-stack-drift-detection-status \
  --stack-drift-detection-id ${DRIFT_ID} \
  --query '{Status:DetectionStatus,DriftStatus:StackDriftStatus}' --output table

echo ""
echo ">> RESULT: CloudFormation tracks everything. Drift detection catches manual changes."
echo ""

echo "============================================"
echo "  ACT 3: CHANGE SETS - PREVIEW BEFORE APPLY"
echo "============================================"
read -p "Press Enter..."

echo ">> Create change set to upgrade to Production..."
aws cloudformation create-change-set \
  --stack-name demo-webapp-dev \
  --change-set-name upgrade-to-production \
  --parameters ParameterKey=EnvironmentType,ParameterValue=Production

sleep 10
echo ""
echo ">> Preview what will change..."
aws cloudformation describe-change-set \
  --stack-name demo-webapp-dev \
  --change-set-name upgrade-to-production \
  --query 'Changes[*].ResourceChange.{Action:Action,Resource:LogicalResourceId,Replacement:Replacement}' \
  --output table

echo ""
echo ">> RESULT: Change sets let you SEE the impact before executing."
echo "   This is safe change management for production infrastructure."
echo ""

# Cleanup demo stack
read -p "Press Enter to delete demo webapp stack..."
aws cloudformation delete-change-set --stack-name demo-webapp-dev --change-set-name upgrade-to-production
aws cloudformation delete-stack --stack-name demo-webapp-dev
echo "  Stack deletion initiated."
echo ""
echo "============ DEMO COMPLETE ============"
