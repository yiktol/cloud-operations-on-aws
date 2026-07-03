#!/bin/bash
# Module 14 - Live Demo: Cost Reporting, Alerts, and Optimization
# NOTE: Billing alarm must be created in us-east-1 (AWS requirement)

STACK_NAME="mod14-cost-optimization-demo"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=$(aws configure get region)
TOPIC_ARN=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`SNSTopicArn`].OutputValue' --output text)

echo "Account: ${ACCOUNT_ID} | Topic: ${TOPIC_ARN}"
echo ""

echo "============================================"
echo "  ACT 1: COST VISIBILITY (Cost Explorer)"
echo "============================================"
read -p "Press Enter to view month-to-date costs by service..."
aws ce get-cost-and-usage \
  --time-period "Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d)" \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --query 'ResultsByTime[0].Groups[*].{Service:Keys[0],Cost:Metrics.BlendedCost.Amount}' \
  --output table

read -p "Press Enter to get a 3-month cost forecast..."
END_DATE=$(date -d '+3 months' +%Y-%m-01 2>/dev/null || date -v+3m +%Y-%m-01)
aws ce get-cost-forecast \
  --time-period "Start=$(date +%Y-%m-%d),End=${END_DATE}" \
  --metric BLENDED_COST \
  --granularity MONTHLY \
  --query '{TotalForecast:Total.Amount,Unit:Total.Unit}' \
  --output table

echo ""
echo ">> RESULT: Cost Explorer shows WHERE money is going. Forecast shows WHERE it is heading."
echo ""

echo "============================================"
echo "  ACT 2: BUDGETS - PROACTIVE COST CONTROL"
echo "============================================"
read -p "Press Enter to create a monthly budget with alerts..."
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

echo "Budget created. Checking status..."
aws budgets describe-budgets --account-id ${ACCOUNT_ID} \
  --query 'Budgets[?BudgetName==`Demo-Monthly-Budget`].{Name:BudgetName,Limit:BudgetLimit.Amount,Actual:CalculatedSpend.ActualSpend.Amount}' \
  --output table

echo ""
echo ">> RESULT: Alert at 80% actual + 100% forecasted = early warning before overspend."
echo ""

echo "============================================"
echo "  ACT 3: OPTIMIZATION - TRUSTED ADVISOR + COMPUTE OPTIMIZER"
echo "============================================"
read -p "Press Enter to check Trusted Advisor cost recommendations..."
# Cost optimization checks (available without Business/Enterprise support for some)
aws support describe-trusted-advisor-check-summaries \
  --check-ids "Qch7DwouX1" "hjLMh88uM8" "Z4AUBRNSminyHCqN5n" \
  --query 'summaries[*].{Name:name,Status:status,Resources:resourcesSummary.resourcesFlagged}' \
  --output table 2>/dev/null || echo "[INFO] Trusted Advisor check requires Business/Enterprise Support plan"

read -p "Press Enter to check Compute Optimizer EC2 recommendations..."
aws compute-optimizer get-ec2-instance-recommendations \
  --query 'instanceRecommendations[0:3].{Instance:instanceArn,Finding:finding,CurrentType:currentInstanceType,RecommendedType:recommendationOptions[0].instanceType,SavingsPercentage:recommendationOptions[0].performanceRisk}' \
  --output table 2>/dev/null || echo "[INFO] Compute Optimizer needs to be opted in 24h before recommendations appear"

read -p "Press Enter to check Savings Plans recommendations..."
aws ce get-savings-plans-purchase-recommendation \
  --savings-plans-type COMPUTE_SP \
  --term-in-years ONE_YEAR \
  --payment-option NO_UPFRONT \
  --query 'SavingsPlansPurchaseRecommendation.SavingsPlansPurchaseRecommendationDetails[0].{HourlyCommitment:HourlyCommitmentToPurchase,EstimatedSavings:EstimatedSavingsAmount,SavingsRate:EstimatedSavingsPercentage}' \
  --output table 2>/dev/null || echo "[INFO] No Savings Plans recommendations available yet"

echo ""
echo ">> RESULT: Three levers for optimization:"
echo "   1. Trusted Advisor - unused/underused resources (quick wins)"
echo "   2. Compute Optimizer - rightsize EC2 based on 14 days of metrics"
echo "   3. Savings Plans/RIs - commit to usage for up to 66% discount"
echo ""
echo "============ DEMO COMPLETE ============"
echo "Run cleanup.sh to remove the budget and SNS topic."
