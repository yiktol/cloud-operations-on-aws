# Module 03 Demo: System Discovery — "Discover & Inventory Your AWS Environment"

## Prerequisites
- AWS CLI configured with admin credentials
- At least one EC2 instance running with SSM Agent installed (Amazon Linux 2/2023 has it by default)
- IAM instance profile with `AmazonSSMManagedInstanceCore` policy attached to the instance
- AWS Config enabled (or be prepared to enable it live)

---

## Part 1: Setup (do before class)

### Step 1: Launch an EC2 instance with SSM access

```bash
# Create an IAM role for EC2 with SSM access
aws iam create-role \
  --role-name EC2-SSM-DemoRole \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "ec2.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }'

aws iam attach-role-policy \
  --role-name EC2-SSM-DemoRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

# Create instance profile
aws iam create-instance-profile --instance-profile-name EC2-SSM-DemoProfile
aws iam add-role-to-instance-profile \
  --instance-profile-name EC2-SSM-DemoProfile \
  --role-name EC2-SSM-DemoRole

# Launch an Amazon Linux 2023 instance (NO key pair, NO public SSH)
aws ec2 run-instances \
  --image-id resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --instance-type t3.micro \
  --iam-instance-profile Name=EC2-SSM-DemoProfile \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=Demo-SSM-Instance},{Key=Environment,Value=Production}]' \
  --count 1

# Note the instance ID from the output
INSTANCE_ID="i-XXXXXXXXXXXX"
```

### Step 2: Enable AWS Config (if not already enabled)

```bash
# Create an S3 bucket for Config
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=$(aws configure get region)
CONFIG_BUCKET="config-bucket-${ACCOUNT_ID}-${REGION}"

aws s3 mb s3://${CONFIG_BUCKET}

# Create Config service role
aws iam create-service-linked-role --aws-service-name config.amazonaws.com

# Set up the configuration recorder
aws configservice put-configuration-recorder \
  --configuration-recorder name=default,roleARN=arn:aws:iam::${ACCOUNT_ID}:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig \
  --recording-group allSupported=true,includeGlobalResourceTypes=true

# Set up delivery channel
aws configservice put-delivery-channel \
  --delivery-channel name=default,s3BucketName=${CONFIG_BUCKET}

# Start recording
aws configservice start-configuration-recorder --configuration-recorder-name default
```

### Step 3: Add a Config rule for compliance demo

```bash
# Rule: EC2 instances must be managed by Systems Manager
aws configservice put-config-rule --config-rule '{
  "ConfigRuleName": "ec2-instance-managed-by-systems-manager",
  "Source": {
    "Owner": "AWS",
    "SourceIdentifier": "EC2_INSTANCE_MANAGED_BY_SSM"
  },
  "Scope": {
    "ComplianceResourceTypes": ["AWS::EC2::Instance"]
  }
}'

# Rule: EC2 instances should not have public IPs
aws configservice put-config-rule --config-rule '{
  "ConfigRuleName": "ec2-instance-no-public-ip",
  "Source": {
    "Owner": "AWS",
    "SourceIdentifier": "EC2_INSTANCE_NO_PUBLIC_IP"
  },
  "Scope": {
    "ComplianceResourceTypes": ["AWS::EC2::Instance"]
  }
}'
```

### Step 4: Set up Systems Manager Inventory collection

```bash
# Create an inventory association (collects every 30 minutes)
aws ssm create-association \
  --name "AWS-GatherSoftwareInventory" \
  --targets "Key=InstanceIds,Values=${INSTANCE_ID}" \
  --schedule-expression "rate(30 minutes)" \
  --parameters '{
    "applications": ["Enabled"],
    "awsComponents": ["Enabled"],
    "networkConfig": ["Enabled"],
    "windowsUpdates": ["Enabled"],
    "services": ["Enabled"]
  }'
```

> **Wait 5–10 minutes** for inventory to be collected and Config to evaluate rules.

---

## Part 2: Live Demo (in class)

---

### 🎬 Act 1: Connect Without SSH (Session Manager)

> **Say:** "Traditionally, to access a Linux server you need SSH keys, a bastion host, and port 22 open. Let's connect to an instance that has NONE of those."

```bash
# Show the instance has no key pair and no public IP
aws ec2 describe-instances --instance-ids ${INSTANCE_ID} \
  --query 'Reservations[0].Instances[0].{KeyName:KeyName, PublicIP:PublicIpAddress, SecurityGroups:SecurityGroups[*].GroupId}' \
  --output table
```

> **Point out:** No KeyName, No public IP.

```bash
# Show it's a managed instance
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=${INSTANCE_ID}" \
  --query 'InstanceInformationList[0].{InstanceId:InstanceId, PingStatus:PingStatus, Platform:PlatformName, AgentVersion:AgentVersion}' \
  --output table
```

> **Start a session:**

```bash
aws ssm start-session --target ${INSTANCE_ID}
```

> **Inside the session:**

```bash
# Show who you are
whoami
# Output: ssm-user

# Show you have sudo access
sudo su -
whoami
# Output: root

# Show system info
hostname
cat /etc/os-release
uptime

# Exit cleanly
exit
exit
```

> **Talking points:**
> - "No SSH keys anywhere. No port 22 open. No bastion host."
> - "Access is controlled 100% by IAM — I can restrict which users access which instances."
> - "Every session is logged to CloudTrail. You can even stream keystrokes to S3 or CloudWatch Logs."

---

### 🎬 Act 2: Inventory — What's INSIDE the Instance

> **Say:** "Now let's see what Systems Manager knows about what's running on this instance — software, OS, network config — all collected automatically by the agent."

```bash
# List installed applications
aws ssm list-inventory-entries \
  --instance-id ${INSTANCE_ID} \
  --type-name "AWS:Application" \
  --output table
```

> **Show the list of installed packages/applications.**

```bash
# Show network configuration
aws ssm list-inventory-entries \
  --instance-id ${INSTANCE_ID} \
  --type-name "AWS:Network" \
  --output table
```

```bash
# Show AWS components (SSM Agent version, etc.)
aws ssm list-inventory-entries \
  --instance-id ${INSTANCE_ID} \
  --type-name "AWS:AWSComponent" \
  --output table
```

```bash
# Show instance detailed info
aws ssm list-inventory-entries \
  --instance-id ${INSTANCE_ID} \
  --type-name "AWS:InstanceDetailedInformation" \
  --output table
```

> **Talking points:**
> - "Systems Manager Inventory tells you what's INSIDE — OS version, installed software, patches, network interfaces."
> - "This runs on a schedule — you always have an up-to-date picture."
> - "Compare this to AWS Config which shows the AWS infrastructure AROUND it (VPC, security groups, IAM roles)."

---

### 🎬 Act 3: AWS Config — Continuous Compliance

> **Say:** "Now let's look at the bigger picture — AWS Config continuously records your resource configurations and evaluates them against rules."

```bash
# Show discovered resources
aws configservice get-discovered-resource-counts --output table
```

> **Point out the variety — EC2, VPC, Security Groups, IAM, etc.**

```bash
# Check compliance summary
aws configservice get-compliance-summary-by-config-rule --output table
```

```bash
# Check our SSM rule — which instances are compliant?
aws configservice get-compliance-details-by-config-rule \
  --config-rule-name ec2-instance-managed-by-systems-manager \
  --output table
```

> **Expected:** Demo instance shows COMPLIANT ✅ (it has SSM agent)

```bash
# Check the no-public-IP rule
aws configservice get-compliance-details-by-config-rule \
  --config-rule-name ec2-instance-no-public-ip \
  --output table
```

> **Expected:** Demo instance shows COMPLIANT ✅ (no public IP)

```bash
# Show resource configuration history (how Config tracks changes)
aws configservice get-resource-config-history \
  --resource-type AWS::EC2::Instance \
  --resource-id ${INSTANCE_ID} \
  --limit 3 \
  --query 'configurationItems[*].{Time:configurationItemCaptureTime, State:resourceCreationTime, Config:configuration}' \
  --output table
```

> **Talking points:**
> - "AWS Config is like a security camera for your infrastructure — it records every configuration change."
> - "Rules evaluate automatically. If someone attaches a public IP to this instance, it'll flip to NON_COMPLIANT within minutes."
> - "You can aggregate this across ALL accounts in your Organization."

---

### 🎬 Bonus: Show the Console (visual reinforcement)

Open the AWS Console and show:

1. **Systems Manager → Session Manager → Session history** — show the logged session from Act 1
2. **Systems Manager → Inventory** — show the visual dashboard of all managed instances
3. **AWS Config → Dashboard** — show the compliance pie chart
4. **AWS Config → Resources** — search for the EC2 instance, show its configuration timeline

> **Talking point:** "Everything we did via CLI is also visible here. The CLI is great for automation and scripting; the console gives you the bird's-eye view."

---

## Part 3: Cleanup

```bash
# Delete the Config rules
aws configservice delete-config-rule --config-rule-name ec2-instance-managed-by-systems-manager
aws configservice delete-config-rule --config-rule-name ec2-instance-no-public-ip

# Stop Config recorder
aws configservice stop-configuration-recorder --configuration-recorder-name default

# Delete the SSM association
ASSOC_ID=$(aws ssm list-associations --query "Associations[?Name=='AWS-GatherSoftwareInventory'].AssociationId" --output text)
aws ssm delete-association --association-id ${ASSOC_ID}

# Terminate the EC2 instance
aws ec2 terminate-instances --instance-ids ${INSTANCE_ID}

# Wait for termination, then clean up IAM
aws iam remove-role-from-instance-profile \
  --instance-profile-name EC2-SSM-DemoProfile \
  --role-name EC2-SSM-DemoRole
aws iam delete-instance-profile --instance-profile-name EC2-SSM-DemoProfile
aws iam detach-role-policy \
  --role-name EC2-SSM-DemoRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws iam delete-role --role-name EC2-SSM-DemoRole

# Delete Config S3 bucket
aws s3 rb s3://${CONFIG_BUCKET} --force
```

---

## Summary Table for Whiteboard

| Tool | What it discovers | How |
|------|------------------|-----|
| **Session Manager** | Live access to instance internals | Interactive shell via SSM Agent |
| **SSM Inventory** | Software, OS, patches, network config | Agent collects on schedule |
| **AWS Config** | AWS resource configurations + changes | API-level recording + rules |

**Key insight:** SSM Inventory = what's **inside** instances. AWS Config = what's **around** them in AWS.

---

## Timing Guide

| Section | Duration |
|---------|----------|
| Act 1 (Session Manager) | 4 min |
| Act 2 (SSM Inventory) | 4 min |
| Act 3 (AWS Config) | 5 min |
| Bonus (Console walkthrough) | 3 min |
| **Total** | **~16 min** |
