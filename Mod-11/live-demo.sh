#!/bin/bash
# Module 11 - Live Demo: Operate Secure and Resilient Networks
STACK_NAME="mod11-secure-networks-demo"
if [ -z "$FLOW_LOGS_ROLE" ]; then
  FLOW_LOGS_ROLE=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
    --query 'Stacks[0].Outputs[?OutputKey==`FlowLogsRoleArn`].OutputValue' --output text)
fi
REGION=$(aws configure get region)

echo "============================================"
echo "  ACT 1: BUILD A SECURE VPC"
echo "============================================"
read -p "Press Enter..."
VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=Demo-SecureVPC}]' \
  --query 'Vpc.VpcId' --output text)

PUBLIC_SUBNET=$(aws ec2 create-subnet --vpc-id ${VPC_ID} \
  --cidr-block 10.0.1.0/24 \
  --availability-zone ${REGION}a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=Public-Subnet}]' \
  --query 'Subnet.SubnetId' --output text)

PRIVATE_SUBNET=$(aws ec2 create-subnet --vpc-id ${VPC_ID} \
  --cidr-block 10.0.2.0/24 \
  --availability-zone ${REGION}a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=Private-Subnet}]' \
  --query 'Subnet.SubnetId' --output text)

IGW_ID=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --internet-gateway-id ${IGW_ID} --vpc-id ${VPC_ID}

PUBLIC_RT=$(aws ec2 create-route-table --vpc-id ${VPC_ID} --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id ${PUBLIC_RT} --destination-cidr-block 0.0.0.0/0 --gateway-id ${IGW_ID}
aws ec2 associate-route-table --route-table-id ${PUBLIC_RT} --subnet-id ${PUBLIC_SUBNET}

echo "  VPC: ${VPC_ID}"
echo "  Public Subnet: ${PUBLIC_SUBNET} (internet route via IGW)"
echo "  Private Subnet: ${PRIVATE_SUBNET} (no internet - isolated)"
echo ""
echo ">> RESULT: Defense in depth. Public-facing resources in public, DB/backend in private."

echo ""
echo "============================================"
echo "  ACT 2: SECURITY GROUPS vs NACLs"
echo "============================================"
read -p "Press Enter..."
WEB_SG=$(aws ec2 create-security-group --group-name demo-web-sg \
  --description "Allow HTTP only" --vpc-id ${VPC_ID} --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id ${WEB_SG} \
  --protocol tcp --port 80 --cidr 0.0.0.0/0

echo ">> Security Group (STATEFUL) - only inbound needed:"
aws ec2 describe-security-groups --group-ids ${WEB_SG} \
  --query 'SecurityGroups[0].{Inbound:IpPermissions[0].IpRanges}' --output table
echo "  Return traffic allowed AUTOMATICALLY (stateful)"

echo ""
echo ">> Creating NACL (STATELESS) - must allow BOTH directions explicitly..."
read -p "Press Enter..."
NACL_ID=$(aws ec2 create-network-acl --vpc-id ${VPC_ID} \
  --tag-specifications 'ResourceType=network-acl,Tags=[{Key=Name,Value=Demo-NACL}]' \
  --query 'NetworkAcl.NetworkAclId' --output text)

# Allow HTTP inbound
aws ec2 create-network-acl-entry --network-acl-id ${NACL_ID} \
  --rule-number 100 --protocol tcp --port-range From=80,To=80 \
  --cidr-block 0.0.0.0/0 --rule-action allow --ingress
# MUST also allow ephemeral ports outbound (stateless!)
aws ec2 create-network-acl-entry --network-acl-id ${NACL_ID} \
  --rule-number 100 --protocol tcp --port-range From=1024,To=65535 \
  --cidr-block 0.0.0.0/0 --rule-action allow --egress

aws ec2 describe-network-acls --network-acl-ids ${NACL_ID} \
  --query 'NetworkAcls[0].Entries[?RuleNumber!=`32767`].{Rule:RuleNumber,Egress:Egress,Action:RuleAction,Ports:PortRange}' \
  --output table

echo ""
echo ">> KEY DIFFERENCE:"
echo "   Security Groups = STATEFUL (instance-level) - return traffic auto-allowed"
echo "   NACLs = STATELESS (subnet-level) - must explicitly allow both directions"

echo ""
echo "============================================"
echo "  ACT 3: VPC FLOW LOGS - NETWORK FORENSICS"
echo "============================================"
read -p "Press Enter..."
aws logs create-log-group --log-group-name "/demo/vpc-flow-logs" 2>/dev/null || true

aws ec2 create-flow-log \
  --resource-type VPC --resource-ids ${VPC_ID} \
  --traffic-type ALL \
  --log-destination-type cloud-watch-logs \
  --log-group-name "/demo/vpc-flow-logs" \
  --deliver-logs-permission-arn ${FLOW_LOGS_ROLE} \
  --query 'FlowLogIds[0]' --output text 2>/dev/null || \
  echo "  Flow log creation - may need a moment"

echo "  Flow Logs enabled. Sample log format:"
echo ""
echo "  2 <account> <eni> <src-ip> <dst-ip> <dst-port> <src-port> <proto> <pkt> <bytes> <start> <end> ACCEPT|REJECT"
echo ""
echo "  Filtering for REJECT entries shows exactly what is being blocked:"
echo "  aws logs filter-log-events --log-group-name /demo/vpc-flow-logs --filter-pattern REJECT"
echo ""
echo ">> RESULT: Flow Logs = network forensics. Instantly answer 'why can't A talk to B?'"
echo ""
echo "============ DEMO COMPLETE ============"
