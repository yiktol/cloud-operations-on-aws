# Module 11 Demo: Operate Secure and Resilient Networks — "VPC Security Layers"

## Prerequisites
- AWS CLI configured with admin credentials

---

## Part 1: Setup (do before class)

(Minimal setup — we build the VPC live for educational value)

---

## Part 2: Live Demo (in class)

### 🎬 Act 1: Build a Secure VPC (Public + Private Subnets)

> **Say:** "A VPC is your isolated network in the cloud. Let's build one with proper security layers — public and private subnets."

```bash
# Create VPC
VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=Demo-SecureVPC}]' \
  --query 'Vpc.VpcId' --output text)

# Create subnets
PUBLIC_SUBNET=$(aws ec2 create-subnet --vpc-id ${VPC_ID} \
  --cidr-block 10.0.1.0/24 --availability-zone ${REGION}a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=Public-Subnet}]' \
  --query 'Subnet.SubnetId' --output text)

PRIVATE_SUBNET=$(aws ec2 create-subnet --vpc-id ${VPC_ID} \
  --cidr-block 10.0.2.0/24 --availability-zone ${REGION}a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=Private-Subnet}]' \
  --query 'Subnet.SubnetId' --output text)

# Internet Gateway (public access)
IGW_ID=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --internet-gateway-id ${IGW_ID} --vpc-id ${VPC_ID}

# Route table for public subnet
PUBLIC_RT=$(aws ec2 create-route-table --vpc-id ${VPC_ID} --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id ${PUBLIC_RT} --destination-cidr-block 0.0.0.0/0 --gateway-id ${IGW_ID}
aws ec2 associate-route-table --route-table-id ${PUBLIC_RT} --subnet-id ${PUBLIC_SUBNET}

echo "VPC: ${VPC_ID}"
echo "Public Subnet: ${PUBLIC_SUBNET} (has internet access)"
echo "Private Subnet: ${PRIVATE_SUBNET} (isolated)"
```

> **Talking points:**
> - "Public subnet has a route to the internet via the Internet Gateway."
> - "Private subnet has NO route to the internet — databases and backend servers go here."
> - "This is defense in depth — even if the public-facing server is compromised, the backend is unreachable."

---

### 🎬 Act 2: Security Groups vs NACLs — Two Layers of Firewall

> **Say:** "AWS gives you TWO firewall layers. Let's see how they differ."

```bash
# Create a security group (stateful)
WEB_SG=$(aws ec2 create-security-group --group-name demo-web-sg \
  --description "Allow HTTP only" --vpc-id ${VPC_ID} \
  --query GroupId --output text)

aws ec2 authorize-security-group-ingress --group-id ${WEB_SG} \
  --protocol tcp --port 80 --cidr 0.0.0.0/0

# Show it — note: no outbound rule needed (stateful!)
aws ec2 describe-security-groups --group-ids ${WEB_SG} \
  --query 'SecurityGroups[0].{Inbound:IpPermissions,Outbound:IpPermissionsEgress}' \
  --output json

echo "Security Group: STATEFUL — return traffic automatically allowed"

# Create a NACL (stateless)
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

echo "NACL: STATELESS — must explicitly allow BOTH directions"

# Show the NACL rules
aws ec2 describe-network-acls --network-acl-ids ${NACL_ID} \
  --query 'NetworkAcls[0].Entries[?RuleNumber!=`32767`].{Rule:RuleNumber,Direction:Egress,Action:RuleAction,Port:PortRange,CIDR:CidrBlock}' \
  --output table
```

> **Talking points:**
> - "Security Groups are STATEFUL — if you allow inbound, the response goes out automatically."
> - "NACLs are STATELESS — you must allow BOTH inbound AND outbound explicitly."
> - "Security Groups = instance-level. NACLs = subnet-level."
> - "Use NACLs for broad subnet-level denies. Use Security Groups for fine-grained instance control."

---

### 🎬 Act 3: VPC Flow Logs — Network Forensics

> **Say:** "When something gets blocked and you don't know why, Flow Logs tell you exactly what traffic was accepted or rejected."

```bash
# Create a CloudWatch log group for flow logs
aws logs create-log-group --log-group-name "/demo/vpc-flow-logs"

# Create a flow log role (simplified)
FLOW_LOG_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/VPCFlowLogsRole"

# Enable VPC Flow Logs
FLOW_LOG_ID=$(aws ec2 create-flow-log \
  --resource-type VPC \
  --resource-ids ${VPC_ID} \
  --traffic-type ALL \
  --log-destination-type cloud-watch-logs \
  --log-group-name "/demo/vpc-flow-logs" \
  --deliver-logs-permission-arn ${FLOW_LOG_ROLE_ARN} \
  --query 'FlowLogIds[0]' --output text 2>/dev/null) || echo "Note: Flow log role needs to be pre-created"

echo "Flow Logs enabled! All traffic (ACCEPT + REJECT) is now recorded."

# Show what flow log data looks like
echo "
Sample flow log entry:
2 123456789012 eni-abc123 10.0.1.5 203.0.113.12 443 49152 6 25 20000 1620140661 1620140721 ACCEPT OK
|  |           |          |src     |dst          |dp |sp    |T |pkt|bytes|start      |end        |action

Fields: version account-id interface src-addr dst-addr dst-port src-port protocol packets bytes start end action log-status
"

# Query flow logs (if data exists)
aws logs filter-log-events \
  --log-group-name "/demo/vpc-flow-logs" \
  --filter-pattern "REJECT" \
  --max-items 5 2>/dev/null || echo "(Flow logs take 5-10 minutes to populate)"
```

> **Talking points:**
> - "Flow Logs record EVERY network connection attempt — accepted AND rejected."
> - "Filter for REJECT to find what's being blocked — instant troubleshooting."
> - "This is your network forensics tool — 'why can't server A talk to server B?'"

---

## Part 3: Cleanup

```bash
# Delete flow log
aws ec2 delete-flow-logs --flow-log-ids ${FLOW_LOG_ID} 2>/dev/null

# Delete NACL
aws ec2 delete-network-acl --network-acl-id ${NACL_ID}

# Delete security group
aws ec2 delete-security-group --group-id ${WEB_SG}

# Delete subnets
aws ec2 delete-subnet --subnet-id ${PUBLIC_SUBNET}
aws ec2 delete-subnet --subnet-id ${PRIVATE_SUBNET}

# Detach and delete IGW
aws ec2 detach-internet-gateway --internet-gateway-id ${IGW_ID} --vpc-id ${VPC_ID}
aws ec2 delete-internet-gateway --internet-gateway-id ${IGW_ID}

# Delete route table
aws ec2 delete-route-table --route-table-id ${PUBLIC_RT}

# Delete VPC
aws ec2 delete-vpc --vpc-id ${VPC_ID}

# Delete log group
aws logs delete-log-group --log-group-name "/demo/vpc-flow-logs"
```

---

## Summary Table

| Layer | Tool | Scope | Key difference |
|-------|------|-------|----------------|
| **Network isolation** | VPC + Subnets | Account-level | Public vs Private |
| **Instance firewall** | Security Groups | Instance-level | Stateful |
| **Subnet firewall** | NACLs | Subnet-level | Stateless |
| **Network audit** | VPC Flow Logs | VPC/subnet/ENI | Accept + Reject records |

---

## Timing Guide

| Section | Duration |
|---------|----------|
| Act 1 (VPC build) | 5 min |
| Act 2 (SG vs NACL) | 5 min |
| Act 3 (Flow Logs) | 4 min |
| **Total** | **~14 min** |
