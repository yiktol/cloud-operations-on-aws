#!/bin/bash
# Mod-08 - Cleanup
set -e
STACK_NAME="mod08-auto-scaling-demo"

echo "[CLEANUP] Mod-08 Demo..."

# Delete ASG (force terminates all instances)
echo "[ASG] Deleting Auto Scaling Group..."
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name demo-asg --min-size 0 --desired-capacity 0 2>/dev/null || true
sleep 10
aws autoscaling delete-auto-scaling-group \
  --auto-scaling-group-name demo-asg --force-delete 2>/dev/null || true

# Wait for instances to terminate
echo "  Waiting for instances to terminate (30s)..."
sleep 30

# Delete launch template
echo "[LT] Deleting launch template..."
LT_ID=$(aws ec2 describe-launch-templates \
  --filters "Name=launch-template-name,Values=demo-scaling-template" \
  --query 'LaunchTemplates[0].LaunchTemplateId' --output text 2>/dev/null) || true
if [ -n "$LT_ID" ] && [ "$LT_ID" != "None" ]; then
  aws ec2 delete-launch-template --launch-template-id ${LT_ID} 2>/dev/null || true
fi

echo "[STACK] Deleting CloudFormation stack..."
aws cloudformation delete-stack --stack-name ${STACK_NAME}
aws cloudformation wait stack-delete-complete --stack-name ${STACK_NAME}

echo "[DONE] Cleanup complete!"
