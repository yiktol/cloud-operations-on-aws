#!/bin/bash
# Module 09 - Live Demo: Monitor and Maintain System Health
# Prereq: Run deploy.sh first
set -e

STACK_NAME="mod09-monitoring-demo"
if [ -z "$INSTANCE_ID" ]; then
  INSTANCE_ID=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
    --query 'Stacks[0].Outputs[?OutputKey==`InstanceId`].OutputValue' --output text)
fi

echo "========================================"
echo " Module 09: CloudWatch Deep Dive"
echo " Instance: ${INSTANCE_ID}"
echo "========================================"
echo ""

# --- ACT 1: CloudWatch Metrics ---
echo "--- ACT 1: CloudWatch Metrics - The Vital Signs ---"
echo ""

# List available EC2 metrics for this instance
echo "[1.1] Available metrics for this instance:"
aws cloudwatch list-metrics --namespace AWS/EC2 \
  --dimensions Name=InstanceId,Value=${INSTANCE_ID} \
  --query 'Metrics[*].MetricName' --output table
echo ""

# Get CPU utilization for the last hour (macOS-compatible date)
START=$(date -u -v-1H +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S)
END=$(date -u +%Y-%m-%dT%H:%M:%S)

echo "[1.2] CPU utilization (last hour):"
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value=${INSTANCE_ID} \
  --start-time ${START} --end-time ${END} \
  --period 300 --statistics Average Maximum --output table
echo ""

# Publish a custom business metric
echo "[1.3] Publishing custom metric (OrdersProcessed)..."
aws cloudwatch put-metric-data --namespace "DemoApp" \
  --metric-name "OrdersProcessed" --value 42 --unit Count \
  --dimensions Name=Environment,Value=Production
aws cloudwatch put-metric-data --namespace "DemoApp" \
  --metric-name "OrdersProcessed" --value 87 --unit Count \
  --dimensions Name=Environment,Value=Production
echo "  ✓ Custom metrics published (42, 87)"
echo ""

# --- ACT 2: CloudWatch Alarms ---
echo "--- ACT 2: CloudWatch Alarms - Automated Alerting ---"
echo ""

# Create alarm for high CPU (>80% for 2 consecutive minutes)
echo "[2.1] Creating alarm: CPU > 80% for 2 consecutive periods..."
aws cloudwatch put-metric-alarm \
  --alarm-name "Demo-HighCPU" \
  --metric-name CPUUtilization --namespace AWS/EC2 \
  --statistic Average --period 60 --evaluation-periods 2 \
  --threshold 80 --comparison-operator GreaterThanThreshold \
  --dimensions Name=InstanceId,Value=${INSTANCE_ID} \
  --alarm-description "Alert when CPU exceeds 80% for 2 minutes" \
  --treat-missing-data missing
echo "  ✓ Alarm created"
echo ""

# Verify alarm configuration
echo "[2.2] Alarm state:"
aws cloudwatch describe-alarms --alarm-names "Demo-HighCPU" \
  --query 'MetricAlarms[0].{Name:AlarmName,State:StateValue,Threshold:Threshold}' \
  --output table
echo ""

# Manually trigger the alarm to simulate high CPU
echo "[2.3] Simulating alarm trigger..."
aws cloudwatch set-alarm-state --alarm-name "Demo-HighCPU" \
  --state-value ALARM --state-reason "Demo: simulating high CPU"
echo -n "  Alarm state: "
aws cloudwatch describe-alarms --alarm-names "Demo-HighCPU" \
  --query 'MetricAlarms[0].StateValue' --output text
echo ""

# --- ACT 3: CloudWatch Logs ---
echo ""
echo "--- ACT 3: CloudWatch Logs - Centralized Logging ---"
echo ""

# Create log group and stream
echo "[3.1] Creating log group and stream..."
aws logs create-log-group --log-group-name "/demo/application" 2>/dev/null || true
aws logs create-log-stream \
  --log-group-name "/demo/application" \
  --log-stream-name "web-server-01" 2>/dev/null || true
echo "  ✓ /demo/application/web-server-01"
echo ""

# Push sample log events
echo "[3.2] Pushing log events..."
TS=$(($(date +%s) * 1000))
aws logs put-log-events \
  --log-group-name "/demo/application" \
  --log-stream-name "web-server-01" \
  --log-events \
    timestamp=${TS},message="INFO: App started successfully" \
    timestamp=$((TS+1000)),message="INFO: Request processed status=200 latency=45ms" \
    timestamp=$((TS+2000)),message="ERROR: Database connection timeout after 30000ms" \
    timestamp=$((TS+3000)),message="ERROR: Database connection timeout after 30000ms" \
  --query 'nextSequenceToken' --output text
echo "  ✓ 4 log events pushed"
echo ""

# Search for ERROR patterns
echo "[3.3] Searching for ERROR pattern:"
sleep 2
aws logs filter-log-events \
  --log-group-name "/demo/application" \
  --filter-pattern "ERROR" \
  --query 'events[*].{Time:timestamp,Message:message}' --output table
echo ""

# Create metric filter to count errors
echo "[3.4] Creating metric filter (ERROR → ApplicationErrors metric)..."
aws logs put-metric-filter \
  --log-group-name "/demo/application" \
  --filter-name "ErrorCount" --filter-pattern "ERROR" \
  --metric-transformations metricName=ApplicationErrors,metricNamespace=DemoApp,metricValue=1
echo "  ✓ Logs → Metrics → Alarms pipeline configured"
echo ""

echo "========================================"
echo " Demo Complete!"
echo "========================================"
