#!/bin/bash
# Module 04 - Live Demo: Tag, Image, Deploy
# Prereq: Run deploy.sh first.

STACK_NAME="mod04-deploy-update-demo"
if [ -z "$INSTANCE_ID" ]; then
  INSTANCE_ID=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
    --query 'Stacks[0].Outputs[?OutputKey==`InstanceId`].OutputValue' --output text)
fi
echo "Instance: ${INSTANCE_ID}"
echo ""

echo "============================================"
echo "  ACT 1: TAGGING STRATEGY"
echo "============================================"
echo ""
echo ">> Show current tags on the instance..."
read -p "Press Enter..."
aws ec2 describe-tags \
  --filters "Name=resource-id,Values=${INSTANCE_ID}" \
  --output table

echo ""
echo ">> Add operational tags (owner, application, patch group)..."
read -p "Press Enter..."
aws ec2 create-tags --resources ${INSTANCE_ID} --tags \
  Key=Application,Value=CustomerPortal \
  Key=Owner,Value=TeamAlpha \
  Key=PatchGroup,Value=Production-Linux

echo ""
echo ">> Find all Development resources by tag..."
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Environment,Values=Development \
  --query 'ResourceTagMappingList[*].{ARN:ResourceARN}' --output table

echo ""
echo ">> Create a Resource Group..."
aws resource-groups create-group \
  --name "Dev-Environment" \
  --resource-query '{
    "Type":"TAG_FILTERS_1_0",
    "Query":"{\"ResourceTypeFilters\":[\"AWS::AllSupported\"],\"TagFilters\":[{\"Key\":\"Environment\",\"Values\":[\"Development\"]}]}"
  }' 2>/dev/null || echo "  Resource group already exists."

echo ""
echo ">> RESULT: Tags = visibility for cost, automation, and access control."
echo ""

echo "============================================"
echo "  ACT 2: CREATE A GOLDEN AMI"
echo "============================================"
read -p "Press Enter..."

echo ">> Verify httpd is installed on the base instance..."
aws ssm send-command \
  --instance-ids ${INSTANCE_ID} \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["systemctl status httpd | head -3"]' \
  --query Command.CommandId --output text

echo ""
echo ">> Creating AMI from the instance..."
AMI_ID=$(aws ec2 create-image \
  --instance-id ${INSTANCE_ID} \
  --name "GoldenAMI-WebServer-$(date +%Y%m%d)" \
  --description "Web server with httpd pre-installed" \
  --tag-specifications 'ResourceType=image,Tags=[{Key=Name,Value=GoldenAMI-WebServer},{Key=Version,Value=1.0}]' \
  --query ImageId --output text)
echo "  AMI ID: ${AMI_ID}"

echo ""
echo ">> Check AMI state (will be pending then available)..."
aws ec2 describe-images --image-ids ${AMI_ID} \
  --query 'Images[0].{State:State,Name:Name,Created:CreationDate}' --output table

echo ""
echo ">> RESULT: Golden AMI captures known-good config - no drift possible."
echo ""

echo "============================================"
echo "  ACT 3: DEPLOY FROM GOLDEN AMI"
echo "============================================"
read -p "Press Enter (waiting for AMI to be available)..."

# Wait for AMI
aws ec2 wait image-available --image-ids ${AMI_ID}
echo "  AMI is available!"

echo ""
echo ">> Launch 2 instances from the golden AMI..."
aws ec2 run-instances \
  --image-id ${AMI_ID} \
  --instance-type t3.micro \
  --count 2 \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=WebServer-FromAMI},{Key=Environment,Value=Production},{Key=DeployedFrom,Value=${AMI_ID}}]" \
  --query 'Instances[*].{Id:InstanceId,State:State.Name}' --output table

echo ""
echo ">> RESULT: Every instance is identical - no post-launch config needed."
echo "   DeployedFrom tag creates a full audit trail back to the AMI."
echo ""
echo "============ DEMO COMPLETE ============"
