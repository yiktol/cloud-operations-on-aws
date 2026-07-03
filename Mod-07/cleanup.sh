#!/bin/bash
# Mod-07 - Cleanup
set -e
STACK_NAME="mod07-high-availability-demo"

echo "[CLEANUP] Mod-07 Demo..."

# Delete ALB resources created during demo
STACK_NAME_DEMO="${STACK_NAME}"
ALB_ARN=$(aws elbv2 describe-load-balancers --names demo-ha-alb \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null)
if [ -n "$ALB_ARN" ] && [ "$ALB_ARN" != "None" ]; then
  LISTENER=$(aws elbv2 describe-listeners --load-balancer-arn ${ALB_ARN} \
    --query 'Listeners[0].ListenerArn' --output text)
  [ -n "$LISTENER" ] && aws elbv2 delete-listener --listener-arn ${LISTENER} 2>/dev/null || true
  TG_ARN=$(aws elbv2 describe-target-groups --names demo-ha-targets \
    --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null)
  aws elbv2 delete-load-balancer --load-balancer-arn ${ALB_ARN}
  sleep 30
  [ -n "$TG_ARN" ] && aws elbv2 delete-target-group --target-group-arn ${TG_ARN} 2>/dev/null || true
fi

echo "[STACK] Deleting CloudFormation stack..."
aws cloudformation delete-stack --stack-name ${STACK_NAME}
aws cloudformation wait stack-delete-complete --stack-name ${STACK_NAME}

echo "[DONE] Cleanup complete!"
