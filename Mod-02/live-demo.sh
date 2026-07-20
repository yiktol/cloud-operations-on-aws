#!/bin/bash
# Module 02 - Live Demo: The Deny Always Wins

STACK_NAME="mod02-access-management-demo"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
GENERAL_BUCKET=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`GeneralBucketName`].OutputValue' --output text)
CONFIDENTIAL_BUCKET=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`ConfidentialBucketName`].OutputValue' --output text)

# --- ACT 1: Implicit Deny (no policies attached) ---
# demo-user tries to list S3 buckets with no policies
aws s3 ls --profile demo-user 2>&1 || true

# --- ACT 2: Explicit Allow ---
# Attach AllowS3Read policy to demo-user
aws iam attach-user-policy --user-name demo-user \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/AllowS3Read-Demo
sleep 10

# List buckets with the allow policy
aws s3 ls --profile demo-user

# Read from both buckets (both should succeed)
aws s3 cp s3://${GENERAL_BUCKET}/general-file.txt - --profile demo-user
aws s3 cp s3://${CONFIDENTIAL_BUCKET}/secret-file.txt - --profile demo-user

# --- ACT 3: Explicit Deny Always Wins ---
# Attach deny policy for confidential bucket
aws iam attach-user-policy --user-name demo-user \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/DenyConfidentialBucket-Demo
sleep 10

# General bucket still works
aws s3 cp s3://${GENERAL_BUCKET}/general-file.txt - --profile demo-user

# Confidential bucket denied even though allow exists
aws s3 cp s3://${CONFIDENTIAL_BUCKET}/secret-file.txt - --profile demo-user 2>&1 || true

# --- BONUS: Role Assumption ---
# Allow demo-user to assume the emergency role
aws iam attach-user-policy --user-name demo-user \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/AllowAssumeEmergencyRole-Demo
sleep 5

# demo-user has no EC2 permissions directly
aws ec2 describe-instances --profile demo-user --max-items 1 2>&1 || true

# Assume the EmergencyAdminRole for temporary elevated access
ROLE_ARN=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`EmergencyAdminRoleArn`].OutputValue' --output text)

CREDS=$(aws sts assume-role --role-arn ${ROLE_ARN} --role-session-name emergency --profile demo-user)
export AWS_ACCESS_KEY_ID=$(echo $CREDS | python3 -c "import sys,json;print(json.load(sys.stdin)['Credentials']['AccessKeyId'])")
export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | python3 -c "import sys,json;print(json.load(sys.stdin)['Credentials']['SecretAccessKey'])")
export AWS_SESSION_TOKEN=$(echo $CREDS | python3 -c "import sys,json;print(json.load(sys.stdin)['Credentials']['SessionToken'])")

# Verify assumed identity
aws sts get-caller-identity

# EC2 now works with the assumed role
aws ec2 describe-instances --max-items 1 \
  --query 'Reservations[0].Instances[0].InstanceId' --output text

unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
