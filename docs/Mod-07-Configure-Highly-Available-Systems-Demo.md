# Module 07 Demo: Configure Highly Available Systems — "Load Balancing in Action"

## Prerequisites
- AWS CLI configured with admin credentials
- A VPC with at least 2 public subnets in different AZs

---

## Part 1: Setup (do before class)

```bash
# Get default VPC and subnets
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query 'Vpcs[0].VpcId' --output text)
SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" --query 'Subnets[*].SubnetId' --output text)
SUBNET_1=$(echo $SUBNETS | awk '{print $1}')
SUBNET_2=$(echo $SUBNETS | awk '{print $2}')

# Create a security group for the ALB and instances
SG_ID=$(aws ec2 create-security-group \
  --group-name demo-ha-sg \
  --description "Demo HA security group" \
  --vpc-id ${VPC_ID} \
  --query GroupId --output text)

aws ec2 authorize-security-group-ingress --group-id ${SG_ID} \
  --protocol tcp --port 80 --cidr 0.0.0.0/0

# Launch 2 web server instances in different AZs
USER_DATA=$(echo '#!/bin/bash
yum install -y httpd
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
echo "<h1>Hello from ${INSTANCE_ID}</h1><p>Availability Zone: ${AZ}</p>" > /var/www/html/index.html
systemctl start httpd
systemctl enable httpd' | base64)

INSTANCE_1=$(aws ec2 run-instances \
  --image-id resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --instance-type t3.micro --subnet-id ${SUBNET_1} \
  --security-group-ids ${SG_ID} \
  --user-data "${USER_DATA}" \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=Web-AZ1}]' \
  --query 'Instances[0].InstanceId' --output text)

INSTANCE_2=$(aws ec2 run-instances \
  --image-id resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --instance-type t3.micro --subnet-id ${SUBNET_2} \
  --security-group-ids ${SG_ID} \
  --user-data "${USER_DATA}" \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=Web-AZ2}]' \
  --query 'Instances[0].InstanceId' --output text)

echo "Instance 1: ${INSTANCE_1} (AZ1)"
echo "Instance 2: ${INSTANCE_2} (AZ2)"
```

---

## Part 2: Live Demo (in class)

### 🎬 Act 1: Create an Application Load Balancer

> **Say:** "We have two web servers in different Availability Zones. Let's put a load balancer in front to distribute traffic and provide fault tolerance."

```bash
# Create the ALB
ALB_ARN=$(aws elbv2 create-load-balancer \
  --name demo-ha-alb \
  --subnets ${SUBNET_1} ${SUBNET_2} \
  --security-groups ${SG_ID} \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)

# Get the DNS name
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns ${ALB_ARN} \
  --query 'LoadBalancers[0].DNSName' --output text)

echo "ALB DNS: ${ALB_DNS}"

# Create target group
TG_ARN=$(aws elbv2 create-target-group \
  --name demo-ha-targets \
  --protocol HTTP --port 80 \
  --vpc-id ${VPC_ID} \
  --health-check-path "/" \
  --query 'TargetGroups[0].TargetGroupArn' --output text)

# Register both instances
aws elbv2 register-targets --target-group-arn ${TG_ARN} \
  --targets Id=${INSTANCE_1} Id=${INSTANCE_2}

# Create listener
aws elbv2 create-listener \
  --load-balancer-arn ${ALB_ARN} \
  --protocol HTTP --port 80 \
  --default-actions Type=forward,TargetGroupArn=${TG_ARN}
```

> **Talking point:** "The ALB spans multiple AZs. If one AZ goes down, traffic automatically routes to the other."

---

### 🎬 Act 2: Health Checks and Traffic Distribution

> **Say:** "Let's see the load balancer distributing traffic between our two servers."

```bash
# Check target health
aws elbv2 describe-target-health --target-group-arn ${TG_ARN} \
  --query 'TargetHealthDescriptions[*].{Instance:Target.Id,Health:TargetHealth.State}' \
  --output table

# Hit the ALB multiple times — observe different instance IDs
for i in {1..6}; do
  curl -s http://${ALB_DNS} | grep -o 'i-[a-z0-9]*'
done
```

> **Expected:** Alternating instance IDs — traffic is balanced across both.

> **Talking points:**
> - "Health checks run every 30 seconds. Unhealthy instances get removed automatically."
> - "Round-robin distribution — each request goes to a different server."

---

### 🎬 Act 3: Simulate Failure — High Availability in Action

> **Say:** "Now let's simulate an AZ failure by stopping one instance. Watch what happens."

```bash
# Stop instance 1 (simulating AZ failure)
aws ec2 stop-instances --instance-ids ${INSTANCE_1}

# Wait for health check to detect it (30-60 seconds)
sleep 45

# Check target health — one should be unhealthy
aws elbv2 describe-target-health --target-group-arn ${TG_ARN} \
  --query 'TargetHealthDescriptions[*].{Instance:Target.Id,Health:TargetHealth.State}' \
  --output table

# Hit the ALB — ALL traffic now goes to the healthy instance
for i in {1..4}; do
  curl -s http://${ALB_DNS} | grep -o 'i-[a-z0-9]*'
done
```

> **Expected:** Only Instance 2 responds — automatic failover!

> **Talking points:**
> - "The user never sees an error. The ALB detected the failure and rerouted."
> - "This is HIGH AVAILABILITY — no human intervention required."
> - "Combine this with Auto Scaling (Module 8) to automatically REPLACE the failed instance."

---

## Part 3: Cleanup

```bash
# Delete listener, target group, and ALB
LISTENER_ARN=$(aws elbv2 describe-listeners --load-balancer-arn ${ALB_ARN} --query 'Listeners[0].ListenerArn' --output text)
aws elbv2 delete-listener --listener-arn ${LISTENER_ARN}
aws elbv2 delete-target-group --target-group-arn ${TG_ARN}
aws elbv2 delete-load-balancer --load-balancer-arn ${ALB_ARN}

# Terminate instances
aws ec2 terminate-instances --instance-ids ${INSTANCE_1} ${INSTANCE_2}

# Wait then delete security group
sleep 60
aws ec2 delete-security-group --group-id ${SG_ID}
```

---

## Summary Table

| Concept | What students see | Key takeaway |
|---------|------------------|------|
| **ALB creation** | One DNS across multiple AZs | Single entry point |
| **Health checks** | Healthy/unhealthy status | Automatic detection |
| **Failover** | Traffic reroutes instantly | Zero-downtime HA |

---

## Timing Guide

| Section | Duration |
|---------|----------|
| Act 1 (Create ALB) | 5 min |
| Act 2 (Traffic distribution) | 4 min |
| Act 3 (Simulate failure) | 5 min |
| **Total** | **~14 min** |
