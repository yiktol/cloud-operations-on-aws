# Module 07 Demo: Configure Highly Available Systems — "Load Balancing in Action"

## Prerequisites
- AWS CLI configured with admin credentials
- Module 07 CloudFormation stack deployed (`Mod-07/cfn-setup.yaml`)

---

## Part 1: Setup (do before class)

### Deploy the CloudFormation stack
The stack creates: two EC2 web server instances in different AZs (with httpd pre-installed), ALB and instance security groups.

```bash
aws cloudformation deploy \
  --template-file Mod-07/cfn-setup.yaml \
  --stack-name mod07-demo \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    VpcId=<your-vpc-id> \
    PublicSubnet1=<public-subnet-az1> \
    PublicSubnet2=<public-subnet-az2> \
    PrivateSubnet1=<private-subnet-az1> \
    PrivateSubnet2=<private-subnet-az2>
```

### Get resource IDs for the demo
```bash
INSTANCE_1=$(aws cloudformation describe-stacks --stack-name mod07-demo --query "Stacks[0].Outputs[?OutputKey=='Instance1Id'].OutputValue" --output text)
INSTANCE_2=$(aws cloudformation describe-stacks --stack-name mod07-demo --query "Stacks[0].Outputs[?OutputKey=='Instance2Id'].OutputValue" --output text)
VPC_ID=$(aws cloudformation describe-stacks --stack-name mod07-demo --query "Stacks[0].Outputs[?OutputKey=='VPCId'].OutputValue" --output text)
SUBNET_1=$(aws cloudformation describe-stacks --stack-name mod07-demo --query "Stacks[0].Outputs[?OutputKey=='PublicSubnet1Id'].OutputValue" --output text)
SUBNET_2=$(aws cloudformation describe-stacks --stack-name mod07-demo --query "Stacks[0].Outputs[?OutputKey=='PublicSubnet2Id'].OutputValue" --output text)
ALB_SG=$(aws cloudformation describe-stacks --stack-name mod07-demo --query "Stacks[0].Outputs[?OutputKey=='ALBSecurityGroupId'].OutputValue" --output text)
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
  --security-groups ${ALB_SG} \
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

# Delete the stack (removes instances and security groups)
aws cloudformation delete-stack --stack-name mod07-demo
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
