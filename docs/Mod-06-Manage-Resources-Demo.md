# Module 06 Demo: Manage Resources — "Operations as Code with Systems Manager"

## Prerequisites
- AWS CLI configured with admin credentials
- At least one EC2 instance with SSM Agent running
- Instance must have `AmazonSSMManagedInstanceCore` IAM role

---

## Part 1: Setup (do before class)

```bash
# Use an existing managed instance or launch one (see Module 03 setup)
INSTANCE_ID="i-XXXXXXXXXXXX"

# Verify it's managed
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=${INSTANCE_ID}" \
  --query 'InstanceInformationList[0].PingStatus'
```

---

## Part 2: Live Demo (in class)

### 🎬 Act 1: Run Command — Execute at Scale

> **Say:** "Instead of SSH-ing into each server one by one, Run Command lets you execute operations on hundreds of instances simultaneously."

```bash
# Run a simple command on the instance
COMMAND_ID=$(aws ssm send-command \
  --instance-ids ${INSTANCE_ID} \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["echo Hello from Systems Manager!","hostname","uptime","df -h"]' \
  --comment "Demo: basic system check" \
  --query Command.CommandId --output text)

# View the output
sleep 5
aws ssm get-command-invocation \
  --command-id ${COMMAND_ID} \
  --instance-id ${INSTANCE_ID} \
  --query '{Status:Status,Output:StandardOutputContent}' \
  --output text

# Run against MULTIPLE instances by tag (scales to thousands)
aws ssm send-command \
  --targets "Key=tag:Environment,Values=Production" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["cat /etc/os-release"]' \
  --comment "Check OS version across all Production instances"
```

> **Talking points:**
> - "No SSH. No bastion. No key management. Works across hundreds of instances."
> - "Target by tag — 'run this on ALL production servers' — one command."
> - "Every execution is logged and auditable via CloudTrail."

---

### 🎬 Act 2: Parameter Store — Centralized Configuration

> **Say:** "Hard-coding database passwords or API keys in your application is a security risk. Parameter Store gives you centralized, encrypted configuration."

```bash
# Store a plain text parameter
aws ssm put-parameter \
  --name "/demo/app/config/endpoint" \
  --value "https://api.example.com/v2" \
  --type String \
  --description "API endpoint for demo application"

# Store a secret (encrypted with KMS)
aws ssm put-parameter \
  --name "/demo/app/secrets/db-password" \
  --value "SuperSecret123!" \
  --type SecureString \
  --description "Database password"

# Retrieve the plain parameter
aws ssm get-parameter --name "/demo/app/config/endpoint"

# Retrieve the secret (notice: Value is encrypted)
aws ssm get-parameter --name "/demo/app/secrets/db-password"

# Decrypt it explicitly
aws ssm get-parameter --name "/demo/app/secrets/db-password" --with-decryption

# List all parameters in a hierarchy
aws ssm get-parameters-by-path --path "/demo/app/" --recursive \
  --query 'Parameters[*].{Name:Name,Type:Type}' --output table
```

> **Talking points:**
> - "Applications reference parameter NAMES, not values — change the value without redeploying."
> - "SecureString encrypts with KMS — access controlled by IAM."
> - "Hierarchical paths let you organize: /prod/app/db-password vs /dev/app/db-password."

---

### 🎬 Act 3: Maintenance Windows — Controlled Change

> **Say:** "Patching and updates should happen on YOUR schedule, not randomly. Maintenance Windows define when operations are allowed."

```bash
# Create a maintenance window (every Sunday 2-4 AM UTC)
WINDOW_ID=$(aws ssm create-maintenance-window \
  --name "Demo-PatchWindow" \
  --schedule "cron(0 2 ? * SUN *)" \
  --duration 2 \
  --cutoff 1 \
  --allow-unassociated-targets \
  --query WindowId --output text)

echo "Maintenance Window: ${WINDOW_ID}"

# Register targets (instances by tag)
TARGET_ID=$(aws ssm register-target-with-maintenance-window \
  --window-id ${WINDOW_ID} \
  --resource-type INSTANCE \
  --targets "Key=tag:PatchGroup,Values=Production-Linux" \
  --query WindowTargetId --output text)

# Register a task (patch the instances)
aws ssm register-task-with-maintenance-window \
  --window-id ${WINDOW_ID} \
  --task-arn "AWS-RunPatchBaseline" \
  --task-type RUN_COMMAND \
  --targets "Key=WindowTargetIds,Values=${TARGET_ID}" \
  --task-invocation-parameters '{
    "RunCommand": {
      "Parameters": {"Operation": ["Install"]}
    }
  }' \
  --max-concurrency "50%" \
  --max-errors "25%"

# Show the maintenance window summary
aws ssm describe-maintenance-windows \
  --query 'WindowIdentities[*].{Name:Name,Schedule:Schedule,Duration:Duration}' \
  --output table
```

> **Talking points:**
> - "Maintenance Windows define WHEN changes can happen — controlled blast radius."
> - "max-concurrency 50% = only patch half the fleet at once (keep the rest serving traffic)."
> - "max-errors 25% = stop patching if too many failures (circuit breaker)."

---

## Part 3: Cleanup

```bash
# Delete maintenance window
aws ssm deregister-target-from-maintenance-window \
  --window-id ${WINDOW_ID} --window-target-id ${TARGET_ID}
aws ssm delete-maintenance-window --window-id ${WINDOW_ID}

# Delete parameters
aws ssm delete-parameters --names "/demo/app/config/endpoint" "/demo/app/secrets/db-password"
```

---

## Summary Table

| Tool | What it does | Key benefit |
|------|-------------|-------------|
| **Run Command** | Execute scripts remotely at scale | No SSH, tag-based targeting |
| **Parameter Store** | Centralized config & secrets | Encrypted, versioned, IAM-controlled |
| **Maintenance Windows** | Scheduled operations | Controlled timing, rate limiting |

---

## Timing Guide

| Section | Duration |
|---------|----------|
| Act 1 (Run Command) | 5 min |
| Act 2 (Parameter Store) | 5 min |
| Act 3 (Maintenance Windows) | 5 min |
| **Total** | **~15 min** |
