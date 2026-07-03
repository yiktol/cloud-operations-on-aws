#!/bin/bash
# Module 02 - Live Demo: "The Deny Always Wins"
# Interactive - uses read prompts between acts

STACK_NAME="mod02-access-management-demo"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
GENERAL_BUCKET=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`GeneralBucketName`].OutputValue' --output text)
CONFIDENTIAL_BUCKET=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`ConfidentialBucketName`].OutputValue' --output text)

echo "============================================"
echo "  ACT 1: IMPLICIT DENY (no policies)"
echo "============================================"
echo ""
echo ">> demo-user tries to list S3 buckets (no policies attached)..."
read -p "Press Enter..."
aws s3 ls --profile demo-user 2>&1 || true
echo ""
echo ">> RESULT: Access Denied. Authentication does not equal Authorization."
echo ""

echo "============================================"
echo "  ACT 2: EXPLICIT ALLOW"
echo "============================================"
read -p "Press Enter to attach AllowS3Read policy..."
aws iam attach-user-policy --user-name demo-user \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/AllowS3Read-Demo
echo "AllowS3Read attached. Waiting 10s..."
sleep 10

echo ">> Listing buckets..."
aws s3 ls --profile demo-user
echo ""
echo ">> Reading general bucket..."
aws s3 cp s3://${GENERAL_BUCKET}/general-file.txt - --profile demo-user
echo ">> Reading confidential bucket..."
aws s3 cp s3://${CONFIDENTIAL_BUCKET}/secret-file.txt - --profile demo-user
echo ""
echo ">> RESULT: Both buckets accessible."
echo ""

echo "============================================"
echo "  ACT 3: EXPLICIT DENY ALWAYS WINS"
echo "============================================"
read -p "Press Enter to ALSO attach Deny policy..."
aws iam attach-user-policy --user-name demo-user \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/DenyConfidentialBucket-Demo
echo "Deny policy attached. Waiting 10s..."
sleep 10

echo ">> General bucket..."
aws s3 cp s3://${GENERAL_BUCKET}/general-file.txt - --profile demo-user
echo ">> Confidential bucket..."
aws s3 cp s3://${CONFIDENTIAL_BUCKET}/secret-file.txt - --profile demo-user 2>&1 || true
echo ""
echo ">> RESULT: General OK, Confidential DENIED. Deny always wins!"
echo ""

echo "============================================"
echo "  BONUS: ROLE ASSUMPTION"
echo "============================================"
read -p "Press Enter for role assumption demo..."
aws iam attach-user-policy --user-name demo-user \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/AllowAssumeEmergencyRole-Demo
sleep 5

echo ">> demo-user tries EC2 (no perms)..."
aws ec2 describe-instances --profile demo-user --max-items 1 2>&1 | head -3 || true
echo ""

ROLE_ARN=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`EmergencyAdminRoleArn`].OutputValue' --output text)

echo ">> Assuming EmergencyAdminRole..."
CREDS=$(aws sts assume-role --role-arn ${ROLE_ARN} --role-session-name emergency --profile demo-user)
export AWS_ACCESS_KEY_ID=$(echo $CREDS | python3 -c "import sys,json;print(json.load(sys.stdin)['Credentials']['AccessKeyId'])")
export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | python3 -c "import sys,json;print(json.load(sys.stdin)['Credentials']['SecretAccessKey'])")
export AWS_SESSION_TOKEN=$(echo $CREDS | python3 -c "import sys,json;print(json.load(sys.stdin)['Credentials']['SessionToken'])")

echo ">> Who am I now?"
aws sts get-caller-identity
echo ""
echo ">> EC2 describe with assumed role..."
aws ec2 describe-instances --max-items 1 --query 'Reservations[0].Instances[0].InstanceId' 2>&1 | head -3
echo ""
echo ">> RESULT: Temporary admin via role!"

unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
echo ""
echo "============ DEMO COMPLETE ============"
