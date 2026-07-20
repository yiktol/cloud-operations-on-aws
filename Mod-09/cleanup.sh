#!/bin/bash
# Mod-09 - Cleanup
set -e
STACK_NAME="mod09-monitoring-demo"

echo "[CLEANUP] Mod-09 Demo..."

echo "[CW] Deleting alarms..."
aws cloudwatch delete-alarms --alarm-names "Demo-HighCPU" 2>/dev/null || true

echo "[LOGS] Deleting log group..."
aws logs delete-log-group --log-group-name "/demo/application" 2>/dev/null || true

echo "[STACK] Deleting CloudFormation stack..."
aws cloudformation delete-stack --stack-name ${STACK_NAME}
aws cloudformation wait stack-delete-complete --stack-name ${STACK_NAME}

echo "[DONE] Cleanup complete!"
