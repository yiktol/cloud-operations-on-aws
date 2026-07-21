# Module 14 – Cost Reporting, Alerts, and Optimization
## Instructor Live Demo Script

**Course:** Cloud Operations on AWS (200-SYSOPS 5.6.2)
**Module:** 14 – Cost Reporting, Alerts, and Optimization
**Total Demo Time:** ~15 minutes

---

## Prerequisites

| Requirement | Details |
|---|---|
| AWS CLI version | v2.x (`aws --version`) |
| IAM permissions | `billing:*`, `budgets:*`, `ce:*`, `cloudwatch:*`, `trustedadvisor:*`, `compute-optimizer:*` |
| Billing Alerts | Must be enabled in **Billing Preferences** (console, one-time) |
| Compute Optimizer | Opt-in ≥24 hours before class for data to populate |
| Module 14 CFN stack | Deployed (`Mod-14/cfn-setup.yaml`) |

---

## Setup (Before Class)

### Deploy the CloudFormation stack
The stack creates: SNS topic with email subscription and publish permissions for Budgets/CloudWatch.

```bash
aws cloudformation deploy \
  --template-file Mod-14/cfn-setup.yaml \
  --stack-name mod14-demo \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides AlertEmail=your-email@example.com
```

> ⚠️ **Check your email and confirm the SNS subscription** before class starts.

### Get the SNS topic ARN and opt in to Compute Optimizer
```bash
SNS_ARN=$(aws cloudformation describe-stacks --stack-name mod14-demo --query "Stacks[0].Outputs[?OutputKey=='SNSTopicArn'].OutputValue" --output text)

# Enable Billing Alerts (console step — one-time):
# Billing and Cost Management → Billing Preferences → Receive Billing Alerts → Save

# Opt in to Compute Optimizer (allow 12-24h for recommendations)
aws compute-optimizer update-enrollment-status --status Active
```

---

## Live Demo

---

### 🎬 ACT 1 — Cost & Usage Awareness (~5 min)

#### 1.1 Check the current month's cost forecast

```bash
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics "BlendedCost" "UnblendedCost" "UsageQuantity" \
  --query 'ResultsByTime[].{Start:TimePeriod.Start, BlendedCost:Total.BlendedCost.Amount, Unit:Total.BlendedCost.Unit}' \
  --output table
```

#### 1.2 Break costs down by service (top services this month)

```bash
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics "BlendedCost" \
  --group-by Type=DIMENSION,Key=SERVICE \
  --query 'sort_by(ResultsByTime[0].Groups, &Keys[0])[].{Service:Keys[0], Cost:Metrics.BlendedCost.Amount}' \
  --output table
```

#### 1.3 Pull a 3-month cost forecast

```bash
aws ce get-cost-forecast \
  --time-period Start=$(date -v+1m +%Y-%m-01),End=$(date -v+4m +%Y-%m-01) \
  --granularity MONTHLY \
  --metric BLENDED_COST \
  --query '{Total:Total, ForecastedPeriods:ForecastResultsByTime[].{Start:TimePeriod.Start, MeanValue:MeanValue}}' \
  --output json
```

#### 1.4 List existing Cost and Usage Reports

```bash
aws cur describe-report-definitions \
  --region us-east-1 \
  --query 'ReportDefinitions[].{ReportName:ReportName, S3Bucket:S3Bucket, Granularity:TimeUnit}' \
  --output table
```

> 📌 **Callout:** Open **Billing → Cost & Usage Reports** in the console to show the report wizard.

---

### 🎬 ACT 2 — Cost Control Mechanisms (~5 min)

#### 2.1 List existing budgets

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws budgets describe-budgets \
  --account-id ${ACCOUNT_ID} \
  --query 'Budgets[].{Name:BudgetName, Type:BudgetType, Limit:BudgetLimit.Amount, Unit:BudgetLimit.Unit}' \
  --output table
```

#### 2.2 Create a monthly cost budget with alerts

```bash
aws budgets create-budget \
  --account-id "$ACCOUNT_ID" \
  --budget '{
    "BudgetName": "MonthlyTotalCost-Demo",
    "BudgetLimit": { "Amount": "100", "Unit": "USD" },
    "TimeUnit": "MONTHLY",
    "BudgetType": "COST"
  }' \
  --notifications-with-subscribers '[
    {
      "Notification": {
        "NotificationType": "ACTUAL",
        "ComparisonOperator": "GREATER_THAN",
        "Threshold": 80,
        "ThresholdType": "PERCENTAGE"
      },
      "Subscribers": [
        { "SubscriptionType": "SNS", "Address": "'"${SNS_ARN}"'" }
      ]
    },
    {
      "Notification": {
        "NotificationType": "FORECASTED",
        "ComparisonOperator": "GREATER_THAN",
        "Threshold": 100,
        "ThresholdType": "PERCENTAGE"
      },
      "Subscribers": [
        { "SubscriptionType": "SNS", "Address": "'"${SNS_ARN}"'" }
      ]
    }
  ]'
```

> 💬 **Talking point:** *"Two thresholds: actual at 80% (early warning) and forecasted at 100% (predictive control)."*

#### 2.3 Create a CloudWatch billing alarm

```bash
# Billing metrics are only in us-east-1
aws cloudwatch put-metric-alarm \
  --region us-east-1 \
  --alarm-name "BillingAlarm-50USD" \
  --alarm-description "Alert when estimated charges exceed $50" \
  --namespace "AWS/Billing" \
  --metric-name "EstimatedCharges" \
  --dimensions Name=Currency,Value=USD \
  --statistic Maximum \
  --period 86400 \
  --evaluation-periods 1 \
  --threshold 50 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --alarm-actions "$SNS_ARN" \
  --treat-missing-data notBreaching
```

> 💬 **Talking point:** *"Budgets = rich forecasting + automated actions. CloudWatch billing alarms = tight EventBridge integration. They're complementary."*

---

### 🎬 ACT 3 — Cost Optimization (~4 min)

#### 3.1 Check Trusted Advisor cost optimization checks

```bash
aws support describe-trusted-advisor-checks \
  --language en \
  --query "checks[?category=='cost_optimizing'].{Id:id, Name:name}" \
  --output table
```

#### 3.2 Check Compute Optimizer recommendations

```bash
aws compute-optimizer get-enrollment-status \
  --query '{Status:status}' --output table

aws compute-optimizer get-ec2-instance-recommendations \
  --query 'instanceRecommendations[0:3].{InstanceArn:instanceArn, Finding:finding, CurrentType:currentInstanceType, RecommendedType:recommendationOptions[0].instanceType}' \
  --output table 2>/dev/null || echo "No recommendations yet — allow 12-24h after opt-in"
```

#### 3.3 View Savings Plans recommendations

```bash
aws ce get-savings-plans-purchase-recommendation \
  --savings-plans-type COMPUTE_SP \
  --term-in-years ONE_YEAR \
  --payment-option NO_UPFRONT \
  --lookback-period-in-days THIRTY_DAYS \
  --query 'SavingsPlansPurchaseRecommendation.SavingsPlansPurchaseRecommendationSummary.{EstimatedMonthlySavings:EstimatedMonthlySavingsAmount,RecommendedHourlyCommitment:RecommendedHourlyCommitmentToPurchase}' \
  --output json
```

---

## Cleanup

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Delete the demo budget
aws budgets delete-budget \
  --account-id "$ACCOUNT_ID" \
  --budget-name "MonthlyTotalCost-Demo"

# Delete the CloudWatch billing alarm
aws cloudwatch delete-alarms \
  --region us-east-1 \
  --alarm-names "BillingAlarm-50USD"

# Delete the stack (removes SNS topic)
aws cloudformation delete-stack --stack-name mod14-demo
```

---

## Summary Table

| Act | Topic | Key Services |
|-----|-------|-------------|
| Act 1 | Cost Awareness | Cost Explorer, CUR |
| Act 2 | Control | Budgets, CloudWatch billing alarms |
| Act 3 | Optimization | Trusted Advisor, Compute Optimizer, Savings Plans |

---

## Timing Guide

| Segment | Time |
|---------|------|
| Act 1 — Awareness | 5 min |
| Act 2 — Control | 5 min |
| Act 3 — Optimization | 4 min |
| Cleanup | 1 min |
| **Total** | **~15 min** |
