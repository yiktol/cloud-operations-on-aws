#!/bin/bash
# Mod-05 - Deploy Setup Stack
set -e
STACK_NAME="mod05-automate-deployment-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[DEPLOY] Mod-05 Demo Stack..."
aws cloudformation deploy \
  --template-file "${SCRIPT_DIR}/cfn-setup.yaml" \
  --stack-name ${STACK_NAME} \
  --capabilities CAPABILITY_NAMED_IAM \
  --no-fail-on-empty-changeset

echo ""
echo "[OUTPUTS]"
aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[*].{Key:OutputKey,Value:OutputValue}' --output table

TEMPLATE_BUCKET=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`TemplateBucketName`].OutputValue' --output text)

echo "[SETUP] Writing webapp-stack.yaml template..."
cat > /tmp/webapp-stack.yaml << 'CFNEOF'
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Demo webapp stack - VPC, Subnet, Security Group, EC2'

Parameters:
  EnvironmentType:
    Type: String
    Default: Development
    AllowedValues: [Development, Production]

Conditions:
  IsProduction: !Equals [!Ref EnvironmentType, Production]

Mappings:
  InstanceTypeMap:
    Development:
      InstanceType: t3.micro
    Production:
      InstanceType: t3.small

Resources:
  DemoVPC:
    Type: AWS::EC2::VPC
    Properties:
      CidrBlock: 10.0.0.0/16
      EnableDnsHostnames: true
      Tags:
        - Key: Name
          Value: !Sub '${EnvironmentType}-VPC'

  DemoSubnet:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref DemoVPC
      CidrBlock: 10.0.1.0/24
      AvailabilityZone: !Select [0, !GetAZs '']

  DemoSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: Allow HTTP
      VpcId: !Ref DemoVPC
      SecurityGroupIngress:
        - IpProtocol: tcp
          FromPort: 80
          ToPort: 80
          CidrIp: 0.0.0.0/0

  DemoInstance:
    Type: AWS::EC2::Instance
    Properties:
      ImageId: !Sub '{{resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64}}'
      InstanceType: !FindInMap [InstanceTypeMap, !Ref EnvironmentType, InstanceType]
      SubnetId: !Ref DemoSubnet
      SecurityGroupIds: [!Ref DemoSecurityGroup]
      Tags:
        - Key: Name
          Value: !Sub '${EnvironmentType}-WebServer'
        - Key: Environment
          Value: !Ref EnvironmentType

Outputs:
  VPCId:
    Value: !Ref DemoVPC
  InstanceId:
    Value: !Ref DemoInstance
  InstanceType:
    Value: !FindInMap [InstanceTypeMap, !Ref EnvironmentType, InstanceType]
CFNEOF

echo "[SETUP] Uploading template to S3..."
aws s3 cp /tmp/webapp-stack.yaml s3://${TEMPLATE_BUCKET}/webapp-stack.yaml
cp /tmp/webapp-stack.yaml "${SCRIPT_DIR}/webapp-stack.yaml"

echo "[DONE] Setup complete!"
echo "  Template ready at: ${SCRIPT_DIR}/webapp-stack.yaml"
echo "  export TEMPLATE_BUCKET=${TEMPLATE_BUCKET}"
