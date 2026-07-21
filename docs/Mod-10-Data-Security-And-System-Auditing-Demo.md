# Module 10 Demo: Data Security and System Auditing — "Detect, Alert, Remediate"

## Prerequisites
- AWS CLI configured with admin credentials
- Module 10 CloudFormation stack deployed (`Mod-10/cfn-setup.yaml`)
- CloudTrail enabled (default in most accounts)
- AWS Config already enabled in the region

---

## Part 1: Setup (do before class)

### Deploy the CloudFormation stack
The stack creates: SNS topic for security alerts (with EventBridge/CloudWatch publish permissions), and an EventBridge IAM role.

```bash
aws cloudformation deploy \
  --template-file Mod-10/cfn-setup.yaml \
  --stack-name mod10-demo \
  --capabilities CAPABILITY_NAMED_IAM
```

### Get the SNS topic ARN
```bash
TOPIC_ARN=$(aws cloudformation describe-stacks --stack-name mod10-demo --query "Stacks[0].Outputs[?OutputKey=='SecurityAlertsTopicArn'].OutputValue" --output text)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Subscribe your email (confirm the subscription before class)
aws sns subscribe --topic-arn ${TOPIC_ARN} --protocol email --notification-endpoint your-email@example.com
```

---

## Part 2: Live Demo (in class)

### 🎬 Act 1: CloudTrail — Who Did What, When

> **Say:** "CloudTrail is your audit log for EVERYTHING that happens in your AWS account. Every API call is recorded."

```bash
# Look at recent API activity
aws cloudtrail lookup-events \
  --max-results 10 \
  --query 'Events[*].{Time:EventTime,User:Username,Event:EventName,Source:EventSource}' \
  --output table

# Search for specific security-relevant events
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=ConsoleLogin \
  --max-results 5 \
  --query 'Events[*].{Time:EventTime,User:Username,Source:CloudTrailEvent}' \
  --output table

# Who created IAM users recently?
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=CreateUser \
  --max-results 5 \
  --output table

# Who modified security groups?
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AuthorizeSecurityGroupIngress \
  --max-results 5 \
  --output table
```

> **Talking points:**
> - "Every single API call — console clicks, CLI commands, SDK calls — ALL recorded."
> - "This is your forensic evidence if something goes wrong."
> - "You can answer: 'Who opened port 22 to the internet at 3am on Tuesday?'"

---

### 🎬 Act 2: EventBridge — Real-time Detection

> **Say:** "CloudTrail records events. EventBridge reacts to them IN REAL TIME."

```bash
# Create an EventBridge rule: detect when someone modifies a security group
aws events put-rule \
  --name "detect-open-security-group" \
  --event-pattern '{
    "source": ["aws.ec2"],
    "detail-type": ["AWS API Call via CloudTrail"],
    "detail": {
      "eventName": ["AuthorizeSecurityGroupIngress"]
    }
  }' \
  --state ENABLED \
  --description "Detect when security group rules are added"

# Add SNS target (send alert)
aws events put-targets \
  --rule "detect-open-security-group" \
  --targets "Id=sns-alert,Arn=${TOPIC_ARN}"

echo "Rule created! Now any security group change triggers an alert."

# Demonstrate: add a security group rule
DEMO_SG=$(aws ec2 create-security-group --group-name demo-detect-sg \
  --description "Trigger detection" --query GroupId --output text)

# This will trigger the EventBridge rule!
aws ec2 authorize-security-group-ingress \
  --group-id ${DEMO_SG} \
  --protocol tcp --port 22 --cidr 0.0.0.0/0

echo "⚠️ Alert sent! Check your email (or SNS topic)."
```

> **Talking points:**
> - "Within SECONDS of someone opening port 22, you get an alert."
> - "No polling, no delays — EventBridge reacts to CloudTrail events in near real-time."
> - "This is your detection mechanism."

---

### 🎬 Act 3: Automated Remediation with Config Rules

> **Say:** "Detection is good, but automated REMEDIATION is better. Let's auto-close insecure security group rules."

```bash
# Create a Config rule to check for open SSH
aws configservice put-config-rule --config-rule '{
  "ConfigRuleName": "restricted-ssh",
  "Source": {
    "Owner": "AWS",
    "SourceIdentifier": "INCOMING_SSH_DISABLED"
  },
  "Scope": {
    "ComplianceResourceTypes": ["AWS::EC2::SecurityGroup"]
  }
}'

# Trigger evaluation
aws configservice start-config-rules-evaluation \
  --config-rule-names restricted-ssh

# After a moment, check compliance
sleep 15
aws configservice get-compliance-details-by-config-rule \
  --config-rule-name restricted-ssh \
  --compliance-types NON_COMPLIANT \
  --query 'EvaluationResults[*].EvaluationResultIdentifier.EvaluationResultQualifier.ResourceId' \
  --output table
```

> **Talking points:**
> - "The pipeline: CloudTrail records → Config evaluates → Remediation fixes."
> - "No human intervention needed for known-bad configurations."
> - "This is the security automation loop: Detect → Alert → Remediate."

---

## Part 3: Cleanup

```bash
aws events remove-targets --rule "detect-open-security-group" --ids "sns-alert"
aws events delete-rule --name "detect-open-security-group"
aws ec2 delete-security-group --group-id ${DEMO_SG}
aws configservice delete-config-rule --config-rule-name restricted-ssh

# Delete the stack
aws cloudformation delete-stack --stack-name mod10-demo
```

---

## Summary Table

| Layer | Tool | What it does |
|-------|------|-------------|
| **Record** | CloudTrail | Audit log of all API calls |
| **Detect** | EventBridge + Config | Real-time pattern matching & compliance |
| **Alert** | SNS | Notify security team |
| **Remediate** | Config Auto-remediation / Lambda | Auto-fix violations |

---

## Timing Guide

| Section | Duration |
|---------|----------|
| Act 1 (CloudTrail) | 4 min |
| Act 2 (EventBridge) | 5 min |
| Act 3 (Auto-remediation) | 5 min |
| **Total** | **~14 min** |
