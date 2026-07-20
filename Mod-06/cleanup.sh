#!/bin/bash
# Mod-06 - Cleanup
set -e
STACK_NAME="mod06-manage-resources-demo"

echo "[CLEANUP] Mod-06 Demo..."

# Delete SSM parameters created during demo
echo "[PARAMS] Deleting demo parameters..."
aws ssm delete-parameters --names \
  "/demo/app/config/endpoint" \
  "/demo/app/secrets/db-password" 2>/dev/null || true

# Delete maintenance window
echo "[MAINT] Deleting maintenance window..."
WINDOW_ID=$(aws ssm describe-maintenance-windows \
  --filters "Key=Name,Values=Demo-PatchWindow" \
  --query 'WindowIdentities[0].WindowId' --output text 2>/dev/null) || true
if [ -n "$WINDOW_ID" ] && [ "$WINDOW_ID" != "None" ]; then
  aws ssm delete-maintenance-window --window-id ${WINDOW_ID} 2>/dev/null || true
fi

echo "[STACK] Deleting CloudFormation stack..."
aws cloudformation delete-stack --stack-name ${STACK_NAME}
aws cloudformation wait stack-delete-complete --stack-name ${STACK_NAME}

echo "[DONE] Cleanup complete!"
