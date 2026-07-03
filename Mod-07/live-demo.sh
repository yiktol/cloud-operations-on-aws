#!/bin/bash
# Module 07 - Live Demo: Configure Highly Available Systems
STACK_NAME="mod07-high-availability-demo"
INSTANCE_1=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`Instance1Id`].OutputValue' --output text)
INSTANCE_2=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`Instance2Id`].OutputValue' --output text)
SUBNET_1=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`SubnetAZ1Id`].OutputValue' --output text)
SUBNET_2=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`SubnetAZ2Id`].OutputValue' --output text)
SG_ID=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`SGId`].OutputValue' --output text)

echo "Instance1 (AZ1): ${INSTANCE_1}"
echo "Instance2 (AZ2): ${INSTANCE_2}"

echo "============================================"
echo "  ACT 1: CREATE AN APPLICATION LOAD BALANCER"
echo "============================================"
read -p "Press Enter..."
ALB_ARN=$(aws elbv2 create-load-balancer \
  --name demo-ha-alb \
  --subnets ${SUBNET_1} ${SUBNET_2} \
  --security-groups ${SG_ID} \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)

ALB_DNS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns ${ALB_ARN} \
  --query 'LoadBalancers[0].DNSName' --output text)
echo "  ALB DNS: ${ALB_DNS}"

TG_ARN=$(aws elbv2 create-target-group \
  --name demo-ha-targets --protocol HTTP --port 80 \
  --vpc-id $(aws ec2 describe-subnets --subnet-ids ${SUBNET_1} \
    --query 'Subnets[0].VpcId' --output text) \
  --health-check-path "/" \
  --query 'TargetGroups[0].TargetGroupArn' --output text)

aws elbv2 register-targets --target-group-arn ${TG_ARN} \
  --targets Id=${INSTANCE_1} Id=${INSTANCE_2}

aws elbv2 create-listener --load-balancer-arn ${ALB_ARN} \
  --protocol HTTP --port 80 \
  --default-actions Type=forward,TargetGroupArn=${TG_ARN}

echo ""
echo ">> RESULT: Single DNS entry, traffic distributed across 2 AZs."

echo ""
echo "============================================"
echo "  ACT 2: HEALTH CHECKS AND TRAFFIC BALANCE"
echo "============================================"
echo ">> Waiting for targets to become healthy (~30s)..."
sleep 35
read -p "Press Enter..."

aws elbv2 describe-target-health --target-group-arn ${TG_ARN} \
  --query 'TargetHealthDescriptions[*].{Instance:Target.Id,Health:TargetHealth.State}' \
  --output table

echo ""
echo ">> Hitting ALB 6 times - observe different instance IDs..."
for i in {1..6}; do
  curl -s --max-time 5 http://${ALB_DNS} | grep -oE 'i-[a-z0-9]+' || echo "  (still warming up)"
done
echo ""
echo ">> RESULT: Requests distributed round-robin across both instances."

echo ""
echo "============================================"
echo "  ACT 3: SIMULATE FAILURE - AUTO FAILOVER"
echo "============================================"
read -p "Press Enter to stop Instance 1 (simulate AZ failure)..."
aws ec2 stop-instances --instance-ids ${INSTANCE_1}
echo "  Instance 1 stopped! Waiting for health check to detect (~45s)..."
sleep 45

aws elbv2 describe-target-health --target-group-arn ${TG_ARN} \
  --query 'TargetHealthDescriptions[*].{Instance:Target.Id,Health:TargetHealth.State}' \
  --output table

echo ""
echo ">> Hitting ALB - all traffic now goes to Instance 2..."
for i in {1..4}; do
  curl -s --max-time 5 http://${ALB_DNS} | grep -oE 'i-[a-z0-9]+' || echo "  (routing...)"
done
echo ""
echo ">> RESULT: Automatic failover. Zero errors to users. No human intervention."
echo ""
echo "============ DEMO COMPLETE ============"
