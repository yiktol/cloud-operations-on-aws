#!/bin/bash
# Module 04 - Live Demo: Tag, Image, Deploy
# Prereq: Run deploy.sh first
set -e

STACK_NAME="mod04-deploy-update-demo"
if [ -z "$INSTANCE_ID" ]; then
  INSTANCE_ID=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
    --query 'Stacks[0].Outputs[?OutputKey==`InstanceId`].OutputValue' --output text)
fi

# Get networking details from stack outputs for launching new instances
SUBNET_ID=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`SubnetId`].OutputValue' --output text)
SG_ID=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`SecurityGroupId`].OutputValue' --output text)
PROFILE_NAME=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`InstanceProfileName`].OutputValue' --output text)

echo "========================================"
echo " Module 04: Deploy and Update Resources"
echo " Instance: ${INSTANCE_ID}"
echo "========================================"
echo ""

# --- ACT 1: Tagging Strategy ---
echo "--- ACT 1: Tagging Strategy (Resource Organization) ---"
echo ""

# Show current tags on the instance
echo "[1.1] Current tags on the base instance:"
aws ec2 describe-tags \
  --filters "Name=resource-id,Values=${INSTANCE_ID}" \
  --query 'Tags[*].{Key:Key,Value:Value}' \
  --output table
echo ""

# Add operational tags (owner, application, patch group)
echo "[1.2] Adding operational tags..."
aws ec2 create-tags --resources ${INSTANCE_ID} --tags \
  Key=Application,Value=CustomerPortal \
  Key=Owner,Value=TeamAlpha \
  Key=PatchGroup,Value=Production-Linux
echo "  ✓ Tags added: Application, Owner, PatchGroup"
echo ""

# Find all Development resources by tag
echo "[1.3] Resources tagged Environment=Development:"
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Environment,Values=Development \
  --query 'ResourceTagMappingList[*].{ARN:ResourceARN}' --output table
echo ""

# Create a Resource Group based on tags
echo "[1.4] Creating Resource Group 'Dev-Environment'..."
aws resource-groups create-group \
  --name "Dev-Environment" \
  --resource-query '{
    "Type":"TAG_FILTERS_1_0",
    "Query":"{\"ResourceTypeFilters\":[\"AWS::AllSupported\"],\"TagFilters\":[{\"Key\":\"Environment\",\"Values\":[\"Development\"]}]}"
  }' --query 'Group.{Name:Name,ARN:GroupArn}' --output table 2>/dev/null || echo "  (Group already exists)"
echo ""

# --- ACT 2: Create a Golden AMI ---
echo "--- ACT 2: Create a Golden AMI ---"
echo ""

# Verify httpd is installed on the base instance
echo "[2.1] Verifying httpd is installed:"
CMD_ID=$(aws ssm send-command \
  --instance-ids ${INSTANCE_ID} \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["systemctl status httpd | head -3"]' \
  --query Command.CommandId --output text)
sleep 5
aws ssm get-command-invocation --command-id ${CMD_ID} --instance-id ${INSTANCE_ID} \
  --query 'StandardOutputContent' --output text
echo ""

# Create AMI from the instance
echo "[2.2] Creating Golden AMI..."
AMI_ID=$(aws ec2 create-image \
  --instance-id ${INSTANCE_ID} \
  --name "GoldenAMI-WebServer-$(date +%Y%m%d)" \
  --description "Web server with httpd pre-installed" \
  --tag-specifications 'ResourceType=image,Tags=[{Key=Name,Value=GoldenAMI-WebServer},{Key=Version,Value=1.0}]' \
  --query ImageId --output text)
echo "  AMI ID: ${AMI_ID}"
echo ""

# Check AMI state
echo "[2.3] AMI status:"
aws ec2 describe-images --image-ids ${AMI_ID} \
  --query 'Images[0].{State:State,Name:Name,Created:CreationDate}' --output table
echo ""

# --- ACT 3: Deploy from Golden AMI ---
echo "--- ACT 3: Deploy from Golden AMI ---"
echo ""

# Wait for AMI to be available
echo "[3.1] Waiting for AMI to become available..."
aws ec2 wait image-available --image-ids ${AMI_ID}
echo "  ✓ AMI is available"
echo ""

# Launch 2 instances from the golden AMI
echo "[3.2] Launching 2 instances from Golden AMI..."
aws ec2 run-instances \
  --image-id ${AMI_ID} \
  --instance-type t3.micro \
  --count 2 \
  --subnet-id ${SUBNET_ID} \
  --security-group-ids ${SG_ID} \
  --iam-instance-profile Name=${PROFILE_NAME} \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=WebServer-FromAMI},{Key=Environment,Value=Production},{Key=DeployedFrom,Value=${AMI_ID}}]" \
  --query 'Instances[*].{Id:InstanceId,State:State.Name}' --output table
echo ""

echo "========================================"
echo " Demo Complete!"
echo " Golden AMI: ${AMI_ID}"
echo "========================================"
