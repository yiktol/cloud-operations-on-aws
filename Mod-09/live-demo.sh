#!/bin/bash
# Module 09 - Live Demo: Monitor and Maintain System Health
STACK_NAME="mod09-monitoring-demo"
if [ -z "$INSTANCE_ID" ]; then
  INSTANCE_ID=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
    --query 'Stacks[0].Outputs[?OutputKey==`InstanceId`].OutputValue' --output text)
fi
echo "Instance: ${INSTANCE_ID}"

echo "============================================"
echo "  ACT 1: CLOUDWATCH METRICS"
echo "============================================"
read -p "Press Enter..."
echo ">> Available EC2 metrics..."
aws cloudwatch list-metrics --namespace AWS/EC2 \
  --dimensions Name=InstanceId,Value=${INSTANCE_ID} \
  --query 'Metrics[*].MetricName' --output table

echo ""
echo ">> CPU utilization (last hour)..."
START=$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -v-1H +%Y-%m-%dT%H:%M:%S)
END=$(date -u +%Y-%m-%dT%H:%M:%S)
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value=${INSTANCE_ID} \
  --start-time ${START} --end-time ${END} \
  --period 300 --statistics Average Maximum --output table

echo ""
echo ">> Publish custom business metric..."
aws cloudwatch put-metric-data --namespace "DemoApp" \
  --metric-name "OrdersProcessed" --value 42 --unit Count \
  --dimensions Name=Environment,Value=Production
echo "  Custom metric published! (DemoApp/OrdersProcessed=42)"
echo ""
echo ">> RESULT: Automatic AWS metrics + your own business metrics in one place."

echo ""
echo "============================================"
echo "  ACT 2: CLOUDWATCH ALARMS"
echo "============================================"
read -p "Press Enter..."
aws cloudwatch put-metric-alarm \
  --alarm-name "Demo-HighCPU" \
  --metric-name CPUUtilization --namespace AWS/EC2 \
  --statistic Average --period 60 --evaluation-periods 2 \
  --threshold 80 --comparison-operator GreaterThanThreshold \
  --dimensions Name=InstanceId,Value=${INSTANCE_ID} \
  --alarm-description "Alert when CPU exceeds 80% for 2 minutes" \
  --treat-missing-data missing

aws cloudwatch describe-alarms --alarm-names "Demo-HighCPU" \
  --query 'MetricAlarms[0].{Name:AlarmName,State:StateValue,Threshold:Threshold}' \
  --output table

echo ""
echo ">> Manually trigger the alarm (simulate high CPU)..."
read -p "Press Enter..."
aws cloudwatch set-alarm-state --alarm-name "Demo-HighCPU" \
  --state-value ALARM --state-reason "Demo: simulating high CPU"
aws cloudwatch describe-alarms --alarm-names "Demo-HighCPU" \
  --query 'MetricAlarms[0].StateValue' --output text
echo ""
echo ">> RESULT: Alarm fires when threshold breached. Drives Auto Scaling and notifications."

echo ""
echo "============================================"
echo "  ACT 3: CLOUDWATCH LOGS"
echo "============================================"
read -p "Press Enter..."
aws logs create-log-group --log-group-name "/demo/application" 2>/dev/null || true
aws logs create-log-stream \
  --log-group-name "/demo/application" \
  --log-stream-name "web-server-01" 2>/dev/null || true

TS=$(($(date +%s) * 1000))
aws logs put-log-events \
  --log-group-name "/demo/application" \
  --log-stream-name "web-server-01" \
  --log-events \
  timestamp=${TS},message="INFO: App started" \
  timestamp=$((TS+1000)),message="INFO: status=200 latency=45ms" \
  timestamp=$((TS+2000)),message="ERROR: DB timeout after 30000ms" \
  timestamp=$((TS+3000)),message="ERROR: DB timeout after 30000ms"

echo ">> Search for ERROR patterns..."
aws logs filter-log-events \
  --log-group-name "/demo/application" \
  --filter-pattern "ERROR" \
  --query 'events[*].{Time:timestamp,Message:message}' --output table

echo ""
echo ">> Create metric filter: count errors..."
aws logs put-metric-filter \
  --log-group-name "/demo/application" \
  --filter-name "ErrorCount" --filter-pattern "ERROR" \
  --metric-transformations metricName=ApplicationErrors,metricNamespace=DemoApp,metricValue=1
echo ""
echo ">> RESULT: Logs -> Filter -> Metric -> Alarm. Full observability pipeline!"
echo ""
echo "============ DEMO COMPLETE ============"
