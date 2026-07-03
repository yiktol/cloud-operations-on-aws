# Module 09 Demo: Monitor and Maintain System Health — "CloudWatch Deep Dive"

## Prerequisites
- AWS CLI configured with admin credentials
- At least one running EC2 instance
- (Optional) An application generating logs

---

## Part 1: Setup (do before class)

```bash
INSTANCE_ID="i-XXXXXXXXXXXX"

# Install CloudWatch agent and generate some log data
aws ssm send-command \
  --instance-ids ${INSTANCE_ID} \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=[
    "sudo yum install -y amazon-cloudwatch-agent",
    "for i in $(seq 1 50); do logger -t demo-app \"Request processed: status=200 latency=${RANDOM}ms\"; done",
    "for i in $(seq 1 5); do logger -t demo-app \"ERROR: Connection timeout after 30000ms\"; done"
  ]'
```

---

## Part 2: Live Demo (in class)

### 🎬 Act 1: CloudWatch Metrics — The Vital Signs

> **Say:** "CloudWatch collects metrics from every AWS service automatically. Let's look at our EC2 instance's vital signs."

```bash
# View available metrics for our instance
aws cloudwatch list-metrics \
  --namespace AWS/EC2 \
  --dimensions Name=InstanceId,Value=${INSTANCE_ID} \
  --query 'Metrics[*].MetricName' --output table

# Get CPU utilization for the last hour
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value=${INSTANCE_ID} \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average Maximum \
  --output table

# Publish a custom metric (application-level)
aws cloudwatch put-metric-data \
  --namespace "DemoApp" \
  --metric-name "OrdersProcessed" \
  --value 42 \
  --unit Count \
  --dimensions Name=Environment,Value=Production

aws cloudwatch put-metric-data \
  --namespace "DemoApp" \
  --metric-name "OrdersProcessed" \
  --value 87 \
  --unit Count \
  --dimensions Name=Environment,Value=Production

echo "Custom metric published!"
```

> **Talking points:**
> - "AWS sends metrics automatically — CPU, network, disk. No setup needed."
> - "Custom metrics let you track BUSINESS data — orders processed, user signups, queue depth."
> - "Period=300 means 5-minute aggregation. You can go as granular as 1 second (for a cost)."

---

### 🎬 Act 2: CloudWatch Alarms — Automated Alerting

> **Say:** "Metrics are useless if no one is watching. Alarms watch FOR you and take action."

```bash
# Create an alarm: CPU > 80% for 2 consecutive periods
aws cloudwatch put-metric-alarm \
  --alarm-name "Demo-HighCPU" \
  --metric-name CPUUtilization \
  --namespace AWS/EC2 \
  --statistic Average \
  --period 60 \
  --evaluation-periods 2 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=InstanceId,Value=${INSTANCE_ID} \
  --alarm-description "Alert when CPU exceeds 80% for 2 minutes" \
  --treat-missing-data missing

# Check alarm state
aws cloudwatch describe-alarms \
  --alarm-names "Demo-HighCPU" \
  --query 'MetricAlarms[0].{Name:AlarmName,State:StateValue,Threshold:Threshold,Metric:MetricName}' \
  --output table

# Manually set alarm state to demonstrate (in real life, CPU spike triggers it)
aws cloudwatch set-alarm-state \
  --alarm-name "Demo-HighCPU" \
  --state-value ALARM \
  --state-reason "Demo: simulating high CPU"

# Check again
aws cloudwatch describe-alarms --alarm-names "Demo-HighCPU" \
  --query 'MetricAlarms[0].StateValue'
```

> **Talking points:**
> - "evaluation-periods=2 prevents false alarms from momentary spikes."
> - "In production, you'd add an SNS action to email/page your on-call team."
> - "Alarms also drive Auto Scaling — this is how scaling policies know when to act."

---

### 🎬 Act 3: CloudWatch Logs — Centralized Logging

> **Say:** "Logs scattered across 50 instances are impossible to search. CloudWatch Logs centralizes them."

```bash
# Create a log group
aws logs create-log-group --log-group-name "/demo/application"

# Create a log stream
aws logs create-log-stream \
  --log-group-name "/demo/application" \
  --log-stream-name "web-server-01"

# Put some log events
TIMESTAMP=$(($(date +%s) * 1000))
aws logs put-log-events \
  --log-group-name "/demo/application" \
  --log-stream-name "web-server-01" \
  --log-events \
    timestamp=${TIMESTAMP},message="INFO: Application started successfully" \
    timestamp=$((TIMESTAMP+1000)),message="INFO: Request processed: status=200 latency=45ms" \
    timestamp=$((TIMESTAMP+2000)),message="ERROR: Database connection timeout after 30000ms" \
    timestamp=$((TIMESTAMP+3000)),message="WARN: Retry attempt 1 of 3" \
    timestamp=$((TIMESTAMP+4000)),message="ERROR: Database connection timeout after 30000ms"

# Search the logs with filter pattern
aws logs filter-log-events \
  --log-group-name "/demo/application" \
  --filter-pattern "ERROR" \
  --output table

# Create a metric filter (count errors automatically)
aws logs put-metric-filter \
  --log-group-name "/demo/application" \
  --filter-name "ErrorCount" \
  --filter-pattern "ERROR" \
  --metric-transformations \
    metricName=ApplicationErrors,metricNamespace=DemoApp,metricValue=1
```

> **Talking points:**
> - "Logs from ALL instances stream here — one place to search."
> - "Filter patterns find needles in haystacks — search for ERROR across millions of lines."
> - "Metric filters TURN logs INTO metrics — then you alarm on them. 'Alert me if error count > 10 in 5 minutes.'"

---

## Part 3: Cleanup

```bash
aws cloudwatch delete-alarms --alarm-names "Demo-HighCPU"
aws logs delete-log-group --log-group-name "/demo/application"
aws cloudwatch delete-dashboards --dashboard-names "Demo-Dashboard" 2>/dev/null
```

---

## Summary Table

| Tool | Purpose | Key insight |
|------|---------|-------------|
| **CloudWatch Metrics** | Numerical time-series data | Auto-collected + custom metrics |
| **CloudWatch Alarms** | Threshold-based alerting | Drives notifications + auto-scaling |
| **CloudWatch Logs** | Centralized log aggregation | Filter → Metric → Alarm pipeline |

---

## Timing Guide

| Section | Duration |
|---------|----------|
| Act 1 (Metrics) | 5 min |
| Act 2 (Alarms) | 4 min |
| Act 3 (Logs) | 5 min |
| **Total** | **~14 min** |
