#!/bin/bash
# Module 07 - Live Demo: Configure Highly Available Systems
# Prereq: Run deploy.sh first
set -e

STACK_NAME="mod07-high-availability-demo"
INSTANCE_1=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`Instance1Id`].OutputValue' --output text)
INSTANCE_2=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`Instance2Id`].OutputValue' --output text)
PUBLIC_SUBNET_1=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`PublicSubnet1Id`].OutputValue' --output text)
PUBLIC_SUBNET_2=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`PublicSubnet2Id`].OutputValue' --output text)
ALB_SG=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`ALBSecurityGroupId`].OutputValue' --output text)
VPC_ID=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`VPCId`].OutputValue' --output text)

echo "========================================"
echo " Module 07: High Availability"
echo " Instance 1: ${INSTANCE_1} (AZ1)"
echo " Instance 2: ${INSTANCE_2} (AZ2)"
echo "========================================"
echo ""

# --- ACT 1: Create an Application Load Balancer ---
echo "--- ACT 1: Create an Application Load Balancer ---"
echo ""

# Create ALB in public subnets (internet-facing)
echo "[1.1] Creating ALB across two public subnets..."
ALB_ARN=$(aws elbv2 create-load-balancer \
  --name demo-ha-alb \
  --subnets ${PUBLIC_SUBNET_1} ${PUBLIC_SUBNET_2} \
  --security-groups ${ALB_SG} \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)

ALB_DNS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns ${ALB_ARN} \
  --query 'LoadBalancers[0].DNSName' --output text)
echo "  ALB DNS: ${ALB_DNS}"
echo ""

# Create target group with health checks
echo "[1.2] Creating target group with health checks..."
TG_ARN=$(aws elbv2 create-target-group \
  --name demo-ha-targets --protocol HTTP --port 80 \
  --vpc-id ${VPC_ID} \
  --health-check-path "/" \
  --health-check-interval-seconds 10 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 2 \
  --query 'TargetGroups[0].TargetGroupArn' --output text)
echo "  Target Group: ${TG_ARN}"
echo ""

# Register both instances (in private subnets)
echo "[1.3] Registering instances..."
aws elbv2 register-targets --target-group-arn ${TG_ARN} \
  --targets Id=${INSTANCE_1} Id=${INSTANCE_2}
echo "  ✓ Registered ${INSTANCE_1} and ${INSTANCE_2}"
echo ""

# Create listener to forward traffic
echo "[1.4] Creating HTTP listener..."
aws elbv2 create-listener --load-balancer-arn ${ALB_ARN} \
  --protocol HTTP --port 80 \
  --default-actions Type=forward,TargetGroupArn=${TG_ARN} \
  --query 'Listeners[0].ListenerArn' --output text
echo ""

# --- ACT 2: Health Checks and Traffic Balance ---
echo "--- ACT 2: Health Checks and Traffic Distribution ---"
echo ""

# Wait for targets to become healthy
echo "[2.1] Waiting for targets to become healthy (30-40s)..."
sleep 35

# Check target health status
echo "[2.2] Target health status:"
aws elbv2 describe-target-health --target-group-arn ${TG_ARN} \
  --query 'TargetHealthDescriptions[*].{Instance:Target.Id,Health:TargetHealth.State}' \
  --output table
echo ""

# Hit ALB 6 times to observe round-robin distribution
echo "[2.3] Traffic distribution (6 requests):"
for i in {1..6}; do
  RESPONSE=$(curl -s --max-time 5 http://${ALB_DNS} 2>/dev/null | grep -oE 'i-[a-z0-9]+') || true
  echo "  Request ${i}: ${RESPONSE:-timeout}"
done
echo ""

# --- ACT 3: Simulate Failure - Auto Failover ---
echo "--- ACT 3: Simulate Failure - High Availability in Action ---"
echo ""

# Stop Instance 1 to simulate an AZ failure
echo "[3.1] Stopping Instance 1 (simulating AZ failure)..."
aws ec2 stop-instances --instance-ids ${INSTANCE_1} \
  --query 'StoppingInstances[0].{Instance:InstanceId,State:CurrentState.Name}' --output table
echo ""

echo "[3.2] Waiting for health check to detect failure (45s)..."
sleep 45

# Verify health check detected the failure
echo "[3.3] Target health after failure:"
aws elbv2 describe-target-health --target-group-arn ${TG_ARN} \
  --query 'TargetHealthDescriptions[*].{Instance:Target.Id,Health:TargetHealth.State}' \
  --output table
echo ""

# All traffic now routes to Instance 2 automatically
echo "[3.4] Traffic now (all goes to healthy instance):"
for i in {1..4}; do
  RESPONSE=$(curl -s --max-time 5 http://${ALB_DNS} 2>/dev/null | grep -oE 'i-[a-z0-9]+') || true
  echo "  Request ${i}: ${RESPONSE:-timeout}"
done
echo ""

echo "========================================"
echo " Demo Complete!"
echo " ALB DNS: ${ALB_DNS}"
echo "========================================"
