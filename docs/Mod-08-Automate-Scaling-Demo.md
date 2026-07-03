# Module 08 Demo: Automate Scaling — "Watch It Scale"

## Prerequisites
- AWS CLI configured with admin credentials
- Default VPC with subnets
- The ALB from Module 07 (or create a new one)

---

## Part 1: Setup (do before class)

```bash
# Get VPC and subnets
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query 'Vpcs[0].VpcId' --output text)
SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" --query 'Subnets[*].SubnetId' --output text)
SUBNET_1=$(echo $SUBNETS | awk '{print $1}')
SUBNET_2=$(echo $SUBNETS | awk '{print $2}')

# Security group
SG_ID=$(aws ec2 create-security-group --group-name demo-asg-sg \
  --description "Demo ASG" --vpc-id ${VPC_ID} --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id ${SG_ID} \
  --protocol tcp --port 80 --cidr 0.0.0.0/0
```

---

## Part 2: Live Demo (in class)

### 🎬 Act 1: Create a Launch Template + Auto Scaling Group

> **Say:** "A Launch Template defines WHAT to launch. An Auto Scaling Group defines HOW MANY and WHERE."

```bash
# Create launch template
USER_DATA=$(echo '#!/bin/bash
yum install -y httpd stress
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
echo "<h1>Instance: ${INSTANCE_ID}</h1><p>Launched by Auto Scaling</p>" > /var/www/html/index.html
systemctl start httpd' | base64)

TEMPLATE_ID=$(aws ec2 create-launch-template \
  --launch-template-name demo-scaling-template \
  --launch-template-data "{
    \"ImageId\":\"resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64\",
    \"InstanceType\":\"t3.micro\",
    \"SecurityGroupIds\":[\"${SG_ID}\"],
    \"UserData\":\"${USER_DATA}\"
  }" --query 'LaunchTemplate.LaunchTemplateId' --output text)

# Create Auto Scaling Group
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name demo-asg \
  --launch-template LaunchTemplateId=${TEMPLATE_ID},Version='$Latest' \
  --min-size 1 --max-size 4 --desired-capacity 2 \
  --vpc-zone-identifier "${SUBNET_1},${SUBNET_2}" \
  --tags Key=Name,Value=ASG-Instance,PropagateAtLaunch=true

# Watch instances launch
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names demo-asg \
  --query 'AutoScalingGroups[0].{Min:MinSize,Max:MaxSize,Desired:DesiredCapacity,Instances:Instances[*].InstanceId}' \
  --output table
```

> **Talking points:**
> - "Min=1 means you always have at least one server running."
> - "Max=4 caps your spending — won't scale beyond 4 no matter what."
> - "Desired=2 is the starting point."

---

### 🎬 Act 2: Attach a Scaling Policy

> **Say:** "Now let's tell Auto Scaling WHEN to add or remove instances — based on CPU utilization."

```bash
# Create a target tracking scaling policy
aws autoscaling put-scaling-policy \
  --auto-scaling-group-name demo-asg \
  --policy-name cpu-target-tracking \
  --policy-type TargetTrackingScaling \
  --target-tracking-configuration '{
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "ASGAverageCPUUtilization"
    },
    "TargetValue": 50.0,
    "ScaleInCooldown": 60,
    "ScaleOutCooldown": 60
  }'

echo "Policy set: Scale out when CPU > 50%, scale in when CPU < 50%"
```

> **Talking point:** "Target tracking is like a thermostat — you set the desired temperature (50% CPU), and Auto Scaling adjusts automatically."

---

### 🎬 Act 3: Trigger Scaling — Generate Load

> **Say:** "Let's stress the instances and watch Auto Scaling add more capacity."

```bash
# Get an instance ID from the ASG
ASG_INSTANCE=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names demo-asg \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' --output text)

# Generate CPU load via SSM Run Command
aws ssm send-command \
  --instance-ids ${ASG_INSTANCE} \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["stress --cpu 4 --timeout 180"]' \
  --comment "Generate CPU load for scaling demo"

# Monitor scaling activity (check every 30 seconds)
echo "Waiting for CloudWatch to detect high CPU..."
sleep 90

# Check scaling activities
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name demo-asg \
  --query 'Activities[*].{Time:StartTime,Description:Description,Status:StatusCode}' \
  --output table

# Check current instance count
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names demo-asg \
  --query 'AutoScalingGroups[0].{Desired:DesiredCapacity,Running:Instances[*].InstanceId}' \
  --output json
```

> **Expected:** After ~2 minutes, new instances are launched.

> **Talking points:**
> - "CloudWatch detected CPU > 50% and told Auto Scaling to add capacity."
> - "When the stress test ends, CPU drops, and it scales BACK IN automatically."
> - "This is reactive scaling — you can also use PREDICTIVE scaling based on historical patterns."

---

## Part 3: Cleanup

```bash
# Delete the ASG (terminates all instances)
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name demo-asg --min-size 0 --desired-capacity 0
sleep 30
aws autoscaling delete-auto-scaling-group --auto-scaling-group-name demo-asg --force-delete

# Delete launch template
aws ec2 delete-launch-template --launch-template-id ${TEMPLATE_ID}

# Delete security group
aws ec2 delete-security-group --group-id ${SG_ID}
```

---

## Summary Table

| Concept | What students see | Key takeaway |
|---------|------------------|------|
| **Launch Template** | Instance blueprint | Consistent launches |
| **ASG** | Min/Max/Desired | Capacity boundaries |
| **Target Tracking** | CPU target = 50% | Thermostat-style automation |
| **Scale Out** | New instances appear | Handles demand spikes |
| **Scale In** | Extra instances removed | Cost optimization |

---

## Timing Guide

| Section | Duration |
|---------|----------|
| Act 1 (ASG creation) | 5 min |
| Act 2 (Scaling policy) | 3 min |
| Act 3 (Trigger + observe) | 7 min |
| **Total** | **~15 min** |
