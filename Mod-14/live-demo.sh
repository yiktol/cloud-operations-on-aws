#!/bin/bash
# Module 14 - Live Demo: Cost Reporting, Alerts, and Optimization
# Prereq: Run deploy.sh first
set -e

STACK_NAME="mod14-cost-optimization-demo"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
TOPIC_ARN=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`SNSTopicArn`].OutputValue' --output text)

echo "========================================"
echo " Module 14: Cost Optimization"
echo " Account: ${ACCOUNT_ID}"
echo "========================================"
echo ""

# --- ACT 1: Cost Visibility (Cost Explorer) ---
echo "--- ACT 1: Cost Visibility (Cost Explorer) ---"
echo ""

# Month-to-date costs grouped by service
echo "[1.1] Month-to-date costs by service:"
aws ce get-cost-and-usage \
  --time-period "Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d)" \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --query 'ResultsByTime[0].Groups[*].{Service:Keys[0],Cost:Metrics.BlendedCost.Amount}' \
  --output table
echo ""

# 3-month cost forecast (macOS-compatible date)
echo "[1.2] 3-month cost forecast:"
END_DATE=$(date -v+3m +%Y-%m-01 2>/dev/null || date -d '+3 months' +%Y-%m-01)
aws ce get-cost-forecast \
  --time-period "Start=$(date +%Y-%m-%d),End=${END_DATE}" \
  --metric BLENDED_COST \
  --granularity MONTHLY \
  --query '{TotalForecast:Total.Amount,Unit:Total.Unit}' \
  --output table
echo ""

# --- ACT 2: Budgets - Proactive Cost Control ---
echo "--- ACT 2: Budgets - Proactive Cost Control ---"
echo ""

# Create monthly budget with alerts
echo "[2.1] Creating monthly budget (\$100, alerts at 80%/100%)..."
aws budgets create-budget \
  --account-id ${ACCOUNT_ID} \
  --budget '{
    "BudgetName": "Demo-Monthly-Budget",
    "BudgetLimit": {"Amount": "100", "Unit": "USD"},
    "BudgetType": "COST",
    "TimeUnit": "MONTHLY",
    "TimePeriod": {"Start": "2020-01-01T00:00:00Z", "End": "2087-06-15T00:00:00Z"}
  }' \
  --notifications-with-subscribers '[
    {
      "Notification": {
        "NotificationType": "ACTUAL",
        "ComparisonOperator": "GREATER_THAN",
        "Threshold": 80,
        "ThresholdType": "PERCENTAGE"
      },
      "Subscribers": [{"SubscriptionType": "SNS", "Address": "'"${TOPIC_ARN}"'"}]
    },
    {
      "Notification": {
        "NotificationType": "FORECASTED",
        "ComparisonOperator": "GREATER_THAN",
        "Threshold": 100,
        "ThresholdType": "PERCENTAGE"
      },
      "Subscribers": [{"SubscriptionType": "SNS", "Address": "'"${TOPIC_ARN}"'"}]
    }
  ]'
echo "  ✓ Budget created"
echo ""

# Verify budget status
echo "[2.2] Budget status:"
aws budgets describe-budgets --account-id ${ACCOUNT_ID} \
  --query 'Budgets[?BudgetName==`Demo-Monthly-Budget`].{Name:BudgetName,Limit:BudgetLimit.Amount,Actual:CalculatedSpend.ActualSpend.Amount}' \
  --output table
echo ""

# --- ACT 3: Optimization Recommendations ---
echo "--- ACT 3: Optimization Recommendations ---"
echo ""

# Trusted Advisor (requires Business/Enterprise support)
echo "[3.1] Trusted Advisor cost checks:"
aws support describe-trusted-advisor-check-summaries \
  --check-ids "Qch7DwouX1" "hjLMh88uM8" \
  --query 'summaries[*].{Name:name,Status:status,Flagged:resourcesSummary.resourcesFlagged}' \
  --output table 2>/dev/null || echo "  (Requires Business/Enterprise support plan)"
echo ""

# Compute Optimizer EC2 rightsizing
echo "[3.2] Compute Optimizer EC2 recommendations:"
aws compute-optimizer get-ec2-instance-recommendations \
  --query 'instanceRecommendations[0:3].{Instance:instanceArn,Finding:finding,CurrentType:currentInstanceType,Recommended:recommendationOptions[0].instanceType}' \
  --output table 2>/dev/null || echo "  (No recommendations available - enable Compute Optimizer 24h in advance)"
echo ""

# Savings Plans recommendations
echo "[3.3] Savings Plans purchase recommendations:"
aws ce get-savings-plans-purchase-recommendation \
  --savings-plans-type COMPUTE_SP \
  --term-in-years ONE_YEAR \
  --payment-option NO_UPFRONT \
  --lookback-period-in-days THIRTY_DAYS \
  --query 'SavingsPlansPurchaseRecommendation.SavingsPlansPurchaseRecommendationDetails[0:3].{HourlyCommitment:HourlyCommitmentToPurchase,EstimatedSavings:EstimatedSavingsAmount,SavingsRate:EstimatedSavingsPercentage}' \
  --output table 2>/dev/null || echo "  (No Savings Plans recommendations available)"
echo ""

echo "========================================"
echo " Demo Complete!"
echo "========================================"
