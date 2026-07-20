#!/bin/bash
# Module 10 - Live Demo: Data Security and System Auditing
# Prereq: Run deploy.sh first
set -e

STACK_NAME="mod10-security-auditing-demo"
if [ -z "$TOPIC_ARN" ]; then
  TOPIC_ARN=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
    --query 'Stacks[0].Outputs[?OutputKey==`SecurityAlertsTopicArn`].OutputValue' --output text)
fi
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
VPC_ID=$(aws cloudformation list-exports --query "Exports[?Name=='VpcId'].Value" --output text)

echo "========================================"
echo " Module 10: Data Security & Auditing"
echo " Topic: ${TOPIC_ARN}"
echo "========================================"
echo ""

# --- ACT 1: CloudTrail - Who Did What, When ---
echo "--- ACT 1: CloudTrail - Who Did What, When ---"
echo ""

# Recent API activity (last 10 events)
echo "[1.1] Recent API activity:"
aws cloudtrail lookup-events --max-results 10 \
  --query 'Events[*].{Time:EventTime,User:Username,Event:EventName}' --output table
echo ""

# Security group changes
echo "[1.2] Security group modification events:"
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AuthorizeSecurityGroupIngress \
  --max-results 5 \
  --query 'Events[*].{Time:EventTime,User:Username,Event:EventName}' --output table 2>/dev/null || echo "  (No events found)"
echo ""

# IAM user creation events
echo "[1.3] IAM user creation events:"
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=CreateUser \
  --max-results 5 \
  --query 'Events[*].{Time:EventTime,User:Username,Event:EventName}' --output table 2>/dev/null || echo "  (No events found)"
echo ""

# --- ACT 2: EventBridge - Real-Time Detection ---
echo "--- ACT 2: EventBridge - Real-Time Detection ---"
echo ""

# Create rule to detect security group changes in real time
echo "[2.1] Creating EventBridge rule (detect SG changes)..."
aws events put-rule --name "detect-sg-change" \
  --event-pattern '{
    "source":["aws.ec2"],
    "detail-type":["AWS API Call via CloudTrail"],
    "detail":{"eventName":["AuthorizeSecurityGroupIngress"]}
  }' --state ENABLED \
  --query 'RuleArn' --output text
echo ""

# Route matching events to SNS for alerting
echo "[2.2] Adding SNS target..."
aws events put-targets --rule "detect-sg-change" \
  --targets "Id=sns-alert,Arn=${TOPIC_ARN}" \
  --query 'FailedEntryCount' --output text
echo "  ✓ Rule → SNS pipeline configured"
echo ""

# Trigger detection by opening port 22 on a demo security group
echo "[2.3] Creating demo security group and opening port 22..."
DEMO_SG=$(aws ec2 create-security-group --group-name demo-detect-sg \
  --description "Trigger detection demo" --vpc-id ${VPC_ID} \
  --query GroupId --output text 2>/dev/null || \
  aws ec2 describe-security-groups --filters "Name=group-name,Values=demo-detect-sg" \
  --query 'SecurityGroups[0].GroupId' --output text)
echo "  SG: ${DEMO_SG}"

aws ec2 authorize-security-group-ingress \
  --group-id ${DEMO_SG} --protocol tcp --port 22 --cidr 0.0.0.0/0 2>/dev/null || true
echo "  ⚠️  Port 22 opened — EventBridge should trigger alert within seconds!"
echo ""

# --- ACT 3: AWS Config - Compliance Check ---
echo "--- ACT 3: AWS Config - Continuous Compliance ---"
echo ""

# Create Config rule to check for open SSH
echo "[3.1] Creating Config rule (restricted-ssh)..."
aws configservice put-config-rule --config-rule '{
  "ConfigRuleName": "restricted-ssh",
  "Source": {"Owner":"AWS","SourceIdentifier":"INCOMING_SSH_DISABLED"},
  "Scope": {"ComplianceResourceTypes": ["AWS::EC2::SecurityGroup"]}
}' 2>/dev/null || true
echo "  ✓ Rule created"
echo ""

# Trigger evaluation
echo "[3.2] Triggering rule evaluation..."
aws configservice start-config-rules-evaluation \
  --config-rule-names restricted-ssh 2>/dev/null || true
echo "  Waiting 20s for evaluation..."
sleep 20

# Check compliance results
echo "[3.3] Compliance results (NON_COMPLIANT security groups):"
aws configservice get-compliance-details-by-config-rule \
  --config-rule-name restricted-ssh \
  --compliance-types NON_COMPLIANT \
  --query 'EvaluationResults[*].{Resource:EvaluationResultIdentifier.EvaluationResultQualifier.ResourceId,Result:ComplianceType}' \
  --output table 2>/dev/null || echo "  (No results yet - Config may need more time)"
echo ""

echo "========================================"
echo " Demo Complete!"
echo " Pipeline: CloudTrail → EventBridge → SNS → Alert"
echo "========================================"
