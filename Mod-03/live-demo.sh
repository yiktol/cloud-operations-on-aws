#!/bin/bash
# Module 03 - Live Demo: System Discovery
# Prereq: Run deploy.sh first.

STACK_NAME="mod03-system-discovery-demo"
if [ -z "$INSTANCE_ID" ]; then
  INSTANCE_ID=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
    --query 'Stacks[0].Outputs[?OutputKey==`InstanceId`].OutputValue' --output text)
fi
echo "Instance: ${INSTANCE_ID}"
echo ""

echo "============================================"
echo "  ACT 1: SESSION MANAGER - NO SSH NEEDED"
echo "============================================"
echo ""
echo ">> Show instance has no key pair and no open ports..."
read -p "Press Enter..."
aws ec2 describe-instances --instance-ids ${INSTANCE_ID} \
  --query 'Reservations[0].Instances[0].{KeyName:KeyName,PublicIP:PublicIpAddress}' \
  --output table

echo ""
echo ">> Show it is SSM managed (PingStatus=Online)..."
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=${INSTANCE_ID}" \
  --query 'InstanceInformationList[0].{Id:InstanceId,Ping:PingStatus,Platform:PlatformName}' \
  --output table

echo ""
echo ">> Starting Session Manager session (interactive shell)..."
read -p "Press Enter to start session (type 'exit' twice to return)..."
aws ssm start-session --target ${INSTANCE_ID}

echo ""
echo ">> RESULT: Secure shell with no SSH, no keys, no open ports."
echo ""

echo "============================================"
echo "  ACT 2: SSM INVENTORY - INSIDE THE INSTANCE"
echo "============================================"
read -p "Press Enter..."

echo ">> Installed applications on the instance..."
aws ssm list-inventory-entries \
  --instance-id ${INSTANCE_ID} \
  --type-name "AWS:Application" \
  --query 'Entries[0:5]' --output table 2>/dev/null || echo "  (Inventory populates after first collection cycle ~30 min)"

echo ""
echo ">> Network interfaces..."
aws ssm list-inventory-entries \
  --instance-id ${INSTANCE_ID} \
  --type-name "AWS:Network" \
  --query 'Entries[0:3]' --output table 2>/dev/null || true

echo ""
echo ">> Instance detailed information..."
aws ssm list-inventory-entries \
  --instance-id ${INSTANCE_ID} \
  --type-name "AWS:InstanceDetailedInformation" \
  --query 'Entries[0]' --output table 2>/dev/null || true

echo ""
echo ">> RESULT: Agent reports what is INSIDE the instance - OS, software, network."
echo ""

echo "============================================"
echo "  ACT 3: AWS CONFIG - CONTINUOUS COMPLIANCE"
echo "============================================"
read -p "Press Enter..."

echo ">> Discovered resource counts..."
aws configservice get-discovered-resource-counts --output table 2>/dev/null || \
  echo "  Config recording must be active to show resource counts."

echo ""
echo ">> Compliance status for SSM rule..."
aws configservice get-compliance-details-by-config-rule \
  --config-rule-name ec2-instance-managed-by-ssm \
  --query 'EvaluationResults[*].{Resource:EvaluationResultIdentifier.EvaluationResultQualifier.ResourceId,Compliance:ComplianceType}' \
  --output table 2>/dev/null || echo "  (Config needs time to evaluate after recording starts)"

echo ""
echo ">> Resource configuration history..."
aws configservice get-resource-config-history \
  --resource-type AWS::EC2::Instance \
  --resource-id ${INSTANCE_ID} \
  --limit 3 \
  --query 'configurationItems[*].{Time:configurationItemCaptureTime,Status:configurationItemStatus}' \
  --output table 2>/dev/null || true

echo ""
echo ">> RESULT: Config = security camera for AWS infrastructure."
echo "   SSM Inventory = what is INSIDE.  Config = what is AROUND it."
echo ""
echo "============ DEMO COMPLETE ============"
