# Module 04 Demo: Deploy and Update Resources — "Tag, Image, Deploy"

## Prerequisites
- AWS CLI configured with admin credentials
- An existing EC2 instance (Amazon Linux 2023)

---

## Part 1: Setup (do before class)

### Step 1: Launch a base EC2 instance

```bash
# Launch a basic instance to use for AMI creation
aws ec2 run-instances \
  --image-id resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --instance-type t3.micro \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=WebServer-Base},{Key=Environment,Value=Development},{Key=CostCenter,Value=CC1234}]' \
  --count 1

# Note the instance ID
INSTANCE_ID="i-XXXXXXXXXXXX"
```

---

## Part 2: Live Demo (in class)

### 🎬 Act 1: Tagging Strategy (Resource Organization)

> **Say:** "Before deploying anything, we need a plan to track and organize resources. Tags are the foundation."

```bash
# Show current tags on the instance
aws ec2 describe-tags \
  --filters "Name=resource-id,Values=${INSTANCE_ID}" \
  --output table

# Add operational tags
aws ec2 create-tags --resources ${INSTANCE_ID} --tags \
  Key=Application,Value=CustomerPortal \
  Key=Owner,Value=TeamAlpha \
  Key=PatchGroup,Value=Production-Linux

# Show all tagged resources by environment
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Environment,Values=Development \
  --output table

# Create a Resource Group based on tags
aws resource-groups create-group \
  --name "Dev-Environment" \
  --resource-query '{
    "Type": "TAG_FILTERS_1_0",
    "Query": "{\"ResourceTypeFilters\":[\"AWS::AllSupported\"],\"TagFilters\":[{\"Key\":\"Environment\",\"Values\":[\"Development\"]}]}"
  }'
```

> **Talking points:**
> - "Tags give you visibility into WHO owns WHAT, and WHERE the cost goes."
> - "Resource Groups let you manage tagged resources as a single unit."
> - "Consistent tagging is the foundation for cost allocation, automation, and access control."

---

### 🎬 Act 2: Create a Golden AMI

> **Say:** "Now let's create a reusable machine image — a 'golden AMI' — that ensures every deployment is consistent."

```bash
# First, install something on the instance to differentiate the AMI
aws ssm send-command \
  --instance-ids ${INSTANCE_ID} \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["sudo yum install -y httpd","sudo systemctl enable httpd","echo HealthCheck > /var/www/html/index.html"]' \
  --comment "Install web server for golden AMI"

# Wait for command to complete
aws ssm list-command-invocations \
  --instance-id ${INSTANCE_ID} \
  --details --output table

# Create the AMI
AMI_ID=$(aws ec2 create-image \
  --instance-id ${INSTANCE_ID} \
  --name "GoldenAMI-WebServer-$(date +%Y%m%d)" \
  --description "Web server with httpd pre-installed" \
  --tag-specifications 'ResourceType=image,Tags=[{Key=Name,Value=GoldenAMI-WebServer},{Key=Version,Value=1.0}]' \
  --query ImageId --output text)

echo "AMI created: ${AMI_ID}"

# Check AMI state
aws ec2 describe-images --image-ids ${AMI_ID} \
  --query 'Images[0].{State:State,Name:Name,Created:CreationDate}' \
  --output table
```

> **Talking points:**
> - "A golden AMI captures your known-good configuration — OS, patches, software, configs."
> - "Every new instance launched from this AMI is identical — no configuration drift."
> - "Version-tag your AMIs so you can track and roll back."

---

### 🎬 Act 3: Deploy from the Golden AMI

> **Say:** "Now let's launch new instances from our golden AMI — guaranteed consistency."

```bash
# Launch 2 instances from the golden AMI
aws ec2 run-instances \
  --image-id ${AMI_ID} \
  --instance-type t3.micro \
  --count 2 \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=WebServer-FromAMI},{Key=Environment,Value=Production},{Key=DeployedFrom,Value=${AMI_ID}}]"

# Verify the web server is already running on the new instances
# (wait ~60 seconds for boot)
NEW_INSTANCE=$(aws ec2 describe-instances \
  --filters "Name=tag:DeployedFrom,Values=${AMI_ID}" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)

aws ssm send-command \
  --instance-ids ${NEW_INSTANCE} \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["systemctl status httpd","curl localhost"]'
```

> **Talking points:**
> - "No post-launch configuration needed — httpd is already running."
> - "The `DeployedFrom` tag creates an audit trail back to the source AMI."
> - "This is the foundation of immutable infrastructure — replace, don't patch."

---

## Part 3: Cleanup

```bash
# Terminate instances
aws ec2 terminate-instances --instance-ids ${INSTANCE_ID}
aws ec2 terminate-instances --instance-ids $(aws ec2 describe-instances \
  --filters "Name=tag:DeployedFrom,Values=${AMI_ID}" \
  --query 'Reservations[*].Instances[*].InstanceId' --output text)

# Deregister AMI and delete snapshot
SNAPSHOT_ID=$(aws ec2 describe-images --image-ids ${AMI_ID} \
  --query 'Images[0].BlockDeviceMappings[0].Ebs.SnapshotId' --output text)
aws ec2 deregister-image --image-id ${AMI_ID}
aws ec2 delete-snapshot --snapshot-id ${SNAPSHOT_ID}

# Delete resource group
aws resource-groups delete-group --group-name "Dev-Environment"
```

---

## Summary Table

| Concept | Tool/Feature | Why it matters |
|---------|-------------|----------------|
| **Tagging** | Tags + Resource Groups | Track ownership, cost, environment |
| **Golden AMI** | EC2 Image Builder / create-image | Consistent, repeatable deployments |
| **Deploy from AMI** | run-instances with AMI ID | Zero drift, immutable infrastructure |

---

## Timing Guide

| Section | Duration |
|---------|----------|
| Act 1 (Tagging) | 4 min |
| Act 2 (Golden AMI) | 5 min |
| Act 3 (Deploy) | 4 min |
| **Total** | **~13 min** |
