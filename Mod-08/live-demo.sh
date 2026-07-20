#!/bin/bash
# Module 08 - Live Demo: Automate Scaling
# Prereq: Run deploy.sh first
set -e

STACK_NAME="mod08-auto-scaling-demo"
SG_ID=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`SGId`].OutputValue' --output text)
SUBNET_1=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`PrivateSubnet1Id`].OutputValue' --output text)
SUBNET_2=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`PrivateSubnet2Id`].OutputValue' --output text)
PROFILE_ARN=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`InstanceProfileArn`].OutputValue' --output text)
LATEST_AMI=$(aws ssm get-parameter \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query Parameter.Value --output text)

echo "========================================"
echo " Module 08: Automate Scaling"
echo " AMI: ${LATEST_AMI}"
echo "========================================"
echo ""

# --- ACT 1: Launch Template + Auto Scaling Group ---
echo "--- ACT 1: Launch Template + Auto Scaling Group ---"
echo ""

# Create user data (base64 encode - works on both macOS and Linux)
USER_DATA=$(printf '#!/bin/bash\nyum install -y httpd stress\necho Hello from Auto Scaling > /var/www/html/index.html\nsystemctl start httpd' | base64)

# Create a launch template
echo "[1.1] Creating launch template..."
TEMPLATE_ID=$(aws ec2 create-launch-template \
  --launch-template-name demo-scaling-template \
  --launch-template-data "{
    \"ImageId\":\"${LATEST_AMI}\",
    \"InstanceType\":\"t3.micro\",
    \"SecurityGroupIds\":[\"${SG_ID}\"],
    \"IamInstanceProfile\":{\"Arn\":\"${PROFILE_ARN}\"},
    \"UserData\":\"${USER_DATA}\"
  }" \
  --query 'LaunchTemplate.LaunchTemplateId' --output text)
echo "  Template ID: ${TEMPLATE_ID}"
echo ""

# Create ASG with min=1, max=4, desired=2 across two subnets
echo "[1.2] Creating Auto Scaling Group (min=1, max=4, desired=2)..."
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name demo-asg \
  --launch-template LaunchTemplateId=${TEMPLATE_ID},Version='$Latest' \
  --min-size 1 --max-size 4 --desired-capacity 2 \
  --vpc-zone-identifier "${SUBNET_1},${SUBNET_2}" \
  --tags Key=Name,Value=ASG-Instance,PropagateAtLaunch=true
echo "  ✓ ASG created"
echo ""

# Verify ASG configuration
echo "[1.3] ASG configuration:"
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names demo-asg \
  --query 'AutoScalingGroups[0].{Min:MinSize,Max:MaxSize,Desired:DesiredCapacity}' \
  --output table
echo ""

# --- ACT 2: Target Tracking Scaling Policy ---
echo "--- ACT 2: Target Tracking Scaling Policy ---"
echo ""

# Set target tracking at 50% CPU
echo "[2.1] Creating scaling policy (target: 50% CPU)..."
aws autoscaling put-scaling-policy \
  --auto-scaling-group-name demo-asg \
  --policy-name cpu-target-tracking \
  --policy-type TargetTrackingScaling \
  --target-tracking-configuration '{
    "PredefinedMetricSpecification":{"PredefinedMetricType":"ASGAverageCPUUtilization"},
    "TargetValue":50.0,
    "DisableScaleIn":false
  }' --query 'PolicyARN' --output text
echo ""
echo "  Policy: Scale out when CPU > 50%, scale in when CPU < 50%"
echo ""

# --- ACT 3: Trigger Scale Out with CPU Load ---
echo "--- ACT 3: Trigger Scaling - Generate Load ---"
echo ""

# Wait for instances to be ready
echo "[3.1] Waiting for ASG instances to launch (60s)..."
sleep 60

# Get an instance from the ASG
ASG_INSTANCE=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names demo-asg \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' --output text)
echo "  Target instance: ${ASG_INSTANCE}"
echo ""

# Verify SSM connectivity
echo "[3.2] Checking SSM connectivity..."
PING=$(aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=${ASG_INSTANCE}" \
  --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null)
echo "  SSM Status: ${PING}"
echo ""

# Generate CPU stress to trigger scaling
echo "[3.3] Generating CPU stress (180s timeout)..."
aws ssm send-command \
  --instance-ids ${ASG_INSTANCE} \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["stress --cpu 4 --timeout 180 &"]' \
  --comment "Generate CPU load for scaling demo" \
  --query 'Command.CommandId' --output text 2>/dev/null || echo "  (stress command sent)"
echo ""

# Wait for CloudWatch to detect and trigger scaling
echo "[3.4] Waiting for CloudWatch to detect high CPU (90s)..."
sleep 90

# Check scaling activity
echo "[3.5] Scaling activities:"
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name demo-asg \
  --query 'Activities[0:3].{Time:StartTime,Description:Description,Status:StatusCode}' \
  --output table
echo ""

# Verify new desired capacity
echo "[3.6] Current ASG state:"
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names demo-asg \
  --query 'AutoScalingGroups[0].{Desired:DesiredCapacity,Instances:length(Instances)}' \
  --output table
echo ""

echo "========================================"
echo " Demo Complete!"
echo "========================================"
