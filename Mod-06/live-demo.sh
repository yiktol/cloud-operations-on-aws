#!/bin/bash
# Module 06 - Live Demo: Operations as Code with Systems Manager
# Prereq: Run deploy.sh first
set -e

STACK_NAME="mod06-manage-resources-demo"
if [ -z "$INSTANCE_ID" ]; then
  INSTANCE_ID=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
    --query 'Stacks[0].Outputs[?OutputKey==`InstanceId`].OutputValue' --output text)
fi

echo "========================================"
echo " Module 06: Operations as Code"
echo " Instance: ${INSTANCE_ID}"
echo "========================================"
echo ""

# --- ACT 1: Run Command - Execute at Scale ---
echo "--- ACT 1: Run Command - Execute at Scale ---"
echo ""

# Run a system check on the instance
echo "[1.1] Running system check via Run Command..."
COMMAND_ID=$(aws ssm send-command \
  --instance-ids ${INSTANCE_ID} \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["echo Hello from Systems Manager!","hostname","uptime","df -h"]' \
  --comment "Demo: basic system check" \
  --query Command.CommandId --output text)
echo "  Command ID: ${COMMAND_ID}"
echo ""

echo "[1.2] Command output:"
sleep 8
aws ssm get-command-invocation \
  --command-id ${COMMAND_ID} \
  --instance-id ${INSTANCE_ID} \
  --query '{Status:Status,Output:StandardOutputContent}' --output text
echo ""

# Run against ALL instances with a specific tag (scales to thousands)
echo "[1.3] Running command against ALL Production-tagged instances:"
aws ssm send-command \
  --targets "Key=tag:Environment,Values=Production" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["cat /etc/os-release | head -3"]' \
  --comment "Check OS across all Production" \
  --query 'Command.{CommandId:CommandId,TargetCount:TargetCount}' --output table
echo ""

# --- ACT 2: Parameter Store - Centralized Config ---
echo "--- ACT 2: Parameter Store - Centralized Configuration ---"
echo ""

# Store a plain-text parameter
echo "[2.1] Storing plain-text parameter:"
aws ssm put-parameter --name "/demo/app/config/endpoint" \
  --value "https://api.example.com/v2" --type String --overwrite \
  --query '{Version:Version,Tier:Tier}' --output table
echo ""

# Store an encrypted parameter (use single quotes to avoid ! expansion)
echo "[2.2] Storing encrypted parameter (SecureString):"
aws ssm put-parameter --name "/demo/app/secrets/db-password" \
  --value 'SuperSecret123!' --type SecureString --overwrite \
  --query '{Version:Version,Tier:Tier}' --output table
echo ""

# Read plain parameter
echo "[2.3] Reading plain parameter:"
aws ssm get-parameter --name "/demo/app/config/endpoint" \
  --query 'Parameter.{Name:Name,Value:Value,Type:Type}' --output table
echo ""

# Read encrypted parameter (masked by default)
echo "[2.4] Reading encrypted parameter (without decryption):"
aws ssm get-parameter --name "/demo/app/secrets/db-password" \
  --query 'Parameter.{Name:Name,Type:Type}' --output table
echo "  Value: (encrypted blob - not human readable)"
echo ""

# Decrypt the parameter
echo "[2.5] Reading with decryption:"
echo -n "  Value: "
aws ssm get-parameter --name "/demo/app/secrets/db-password" \
  --with-decryption --query 'Parameter.Value' --output text
echo ""
echo ""

# List all parameters in /demo/ hierarchy
echo "[2.6] All parameters in /demo/app/ hierarchy:"
aws ssm get-parameters-by-path --path "/demo/app/" --recursive \
  --query 'Parameters[*].{Name:Name,Type:Type}' --output table
echo ""

# --- ACT 3: Maintenance Windows - Scheduled Ops ---
echo "--- ACT 3: Maintenance Windows - Controlled Change ---"
echo ""

# Create a maintenance window (Sundays at 2am, 2hr duration)
echo "[3.1] Creating maintenance window (Sundays 2-4 AM UTC):"
WINDOW_ID=$(aws ssm create-maintenance-window \
  --name "Demo-PatchWindow" \
  --schedule "cron(0 2 ? * SUN *)" \
  --duration 2 --cutoff 1 --allow-unassociated-targets \
  --query WindowId --output text)
echo "  Window ID: ${WINDOW_ID}"
echo ""

# Register Production-Linux instances as targets
echo "[3.2] Registering targets (PatchGroup=Production-Linux):"
TARGET_ID=$(aws ssm register-target-with-maintenance-window \
  --window-id ${WINDOW_ID} --resource-type INSTANCE \
  --targets "Key=tag:PatchGroup,Values=Production-Linux" \
  --query WindowTargetId --output text)
echo "  Target ID: ${TARGET_ID}"
echo ""

# Register the patch baseline task (50% concurrency, 25% error threshold)
echo "[3.3] Registering patch task (50% concurrency, 25% error threshold):"
aws ssm register-task-with-maintenance-window \
  --window-id ${WINDOW_ID} --task-arn "AWS-RunPatchBaseline" \
  --task-type RUN_COMMAND \
  --targets "Key=WindowTargetIds,Values=${TARGET_ID}" \
  --task-invocation-parameters '{"RunCommand":{"Parameters":{"Operation":["Install"]}}}' \
  --max-concurrency "50%" --max-errors "25%" \
  --query 'WindowTaskId' --output text
echo ""

# Verify the maintenance window
echo "[3.4] Maintenance window summary:"
aws ssm describe-maintenance-windows \
  --query 'WindowIdentities[?Name==`Demo-PatchWindow`].{Name:Name,Schedule:Schedule,Duration:Duration}' \
  --output table
echo ""

echo "========================================"
echo " Demo Complete!"
echo "========================================"
