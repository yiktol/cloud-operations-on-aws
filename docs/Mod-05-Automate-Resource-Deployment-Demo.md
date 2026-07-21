# Module 05 Demo: Automate Resource Deployment — "Infrastructure as Code with CloudFormation"

## Prerequisites
- AWS CLI configured with admin credentials
- Module 05 CloudFormation stack deployed (`Mod-05/cfn-setup.yaml`) — creates an S3 bucket for templates
- The `webapp-stack.yaml` template file (included in `Mod-05/`)

---

## Part 1: Setup (do before class)

### Deploy the setup stack
The stack creates an S3 bucket for storing demo templates.

```bash
aws cloudformation deploy \
  --template-file Mod-05/cfn-setup.yaml \
  --stack-name mod05-demo \
  --capabilities CAPABILITY_NAMED_IAM
```

### Get the template bucket name
```bash
TEMPLATE_BUCKET=$(aws cloudformation describe-stacks --stack-name mod05-demo --query "Stacks[0].Outputs[?OutputKey=='TemplateBucketName'].OutputValue" --output text)
```

---

## Part 2: Live Demo (in class)

### 🎬 Act 1: Validate and Deploy the Stack

> **Say:** "Instead of manually clicking through the console to create a VPC, subnet, security group, and instance — we define it ALL in one template file and let CloudFormation handle it."

```bash
# Show the template (highlight Parameters, Mappings, Resources, Outputs)
cat Mod-05/webapp-stack.yaml

# Validate the template
aws cloudformation validate-template --template-body file://Mod-05/webapp-stack.yaml

# Deploy as Development
aws cloudformation create-stack \
  --stack-name demo-webapp-dev \
  --template-body file://Mod-05/webapp-stack.yaml \
  --parameters ParameterKey=EnvironmentType,ParameterValue=Development

# Watch the stack creation events in real-time
aws cloudformation describe-stack-events \
  --stack-name demo-webapp-dev \
  --query 'StackEvents[*].{Time:Timestamp,Resource:LogicalResourceId,Status:ResourceStatus}' \
  --output table
```

> **Talking points:**
> - "One YAML file creates: VPC, Subnet, Security Group, EC2 instance — all wired together."
> - "Parameters make it reusable — same template, different environments."
> - "Mappings select the right instance type based on the environment."

---

### 🎬 Act 2: Stack Outputs and Drift Detection

> **Say:** "CloudFormation tracks everything it created. Let's see the outputs and then detect if anyone makes manual changes."

```bash
# Check stack status
aws cloudformation describe-stacks --stack-name demo-webapp-dev \
  --query 'Stacks[0].{Status:StackStatus,Outputs:Outputs}' \
  --output table

# List all resources created by the stack
aws cloudformation list-stack-resources --stack-name demo-webapp-dev \
  --query 'StackResourceSummaries[*].{Type:ResourceType,LogicalId:LogicalResourceId,PhysicalId:PhysicalResourceId,Status:ResourceStatus}' \
  --output table

# Initiate drift detection
DRIFT_ID=$(aws cloudformation detect-stack-drift \
  --stack-name demo-webapp-dev \
  --query StackDriftDetectionId --output text)

# Check drift results (after a few seconds)
sleep 10
aws cloudformation describe-stack-drift-detection-status \
  --stack-drift-detection-id ${DRIFT_ID}
```

> **Talking point:** "If someone manually changes a security group rule, CloudFormation will detect the DRIFT — your infrastructure reality no longer matches your code."

---

### 🎬 Act 3: Update the Stack (Change Sets)

> **Say:** "What if we want to promote this to Production? We use a change set to PREVIEW changes before applying them."

```bash
# Create a change set to upgrade to Production
aws cloudformation create-change-set \
  --stack-name demo-webapp-dev \
  --change-set-name upgrade-to-production \
  --parameters ParameterKey=EnvironmentType,ParameterValue=Production

# Preview what will change
aws cloudformation describe-change-set \
  --stack-name demo-webapp-dev \
  --change-set-name upgrade-to-production \
  --query 'Changes[*].ResourceChange.{Action:Action,Resource:LogicalResourceId,Replacement:Replacement}' \
  --output table
```

> **Talking points:**
> - "Change sets show you EXACTLY what will change before you execute."
> - "Replace vs. Modify — some changes require the resource to be recreated."
> - "This is how you safely evolve infrastructure in production."

---

## Part 3: Cleanup

```bash
# Delete the demo webapp stack
aws cloudformation delete-stack --stack-name demo-webapp-dev

# Delete the setup stack
aws cloudformation delete-stack --stack-name mod05-demo
```

---

## Summary Table

| Concept | What students see | Key takeaway |
|---------|------------------|------|
| **Template** | YAML defining full infrastructure | Infrastructure as Code |
| **Parameters/Mappings** | Same template, different configs | Reusability |
| **Stack events** | Real-time resource creation | Dependency management |
| **Drift detection** | Detect manual changes | Compliance |
| **Change sets** | Preview before apply | Safe updates |

---

## Timing Guide

| Section | Duration |
|---------|----------|
| Act 1 (Deploy) | 5 min |
| Act 2 (Outputs + Drift) | 4 min |
| Act 3 (Change Sets) | 4 min |
| **Total** | **~13 min** |
