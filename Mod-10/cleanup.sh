#!/bin/bash
# Mod-10 - Cleanup
set -e
STACK_NAME="mod10-security-auditing-demo"

echo "[CLEANUP] Mod-10 Demo..."

echo "[EVENTS] Removing EventBridge rule..."
aws events remove-targets --rule "detect-sg-change" --ids "sns-alert" 2>/dev/null || true
aws events delete-rule --name "detect-sg-change" 2>/dev/null || true

echo "[EC2] Deleting demo security group..."
aws ec2 delete-security-group --group-name demo-detect-sg 2>/dev/null || true

echo "[CONFIG] Deleting Config rule..."
aws configservice delete-config-rule --config-rule-name restricted-ssh 2>/dev/null || true

echo "[STACK] Deleting CloudFormation stack..."
aws cloudformation delete-stack --stack-name ${STACK_NAME}
aws cloudformation wait stack-delete-complete --stack-name ${STACK_NAME}

echo "[DONE] Cleanup complete!"
