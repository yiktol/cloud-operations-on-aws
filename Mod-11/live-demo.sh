#!/bin/bash
# Module 11 - Live Demo: Operate Secure and Resilient Networks
# Prereq: Run deploy.sh first
set -e

STACK_NAME="mod11-secure-networks-demo"
if [ -z "$FLOW_LOGS_ROLE" ]; then
  FLOW_LOGS_ROLE=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
    --query 'Stacks[0].Outputs[?OutputKey==`FlowLogsRoleArn`].OutputValue' --output text)
fi
REGION=$(aws configure get region)

echo "========================================"
echo " Module 11: Secure & Resilient Networks"
echo "========================================"
echo ""

# --- ACT 1: Build a Secure VPC ---
echo "--- ACT 1: Build a Secure VPC (Public + Private Subnets) ---"
echo ""

# Create VPC
echo "[1.1] Creating VPC (10.11.0.0/16):"
VPC_ID=$(aws ec2 create-vpc --cidr-block 10.11.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=Demo-SecureVPC}]' \
  --query 'Vpc.VpcId' --output text)
echo "  VPC: ${VPC_ID}"
echo ""

# Create subnets
echo "[1.2] Creating subnets:"
PUBLIC_SUBNET=$(aws ec2 create-subnet --vpc-id ${VPC_ID} \
  --cidr-block 10.11.1.0/24 \
  --availability-zone ${REGION}a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=Public-Subnet}]' \
  --query 'Subnet.SubnetId' --output text)
echo "  Public: ${PUBLIC_SUBNET} (10.11.1.0/24)"

PRIVATE_SUBNET=$(aws ec2 create-subnet --vpc-id ${VPC_ID} \
  --cidr-block 10.11.2.0/24 \
  --availability-zone ${REGION}a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=Private-Subnet}]' \
  --query 'Subnet.SubnetId' --output text)
echo "  Private: ${PRIVATE_SUBNET} (10.11.2.0/24)"
echo ""

# Attach internet gateway
echo "[1.3] Creating and attaching Internet Gateway:"
IGW_ID=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --internet-gateway-id ${IGW_ID} --vpc-id ${VPC_ID}
echo "  IGW: ${IGW_ID} → attached"
echo ""

# Create route table with internet route for public subnet
echo "[1.4] Creating public route table (0.0.0.0/0 → IGW):"
PUBLIC_RT=$(aws ec2 create-route-table --vpc-id ${VPC_ID} --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id ${PUBLIC_RT} \
  --destination-cidr-block 0.0.0.0/0 --gateway-id ${IGW_ID} > /dev/null
aws ec2 associate-route-table --route-table-id ${PUBLIC_RT} --subnet-id ${PUBLIC_SUBNET} > /dev/null
echo "  RT: ${PUBLIC_RT} → public subnet has internet access"
echo "  Private subnet: NO internet route (isolated)"
echo ""

# --- ACT 2: Security Groups vs NACLs ---
echo "--- ACT 2: Security Groups vs NACLs - Two Firewall Layers ---"
echo ""

# Security Group (STATEFUL)
echo "[2.1] Creating Security Group (STATEFUL):"
WEB_SG=$(aws ec2 create-security-group --group-name demo-web-sg \
  --description "Allow HTTP only" --vpc-id ${VPC_ID} --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id ${WEB_SG} \
  --protocol tcp --port 80 --cidr 0.0.0.0/0 > /dev/null
echo "  SG: ${WEB_SG} — Allow inbound HTTP (return traffic automatic)"
echo ""

echo "[2.2] Security Group rules:"
aws ec2 describe-security-groups --group-ids ${WEB_SG} \
  --query 'SecurityGroups[0].{Inbound:IpPermissions[0].IpRanges[0].CidrIp,Protocol:IpPermissions[0].IpProtocol,Port:IpPermissions[0].FromPort}' \
  --output table
echo ""

# NACL (STATELESS)
echo "[2.3] Creating NACL (STATELESS):"
NACL_ID=$(aws ec2 create-network-acl --vpc-id ${VPC_ID} \
  --tag-specifications 'ResourceType=network-acl,Tags=[{Key=Name,Value=Demo-NACL}]' \
  --query 'NetworkAcl.NetworkAclId' --output text)
echo "  NACL: ${NACL_ID}"

# Allow HTTP inbound
aws ec2 create-network-acl-entry --network-acl-id ${NACL_ID} \
  --rule-number 100 --protocol tcp --port-range From=80,To=80 \
  --cidr-block 0.0.0.0/0 --rule-action allow --ingress

# Must also allow ephemeral ports outbound (stateless!)
aws ec2 create-network-acl-entry --network-acl-id ${NACL_ID} \
  --rule-number 100 --protocol tcp --port-range From=1024,To=65535 \
  --cidr-block 0.0.0.0/0 --rule-action allow --egress
echo "  ✓ Inbound: HTTP 80 allowed"
echo "  ✓ Outbound: Ephemeral 1024-65535 allowed (must be explicit!)"
echo ""

echo "[2.4] NACL entries:"
aws ec2 describe-network-acls --network-acl-ids ${NACL_ID} \
  --query 'NetworkAcls[0].Entries[?RuleNumber!=`32767`].{Rule:RuleNumber,Egress:Egress,Action:RuleAction,Ports:PortRange}' \
  --output table
echo ""

# --- ACT 3: VPC Flow Logs - Network Forensics ---
echo "--- ACT 3: VPC Flow Logs - Network Forensics ---"
echo ""

# Enable flow logs on the VPC
echo "[3.1] Creating log group:"
aws logs create-log-group --log-group-name "/demo/vpc-flow-logs" 2>/dev/null || true
echo "  ✓ /demo/vpc-flow-logs"
echo ""

echo "[3.2] Enabling VPC Flow Logs (ALL traffic):"
FLOW_LOG_ID=$(aws ec2 create-flow-logs \
  --resource-type VPC --resource-ids ${VPC_ID} \
  --traffic-type ALL \
  --log-destination-type cloud-watch-logs \
  --log-group-name "/demo/vpc-flow-logs" \
  --deliver-logs-permission-arn ${FLOW_LOGS_ROLE} \
  --query 'FlowLogIds[0]' --output text)
echo "  Flow Log ID: ${FLOW_LOG_ID}"
echo ""

echo "[3.3] Flow log status:"
aws ec2 describe-flow-logs --flow-log-ids ${FLOW_LOG_ID} \
  --query 'FlowLogs[0].{Status:FlowLogStatus,Traffic:TrafficType,Destination:LogGroupName}' \
  --output table
echo ""

echo "  Note: Flow log data takes 5-10 minutes to appear in CloudWatch Logs."
echo "  Query with: aws logs filter-log-events --log-group-name /demo/vpc-flow-logs --filter-pattern REJECT"
echo ""

echo "========================================"
echo " Demo Complete!"
echo " VPC: ${VPC_ID}"
echo "========================================"
