#!/bin/bash
# Mod-07 - Cleanup
set -e
STACK_NAME="mod07-high-availability-demo"

echo "[CLEANUP] Mod-07 Demo..."

# Delete ALB resources created during demo
echo "[ALB] Removing load balancer resources..."
ALB_ARN=$(aws elbv2 describe-load-balancers --names demo-ha-alb \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null) || true

if [ -n "$ALB_ARN" ] && [ "$ALB_ARN" != "None" ]; then
  # Delete listeners
  LISTENERS=$(aws elbv2 describe-listeners --load-balancer-arn ${ALB_ARN} \
    --query 'Listeners[*].ListenerArn' --output text 2>/dev/null) || true
  for LISTENER in $LISTENERS; do
    [ -n "$LISTENER" ] && [ "$LISTENER" != "None" ] && \
      aws elbv2 delete-listener --listener-arn ${LISTENER} 2>/dev/null || true
  done

  # Delete ALB
  aws elbv2 delete-load-balancer --load-balancer-arn ${ALB_ARN} 2>/dev/null || true
  echo "  ALB deleted, waiting 30s for ENI cleanup..."
  sleep 30
fi

# Delete target group
TG_ARN=$(aws elbv2 describe-target-groups --names demo-ha-targets \
  --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null) || true
if [ -n "$TG_ARN" ] && [ "$TG_ARN" != "None" ]; then
  aws elbv2 delete-target-group --target-group-arn ${TG_ARN} 2>/dev/null || true
fi

# Restart stopped instance so CFN can terminate it
echo "[EC2] Restarting any stopped instances..."
INSTANCE_1=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`Instance1Id`].OutputValue' --output text 2>/dev/null) || true
if [ -n "$INSTANCE_1" ] && [ "$INSTANCE_1" != "None" ]; then
  STATE=$(aws ec2 describe-instances --instance-ids ${INSTANCE_1} \
    --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null) || true
  if [ "$STATE" = "stopped" ]; then
    aws ec2 start-instances --instance-ids ${INSTANCE_1} 2>/dev/null || true
    echo "  Started ${INSTANCE_1} (was stopped during demo)"
  fi
fi

echo "[STACK] Deleting CloudFormation stack..."
aws cloudformation delete-stack --stack-name ${STACK_NAME}
aws cloudformation wait stack-delete-complete --stack-name ${STACK_NAME}

echo "[DONE] Cleanup complete!"
