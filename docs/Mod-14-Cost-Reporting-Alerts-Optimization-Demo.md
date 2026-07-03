# Module 14 – Cost Reporting, Alerts, and Optimization
## Instructor Live Demo Script

**Course:** Cloud Operations on AWS (200-SYSOPS 5.6.2)
**Module:** 14 – Cost Reporting, Alerts, and Optimization
**Total Demo Time:** ~15 minutes
**Format:** CLI-driven with AWS Management Console callouts where noted

---

## Overview

This demo walks students through the three pillars of CloudOps cost management:

1. **Awareness** – Explore historical and current cost/usage data (Cost Explorer, CUR)
2. **Control** – Create a Budget with alerts and a CloudWatch billing alarm
3. **Optimization** – View Trusted Advisor and Compute Optimizer recommendations

Each act pairs live CLI commands with instructor talking points tied directly to the slide deck.

---

## Prerequisites

| Requirement | Details |
|---|---|
| AWS CLI version | v2.x (`aws --version`) |
| IAM permissions | `billing:*`, `budgets:*`, `ce:*`, `cloudwatch:*`, `trustedadvisor:*`, `compute-optimizer:*` |
| IAM Billing Access | Billing console access must be **activated** in Account Settings for IAM users |
| AWS Region | Most commands target `us-east-1` (billing metrics are stored only in us-east-1) |
| Billing Alerts | Must be enabled in **Billing Preferences** before billing alarms work |
| SNS Topic | A pre-created SNS topic with a confirmed email subscription for alert demos |
| Compute Optimizer | Opt-in must be done ≥24 hours before class for data to populate |

---

## Setup (Before Class — ~10 min)

> Complete these steps **before** students arrive. Commands are safe to run in any sandbox account.

### S1 – Configure AWS CLI default region

```bash
# Set default profile/region for the demo session
export AWS_DEFAULT_REGION=us-east-1
aws configure get region
```

### S2 – Create an SNS topic and subscribe your email

```bash
# Create the topic
aws sns create-topic --name cost-alerts-demo \
  --query 'TopicArn' --output text

# Subscribe your instructor email (replace with your address)
SNS_ARN=$(aws sns list-topics \
  --query "Topics[?contains(TopicArn,'cost-alerts-demo')].TopicArn" \
  --output text)

aws sns subscribe \
  --topic-arn "$SNS_ARN" \
  --protocol email \
  --notification-endpoint instructor@example.com
```

> ⚠️ **Check your email and confirm the subscription** before class starts.

### S3 – Enable Billing Alerts (console step — one-time)

1. Sign in → **Billing and Cost Management** → **Billing Preferences**
2. Check **Receive Billing Alerts** → Save

> This cannot be done with the CLI; it only needs to be done once per account.

### S4 – Opt in to Compute Optimizer

```bash
aws compute-optimizer update-enrollment-status \
  --status Active
```

> Allow at least 12–24 hours for recommendations to populate.

### S5 – Capture the SNS ARN for later use

```bash
SNS_ARN=$(aws sns list-topics \
  --query "Topics[?contains(TopicArn,'cost-alerts-demo')].TopicArn" \
  --output text)
echo "SNS ARN: $SNS_ARN"
```

---

## Live Demo

---

### 🎬 ACT 1 — Cost & Usage Awareness (~5 min)

**Slides covered:** 6–17
**Core message:** AWS provides a spectrum of tools for cost awareness — from the high-level Billing Dashboard, through Cost Explorer, to the granular Cost and Usage Report.

---

#### 1.1 Check the current month's cost forecast

```bash
# Get a month-to-date cost summary and 30-day forecast
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics "BlendedCost" "UnblendedCost" "UsageQuantity" \
  --query 'ResultsByTime[].{Start:TimePeriod.Start, BlendedCost:Total.BlendedCost.Amount, Unit:Total.BlendedCost.Unit}' \
  --output table
```

💬 **Talking point:** *"The Billing Dashboard (slide 8) gives us three at-a-glance views: Spend Summary, Month-to-Date Spend by Service, and Top Services by Spend. Here in the CLI we're pulling the same underlying data that populates those graphs."*

---

#### 1.2 Break costs down by service (top 5 services this month)

```bash
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics "BlendedCost" \
  --group-by Type=DIMENSION,Key=SERVICE \
  --query 'sort_by(ResultsByTime[0].Groups, &Keys[0])[].{Service:Keys[0], Cost:Metrics.BlendedCost.Amount}' \
  --output table
```

💬 **Talking point:** *"This is exactly what Cost Explorer (slides 10–11) lets you do visually — filter and group by service, account, region, or tag. The CLI gives you the same data, making it scriptable for reporting pipelines."*

---

#### 1.3 Pull a 3-month cost forecast

```bash
# Forecast for next 3 months
aws ce get-cost-forecast \
  --time-period Start=$(date -d "+1 month" +%Y-%m-01 2>/dev/null || date -v+1m +%Y-%m-01),End=$(date -d "+4 months" +%Y-%m-01 2>/dev/null || date -v+4m +%Y-%m-01) \
  --granularity MONTHLY \
  --metric BLENDED_COST \
  --query '{Total:Total, ForecastedPeriods:ForecastResultsByTime[].{Start:TimePeriod.Start, MeanValue:MeanValue}}' \
  --output json
```

💬 **Talking point:** *"Slides 12–13 show how Cost Explorer forecasts future spend based on historical trends. A monthly report with +3M or +12M forecast gives finance teams the runway they need to plan budgets proactively."*

---

#### 1.4 List existing Cost and Usage Reports

```bash
# See if any CUR definitions already exist
aws cur describe-report-definitions \
  --region us-east-1 \
  --query 'ReportDefinitions[].{ReportName:ReportName, S3Bucket:S3Bucket, Granularity:TimeUnit, Compression:Compression}' \
  --output table
```

💬 **Talking point:** *"Slides 14–16 walk us through the CUR. It's the most granular data source AWS provides — per-resource, per-hour. You can point it at S3 and then query it with Athena (slide 17) to automate cost reports via Lambda and deliver them by email through SES."*

> 📌 **Callout (console):** Open **Billing → Cost & Usage Reports** to show the report wizard, highlighting the S3 bucket assignment, time granularity, and data integration options (Athena / Redshift / QuickSight).

---

### 🎬 ACT 2 — Cost Control Mechanisms (~5 min)

**Slides covered:** 19–27
**Core message:** Detection → Notification → Action. AWS Budgets and CloudWatch billing alarms let you set guardrails and automate responses before costs spiral.

---

#### 2.1 List existing budgets

```bash
# View any budgets already configured in the account
aws budgets describe-budgets \
  --account-id $(aws sts get-caller-identity --query Account --output text) \
  --query 'Budgets[].{Name:BudgetName, Type:BudgetType, Limit:BudgetLimit.Amount, Unit:BudgetLimit.Unit, TimeUnit:TimeUnit}' \
  --output table
```

💬 **Talking point:** *"Slide 20 introduces AWS Budgets as the primary cost-control mechanism. You can track cost, usage, reservation utilization, or Savings Plans coverage — and trigger alerts or automated actions when thresholds are hit."*

---

#### 2.2 Create a monthly cost budget with email alerts

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create a $100/month budget with alerts at 80% and 100%
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
        { "SubscriptionType": "EMAIL", "Address": "instructor@example.com" }
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
        { "SubscriptionType": "EMAIL", "Address": "instructor@example.com" }
      ]
    }
  ]'
```

💬 **Talking point:** *"Slides 22–25 walk through the budget wizard. Notice we set TWO thresholds: an actual spend alert at 80% (early warning) and a forecasted spend alert at 100% (predictive control). You can also add budget actions to automatically stop EC2/RDS instances or apply an SCP when a threshold is crossed."*

---

#### 2.3 Verify the budget was created

```bash
aws budgets describe-budget \
  --account-id "$ACCOUNT_ID" \
  --budget-name "MonthlyTotalCost-Demo" \
  --query 'Budget.{Name:BudgetName, Limit:BudgetLimit.Amount, Unit:BudgetLimit.Unit}' \
  --output table
```

---

#### 2.4 Create a CloudWatch billing alarm

```bash
# Billing metrics are only available in us-east-1
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
  --ok-actions "$SNS_ARN" \
  --treat-missing-data notBreaching
```

💬 **Talking point:** *"Slides 26–27 cover CloudWatch billing alarms. Key difference from Budgets: a billing alarm uses CloudWatch metrics (EstimatedCharges is published to us-east-1 several times a day) and fires only on actual charges — not forecasts. These are complementary tools, not substitutes. Use Budgets for rich forecasting and actions; use CloudWatch alarms when you need tight integration with EventBridge workflows."*

---

#### 2.5 Confirm the alarm state

```bash
aws cloudwatch describe-alarms \
  --region us-east-1 \
  --alarm-names "BillingAlarm-50USD" \
  --query 'MetricAlarms[].{Name:AlarmName, State:StateValue, Threshold:Threshold, Desc:AlarmDescription}' \
  --output table
```

> 💡 **Expected state:** `INSUFFICIENT_DATA` — this is normal when the alarm is brand new. Explain slide 21: the three states are OK, ALARM, and INSUFFICIENT_DATA.

---

### 🎬 ACT 3 — Cost Optimization (~4 min)

**Slides covered:** 28–38
**Core message:** Rightsizing, Savings Plans, Reserved Instances, Trusted Advisor, and Compute Optimizer all work together to reduce waste and right-size workloads.

---

#### 3.1 Check Trusted Advisor cost optimization checks

```bash
# Requires Business or Enterprise Support Plan for full access
aws support describe-trusted-advisor-checks \
  --language en \
  --query "checks[?category=='cost_optimizing'].{Id:id, Name:name}" \
  --output table
```

💬 **Talking point:** *"Slide 32 shows the Trusted Advisor cost optimization category. It surfaces low-utilization EC2 instances (CPU ≤10%, network I/O ≤5 MB on 4+ days), underutilized EBS volumes, idle RDS instances, and RI/Savings Plan opportunities. This is the fastest free health check for cost."*

---

#### 3.2 Retrieve a specific Trusted Advisor check result (Low Utilization EC2)

```bash
# Check ID for "Low Utilization Amazon EC2 Instances" = 1iG5NDGVre
aws support describe-trusted-advisor-check-result \
  --check-id 1iG5NDGVre \
  --language en \
  --query 'result.{Status:status, FlaggedResources:flaggedResources[0:3]}' \
  --output json
```

> ⚠️ **Note:** Trusted Advisor full results require Business or Enterprise Support. In a sandbox account without those plans, demonstrate this in the console under **AWS Support → Trusted Advisor → Cost Optimization**.

---

#### 3.3 Check Compute Optimizer enrollment and EC2 recommendations

```bash
# Confirm Compute Optimizer is active
aws compute-optimizer get-enrollment-status \
  --query '{Status:status, MemberAccountsEnrolled:memberAccountsEnrolled}' \
  --output table

# Get EC2 instance recommendations (returns empty if <12h since opt-in)
aws compute-optimizer get-ec2-instance-recommendations \
  --query 'instanceRecommendations[0:3].{InstanceArn:instanceArn, Finding:finding, CurrentType:currentInstanceType, RecommendedType:recommendationOptions[0].instanceType, EstimatedMonthlySavings:recommendationOptions[0].estimatedMonthlySavings.value}' \
  --output table 2>/dev/null || echo "No recommendations yet — allow 12-24h after opt-in"
```

💬 **Talking point:** *"Slides 33–37 cover Compute Optimizer. It uses ML to analyze CloudWatch utilization metrics and classifies each resource as Overprovisioned, Underprovisioned, or Optimized. Slide 36 shows a real example: downsizing from m5.8xlarge to r5.4xlarge saves $36.71/month. At scale, these recommendations compound quickly."*

---

#### 3.4 View Savings Plans recommendations

```bash
aws ce get-savings-plans-purchase-recommendation \
  --savings-plans-type COMPUTE_SP \
  --term-in-years ONE_YEAR \
  --payment-option NO_UPFRONT \
  --lookback-period-in-days THIRTY_DAYS \
  --query 'SavingsPlansPurchaseRecommendation.{
    EstimatedMonthlySavings:SavingsPlansPurchaseRecommendationSummary.EstimatedMonthlySavingsAmount,
    EstimatedROI:SavingsPlansPurchaseRecommendationSummary.EstimatedROI,
    RecommendedHourlyCommitment:SavingsPlansPurchaseRecommendationSummary.RecommendedHourlyCommitmentToPurchase
  }' \
  --output json
```

💬 **Talking point:** *"Slide 30 explains Savings Plans. Unlike Reserved Instances (a capacity commitment), Savings Plans commit you to a dollar-per-hour spend for 1 or 3 years. The flexibility: they apply across instance families, regions (Compute SP), and even Lambda and Fargate. The CLI recommendation engine shows exactly how much you'd save based on your last 30 days of usage."*

---

#### 3.5 (Optional) View RI recommendations for EC2

```bash
aws ce get-reservation-purchase-recommendation \
  --service "Amazon EC2" \
  --lookback-period-in-days THIRTY_DAYS \
  --term-in-years ONE_YEAR \
  --payment-option NO_UPFRONT \
  --query 'Recommendations[0:2].{Service:ServiceSpecification.EC2Specification.OfferingClass, RecommendedCount:RecommendationDetails[0].RecommendedNumberOfInstancesToPurchase, EstimatedMonthlySavings:RecommendationDetails[0].EstimatedMonthlySavingsAmount}' \
  --output table 2>/dev/null || echo "No RI recommendations available for this account"
```

💬 **Talking point:** *"Slide 31 covers RI recommendations. Cost Explorer evaluates 7, 30, or 60 days of usage patterns and ignores usage already covered by existing RIs. Slide 38 reinforces this — upgrading to latest-generation instances (e.g., c3 → c5) delivers both lower per-hour cost AND better performance."*

---

## Cleanup (~1 min)

> Run after demo or at end of class to avoid leftover resources.

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Delete the demo budget
aws budgets delete-budget \
  --account-id "$ACCOUNT_ID" \
  --budget-name "MonthlyTotalCost-Demo"
echo "Budget deleted."

# Delete the CloudWatch billing alarm
aws cloudwatch delete-alarms \
  --region us-east-1 \
  --alarm-names "BillingAlarm-50USD"
echo "Billing alarm deleted."

# Optionally delete the SNS topic
SNS_ARN=$(aws sns list-topics \
  --query "Topics[?contains(TopicArn,'cost-alerts-demo')].TopicArn" \
  --output text)
aws sns delete-topic --topic-arn "$SNS_ARN"
echo "SNS topic deleted."
```

---

## Summary Table

| Act | Topic | Key Services Demonstrated | Slide Refs |
|-----|-------|--------------------------|------------|
| Act 1 | Cost & Usage Awareness | `aws ce get-cost-and-usage`, `aws ce get-cost-forecast`, `aws cur describe-report-definitions` | 6–17 |
| Act 2 | Control Mechanisms | `aws budgets create-budget`, `aws cloudwatch put-metric-alarm` | 19–27 |
| Act 3 | Cost Optimization | `aws compute-optimizer`, `aws ce get-savings-plans-purchase-recommendation`, `aws support describe-trusted-advisor-check-result` | 28–38 |
| Cleanup | Resource removal | `aws budgets delete-budget`, `aws cloudwatch delete-alarms` | — |

---

## Timing Guide

| Segment | Activity | Time |
|---------|----------|------|
| Pre-class | Setup (S1–S5) | 10 min (not counted in demo) |
| Intro | Overview + module goals | 1 min |
| Act 1 | Awareness — cost queries & CUR | 5 min |
| Act 2 | Control — Budgets + billing alarm | 5 min |
| Act 3 | Optimization — Trusted Advisor, Compute Optimizer, Savings Plans | 4 min |
| Cleanup | Delete demo resources | 1 min |
| **Total** | | **~15 min** |

---

## Instructor Tips

- **If the account is brand-new or has minimal usage**, Cost Explorer queries return empty or near-zero results. Use the console to show sample screenshots from the slide deck, or use the `--query` flag to display structure even if data is sparse.
- **If Trusted Advisor full checks are unavailable** (no Business/Enterprise Support), navigate to the console and show the categories visually — a screenshot walkthrough takes ~60 seconds.
- **If Compute Optimizer has no data yet**, explain that opt-in requires 12–24 hours and demonstrate the Compute Optimizer dashboard in the console showing the finding categories: Overprovisioned, Underprovisioned, Optimized.
- **Billing alarms must be created in `us-east-1`** — reinforce this point from slide 26. A common student mistake is creating them in the wrong region and wondering why they never trigger.
- **AWS Anomaly Detection** (slide 19) is not CLI-demonstrated here but can be shown in the Cost Explorer console as a 2-minute add-on: navigate to **Cost Management → Anomaly Detection → Create monitor**.
- After the demo, connect back to the **CloudOps framework** from slide 4: Awareness → Control → Optimization is not a one-time exercise but a continuous loop driven by the tools we just demonstrated.

---

## Reference Links

| Resource | URL |
|----------|-----|
| AWS Cost Explorer docs | https://docs.aws.amazon.com/cost-management/latest/userguide/ce-what-is.html |
| AWS Budgets docs | https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/budgets-create.html |
| CloudWatch billing alarms | https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/monitor_estimated_charges_with_cloudwatch.html |
| Compute Optimizer docs | https://docs.aws.amazon.com/compute-optimizer/latest/ug/what-is-compute-optimizer.html |
| Trusted Advisor check reference | https://docs.aws.amazon.com/awssupport/latest/user/trusted-advisor-check-reference.html |
| Savings Plans recommendations | https://docs.aws.amazon.com/savingsplans/latest/userguide/sp-recommendations.html |
| AWS CUR User Guide | https://docs.aws.amazon.com/cur/latest/userguide/creating-cur.html |
| Well-Architected Labs (CUR automation) | https://wellarchitectedlabs.com/cost/300_labs/300_automated_cur_query_and_email_delivery |
