#!/bin/bash
# Mod-08 - Cleanup
set -e
STACK_NAME="mod08-auto-scaling-demo"

echo "[CLEANUP] Mod-08 Demo..."

# Delete ASG if still running
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name demo-asg --min-size 0 --desired-capacity 0 2>/dev/null || true
sleep 20
aws autoscaling delete-auto-scaling-group \
  --auto-scaling-group-name demo-asg --force-delete 2>/dev/null || true
# Delete launch template
LT_ID=$(aws ec2 describe-launch-templates \
  --filters "Name=launch-template-name,Values=demo-scaling-template" \
  --query 'LaunchTemplates[0].LaunchTemplateId' --output text 2>/dev/null)
[ -n "$LT_ID" ] && aws ec2 delete-launch-template --launch-template-id ${LT_ID} 2>/dev/null || true

echo "[STACK] Deleting CloudFormation stack..."
aws cloudformation delete-stack --stack-name ${STACK_NAME}
aws cloudformation wait stack-delete-complete --stack-name ${STACK_NAME}

echo "[DONE] Cleanup complete!"
