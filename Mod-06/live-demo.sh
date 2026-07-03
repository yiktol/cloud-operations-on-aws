#!/bin/bash
# Module 06 - Live Demo: Operations as Code with Systems Manager
STACK_NAME="mod06-manage-resources-demo"
if [ -z "$INSTANCE_ID" ]; then
  INSTANCE_ID=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
    --query 'Stacks[0].Outputs[?OutputKey==`InstanceId`].OutputValue' --output text)
fi
echo "Instance: ${INSTANCE_ID}"

echo "============================================"
echo "  ACT 1: RUN COMMAND - EXECUTE AT SCALE"
echo "============================================"
read -p "Press Enter..."
echo ">> Running system check on instance..."
COMMAND_ID=$(aws ssm send-command \
  --instance-ids ${INSTANCE_ID} \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["echo Hello from Systems Manager!","hostname","uptime","df -h"]' \
  --comment "Demo: basic system check" \
  --query Command.CommandId --output text)

sleep 8
aws ssm get-command-invocation \
  --command-id ${COMMAND_ID} \
  --instance-id ${INSTANCE_ID} \
  --query '{Status:Status,Output:StandardOutputContent}' --output text

echo ""
echo ">> Run against ALL instances with a specific tag (scales to thousands)..."
read -p "Press Enter..."
aws ssm send-command \
  --targets "Key=tag:Environment,Values=Production" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["cat /etc/os-release | head -3"]' \
  --comment "Check OS across all Production" \
  --query Command.CommandId --output text
echo ""
echo ">> RESULT: One command hits every tagged server. No SSH. Fully audited."

echo ""
echo "============================================"
echo "  ACT 2: PARAMETER STORE - CENTRALIZED CONFIG"
echo "============================================"
read -p "Press Enter..."
aws ssm put-parameter --name "/demo/app/config/endpoint" \
  --value "https://api.example.com/v2" --type String --overwrite
aws ssm put-parameter --name "/demo/app/secrets/db-password" \
  --value "SuperSecret123!" --type SecureString --overwrite

echo ">> Read plain parameter..."
aws ssm get-parameter --name "/demo/app/config/endpoint" \
  --query 'Parameter.Value' --output text
echo ""
echo ">> Read encrypted parameter (masked)..."
aws ssm get-parameter --name "/demo/app/secrets/db-password" \
  --query 'Parameter.Value' --output text
echo ""
echo ">> Decrypt it..."
aws ssm get-parameter --name "/demo/app/secrets/db-password" \
  --with-decryption --query 'Parameter.Value' --output text
echo ""
echo ">> List all parameters in /demo/ hierarchy..."
aws ssm get-parameters-by-path --path "/demo/app/" --recursive \
  --query 'Parameters[*].{Name:Name,Type:Type}' --output table
echo ""
echo ">> RESULT: Apps reference parameter NAMES not values. Change secrets without redeploying."

echo ""
echo "============================================"
echo "  ACT 3: MAINTENANCE WINDOWS - SCHEDULED OPS"
echo "============================================"
read -p "Press Enter..."
WINDOW_ID=$(aws ssm create-maintenance-window \
  --name "Demo-PatchWindow" \
  --schedule "cron(0 2 ? * SUN *)" \
  --duration 2 --cutoff 1 --allow-unassociated-targets \
  --query WindowId --output text)

TARGET_ID=$(aws ssm register-target-with-maintenance-window \
  --window-id ${WINDOW_ID} --resource-type INSTANCE \
  --targets "Key=tag:PatchGroup,Values=Production-Linux" \
  --query WindowTargetId --output text)

aws ssm register-task-with-maintenance-window \
  --window-id ${WINDOW_ID} --task-arn "AWS-RunPatchBaseline" \
  --task-type RUN_COMMAND \
  --targets "Key=WindowTargetIds,Values=${TARGET_ID}" \
  --task-invocation-parameters '{"RunCommand":{"Parameters":{"Operation":["Install"]}}}' \
  --max-concurrency "50%" --max-errors "25%"

aws ssm describe-maintenance-windows \
  --query 'WindowIdentities[?Name==`Demo-PatchWindow`].{Name:Name,Schedule:Schedule,Duration:Duration}' \
  --output table
echo ""
echo ">> RESULT: Patching runs Sunday 2am, max 50% concurrency, stops at 25% errors."
echo ""
echo "============ DEMO COMPLETE ============"
