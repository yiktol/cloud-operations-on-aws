#!/bin/bash
# Module 14 - Cleanup
set -e
STACK_NAME="mod14-cost-optimization-demo"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "[CLEANUP] Module 14 Demo..."

# Delete budget created during demo (budgets API uses account ID)
aws budgets delete-budget \
  --account-id ${ACCOUNT_ID} \
  --budget-name "Demo-Monthly-Budget" 2>/dev/null || true

# Delete CloudWatch billing alarm (must be in us-east-1)
aws cloudwatch delete-alarms \
  --alarm-names "Demo-BillingAlert" \
  --region us-east-1 2>/dev/null || true

# Delete stack
aws cloudformation delete-stack --stack-name ${STACK_NAME}
aws cloudformation wait stack-delete-complete --stack-name ${STACK_NAME}

echo "[DONE] Cleanup complete!"
