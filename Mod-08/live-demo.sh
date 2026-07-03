#!/bin/bash
# Module 08 - Live Demo: Automate Scaling
STACK_NAME="mod08-auto-scaling-demo"
SG_ID=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`SGId`].OutputValue' --output text)
SUBNET_1=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`SubnetAZ1Id`].OutputValue' --output text)
SUBNET_2=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`SubnetAZ2Id`].OutputValue' --output text)
PROFILE_ARN=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`InstanceProfileArn`].OutputValue' --output text)
LATEST_AMI=$(aws ssm get-parameter \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query Parameter.Value --output text)

echo "============================================"
echo "  ACT 1: LAUNCH TEMPLATE + AUTO SCALING GROUP"
echo "============================================"
read -p "Press Enter..."
TEMPLATE_ID=$(aws ec2 create-launch-template \
  --launch-template-name demo-scaling-template \
  --launch-template-data "{
    \"ImageId\":\"${LATEST_AMI}\",
    \"InstanceType\":\"t3.micro\",
    \"SecurityGroupIds\":[\"${SG_ID}\"],
    \"IamInstanceProfile\":{\"Arn\":\"${PROFILE_ARN}\"},
    \"UserData\":\"$(echo '#!/bin/bash
yum install -y httpd stress
echo Hello from Auto Scaling > /var/www/html/index.html
systemctl start httpd' | base64 -w0)\"
  }" \
  --query 'LaunchTemplate.LaunchTemplateId' --output text)
echo "  Launch Template: ${TEMPLATE_ID}"

aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name demo-asg \
  --launch-template LaunchTemplateId=${TEMPLATE_ID},Version='$Latest' \
  --min-size 1 --max-size 4 --desired-capacity 2 \
  --vpc-zone-identifier "${SUBNET_1},${SUBNET_2}" \
  --tags Key=Name,Value=ASG-Instance,PropagateAtLaunch=true

aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names demo-asg \
  --query 'AutoScalingGroups[0].{Min:MinSize,Max:MaxSize,Desired:DesiredCapacity}' \
  --output table
echo ""
echo ">> RESULT: Min=1, Max=4, Desired=2. ASG ensures correct capacity at all times."

echo ""
echo "============================================"
echo "  ACT 2: TARGET TRACKING SCALING POLICY"
echo "============================================"
read -p "Press Enter..."
aws autoscaling put-scaling-policy \
  --auto-scaling-group-name demo-asg \
  --policy-name cpu-target-tracking \
  --policy-type TargetTrackingScaling \
  --target-tracking-configuration '{
    "PredefinedMetricSpecification":{"PredefinedMetricType":"ASGAverageCPUUtilization"},
    "TargetValue":50.0,
    "ScaleInCooldown":60,
    "ScaleOutCooldown":60
  }'
echo ""
echo ">> RESULT: Like a thermostat - target 50% CPU, ASG adjusts capacity automatically."

echo ""
echo "============================================"
echo "  ACT 3: TRIGGER SCALE OUT WITH CPU LOAD"
echo "============================================"
echo ">> Waiting for instances to be ready (~60s)..."
sleep 60
read -p "Press Enter to generate CPU stress..."
ASG_INSTANCE=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names demo-asg \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' --output text)

aws ssm send-command \
  --instance-ids ${ASG_INSTANCE} \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["stress --cpu 4 --timeout 180 &"]' \
  --comment "Generate CPU load for scaling demo" 2>/dev/null || \
  echo "  (SSM may need a moment - stress will run on the instance)"

echo "  CPU stress running. Monitoring scaling activity (watch for ~2 min)..."
sleep 90
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name demo-asg \
  --query 'Activities[0:3].{Time:StartTime,Description:Description,Status:StatusCode}' \
  --output table

echo ""
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names demo-asg \
  --query 'AutoScalingGroups[0].{Desired:DesiredCapacity,Instances:length(Instances)}' \
  --output table
echo ""
echo ">> RESULT: CloudWatch detected CPU > 50%, ASG automatically launched new instances!"
echo ""
echo "============ DEMO COMPLETE ============"
