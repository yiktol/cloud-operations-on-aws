#!/bin/bash
# Module 10 - Live Demo: Data Security and System Auditing
STACK_NAME="mod10-security-auditing-demo"
if [ -z "$TOPIC_ARN" ]; then
  TOPIC_ARN=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
    --query 'Stacks[0].Outputs[?OutputKey==`SecurityAlertsTopicArn`].OutputValue' --output text)
fi
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Alert Topic: ${TOPIC_ARN}"

echo "============================================"
echo "  ACT 1: CLOUDTRAIL - WHO DID WHAT, WHEN"
echo "============================================"
read -p "Press Enter..."
echo ">> Recent API activity (last 10 events)..."
aws cloudtrail lookup-events --max-results 10 \
  --query 'Events[*].{Time:EventTime,User:Username,Event:EventName}' --output table

echo ""
echo ">> IAM user creation events..."
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=CreateUser \
  --max-results 5 \
  --query 'Events[*].{Time:EventTime,User:Username,Event:EventName}' --output table

echo ""
echo ">> Security group changes..."
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AuthorizeSecurityGroupIngress \
  --max-results 5 \
  --query 'Events[*].{Time:EventTime,User:Username,Event:EventName}' --output table
echo ""
echo ">> RESULT: Every API call is auditable. Forensic evidence for security incidents."

echo ""
echo "============================================"
echo "  ACT 2: EVENTBRIDGE - REAL-TIME DETECTION"
echo "============================================"
read -p "Press Enter..."
aws events put-rule --name "detect-sg-change" \
  --event-pattern '{
    "source":["aws.ec2"],
    "detail-type":["AWS API Call via CloudTrail"],
    "detail":{"eventName":["AuthorizeSecurityGroupIngress"]}
  }' --state ENABLED

aws events put-targets --rule "detect-sg-change" \
  --targets "Id=sns-alert,Arn=${TOPIC_ARN}"
echo "  EventBridge rule active - any security group change triggers SNS alert."

echo ""
read -p "Press Enter to trigger detection (add a security group rule)..."
DEMO_SG=$(aws ec2 create-security-group --group-name demo-detect-sg \
  --description "Trigger detection demo" --query GroupId --output text 2>/dev/null || \
  aws ec2 describe-security-groups --filters "Name=group-name,Values=demo-detect-sg" \
  --query 'SecurityGroups[0].GroupId' --output text)

aws ec2 authorize-security-group-ingress \
  --group-id ${DEMO_SG} --protocol tcp --port 22 --cidr 0.0.0.0/0
echo "  Port 22 opened! Check your email - an alert should arrive within seconds."
echo ""
echo ">> RESULT: Detection within seconds. No polling. Event-driven security."

echo ""
echo "============================================"
echo "  ACT 3: AWS CONFIG - AUTO-REMEDIATION"
echo "============================================"
read -p "Press Enter..."
aws configservice put-config-rule --config-rule '{
  "ConfigRuleName": "restricted-ssh",
  "Source": {"Owner":"AWS","SourceIdentifier":"INCOMING_SSH_DISABLED"},
  "Scope": {"ComplianceResourceTypes": ["AWS::EC2::SecurityGroup"]}
}' 2>/dev/null || true

sleep 15
aws configservice get-compliance-details-by-config-rule \
  --config-rule-name restricted-ssh \
  --query 'EvaluationResults[*].{Resource:EvaluationResultIdentifier.EvaluationResultQualifier.ResourceId,Result:ComplianceType}' \
  --output table 2>/dev/null || echo "  (Config needs time to evaluate)"
echo ""
echo ">> RESULT: Pipeline: CloudTrail records -> EventBridge detects -> Config enforces -> Auto-remediate"
echo ""
echo "============ DEMO COMPLETE ============"
