#!/bin/bash
# Module 03 - Live Demo: System Discovery
# Prereq: Run deploy.sh first
set -e

STACK_NAME="mod03-system-discovery-demo"
if [ -z "$INSTANCE_ID" ]; then
  INSTANCE_ID=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
    --query 'Stacks[0].Outputs[?OutputKey==`InstanceId`].OutputValue' --output text)
fi

echo "========================================"
echo " Module 03: System Discovery"
echo " Instance: ${INSTANCE_ID}"
echo "========================================"
echo ""

# --- ACT 1: Session Manager - No SSH Needed ---
echo "--- ACT 1: Session Manager - Connect Without SSH ---"
echo ""

# Show instance has no key pair and no public IP
echo "[1.1] Instance configuration (no SSH key, no public IP):"
aws ec2 describe-instances --instance-ids ${INSTANCE_ID} \
  --query 'Reservations[0].Instances[0].{KeyName:KeyName,PublicIP:PublicIpAddress,PrivateIP:PrivateIpAddress,State:State.Name}' \
  --output table
echo ""

# Confirm SSM agent is online
echo "[1.2] SSM Agent status:"
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=${INSTANCE_ID}" \
  --query 'InstanceInformationList[0].{Id:InstanceId,Ping:PingStatus,Platform:PlatformName,AgentVersion:AgentVersion}' \
  --output table
echo ""

# Start a Session Manager session (interactive shell, type 'exit' to return)
echo "[1.3] Starting Session Manager session (type 'exit' to return)..."
aws ssm start-session --target ${INSTANCE_ID}
echo ""

# --- ACT 2: SSM Inventory - Inside the Instance ---
echo "--- ACT 2: SSM Inventory - What's Inside the Instance ---"
echo ""

# List installed applications
echo "[2.1] Installed applications (top 5):"
aws ssm list-inventory-entries \
  --instance-id ${INSTANCE_ID} \
  --type-name "AWS:Application" \
  --query 'Entries[0:5]' --output table 2>/dev/null || echo "  (Inventory not yet collected - wait for scheduled collection)"
echo ""

# List network interfaces
echo "[2.2] Network configuration:"
aws ssm list-inventory-entries \
  --instance-id ${INSTANCE_ID} \
  --type-name "AWS:Network" \
  --query 'Entries[0:3]' --output table 2>/dev/null || echo "  (Network inventory not available)"
echo ""

# Show instance detailed information
echo "[2.3] Instance hardware details:"
aws ssm list-inventory-entries \
  --instance-id ${INSTANCE_ID} \
  --type-name "AWS:InstanceDetailedInformation" \
  --query 'Entries[0]' --output table 2>/dev/null || echo "  (Detailed info not yet collected)"
echo ""

# --- ACT 3: AWS Config - Continuous Compliance ---
echo "--- ACT 3: AWS Config - Continuous Compliance ---"
echo ""

# Show discovered resource counts
echo "[3.1] Discovered resource counts:"
aws configservice get-discovered-resource-counts \
  --resource-types "AWS::EC2::Instance" "AWS::EC2::SecurityGroup" "AWS::IAM::Role" "AWS::S3::Bucket" \
  --output table 2>/dev/null || echo "  (Config not recording - check recorder status)"
echo ""

# Check compliance status for SSM managed instances rule
echo "[3.2] Compliance: EC2 instances managed by SSM:"
aws configservice get-compliance-details-by-config-rule \
  --config-rule-name ec2-instance-managed-by-ssm \
  --query 'EvaluationResults[*].{Resource:EvaluationResultIdentifier.EvaluationResultQualifier.ResourceId,Compliance:ComplianceType}' \
  --output table 2>/dev/null || echo "  (Rule not yet evaluated - trigger with: aws configservice start-config-rules-evaluation)"
echo ""

# Show resource configuration history
echo "[3.3] Configuration history for this instance:"
aws configservice get-resource-config-history \
  --resource-type AWS::EC2::Instance \
  --resource-id ${INSTANCE_ID} \
  --limit 3 \
  --query 'configurationItems[*].{Time:configurationItemCaptureTime,Status:configurationItemStatus}' \
  --output table 2>/dev/null || echo "  (No configuration history available yet)"
echo ""

echo "========================================"
echo " Demo Complete!"
echo "========================================"
