# Module 02 Demo: IAM Policy Evaluation — "The Deny Always Wins"

## Prerequisites
- AWS CLI configured with admin credentials
- Module 02 CloudFormation stack deployed (`Mod-02/cfn-setup.yaml`)

---

## Part 1: Setup (do before class)

### Deploy the CloudFormation stack
The stack creates: S3 buckets, IAM policies, demo-user, access keys, and the EmergencyAdminRole.

```bash
aws cloudformation deploy \
  --template-file Mod-02/cfn-setup.yaml \
  --stack-name mod02-demo \
  --capabilities CAPABILITY_NAMED_IAM
```

### Upload sample files to buckets
```bash
# Get bucket names from stack outputs
GENERAL_BUCKET=$(aws cloudformation describe-stacks --stack-name mod02-demo --query "Stacks[0].Outputs[?OutputKey=='GeneralBucketName'].OutputValue" --output text)
CONFIDENTIAL_BUCKET=$(aws cloudformation describe-stacks --stack-name mod02-demo --query "Stacks[0].Outputs[?OutputKey=='ConfidentialBucketName'].OutputValue" --output text)

echo "This is general data." > /tmp/general-file.txt
echo "This is CONFIDENTIAL data." > /tmp/secret-file.txt

aws s3 cp /tmp/general-file.txt s3://${GENERAL_BUCKET}/
aws s3 cp /tmp/secret-file.txt s3://${CONFIDENTIAL_BUCKET}/
```

### Configure a CLI profile for demo-user
```bash
# Get credentials from stack outputs
ACCESS_KEY=$(aws cloudformation describe-stacks --stack-name mod02-demo --query "Stacks[0].Outputs[?OutputKey=='DemoUserAccessKeyId'].OutputValue" --output text)
SECRET_KEY=$(aws cloudformation describe-stacks --stack-name mod02-demo --query "Stacks[0].Outputs[?OutputKey=='DemoUserSecretKey'].OutputValue" --output text)

aws configure set aws_access_key_id $ACCESS_KEY --profile demo-user
aws configure set aws_secret_access_key $SECRET_KEY --profile demo-user
aws configure set region $(aws configure get region) --profile demo-user
aws configure set output json --profile demo-user
```

---

## Part 2: Live Demo (in class)

### 🎬 Act 1: Implicit Deny (no policies attached)

> **Say:** "Our demo-user has authenticated — they have valid credentials. But what happens when they try to DO something?"

```bash
# Try to list S3 buckets as demo-user
aws s3 ls --profile demo-user
```

> **Expected output:**
> ```
> An error occurred (AccessDenied): Access Denied
> ```

> **Talking point:** "Authentication ≠ Authorization. This user can sign in, but with ZERO policies attached, everything is implicitly denied. This is the default — deny unless explicitly allowed."

---

### 🎬 Act 2: Explicit Allow opens the door

> **Say:** "Now let's give them read access to S3."

```bash
# Get policy ARN from stack outputs
ALLOW_S3_ARN=$(aws cloudformation describe-stacks --stack-name mod02-demo --query "Stacks[0].Outputs[?OutputKey=='AllowS3ReadPolicyArn'].OutputValue" --output text)

# Attach the Allow policy
aws iam attach-user-policy \
  --user-name demo-user \
  --policy-arn $ALLOW_S3_ARN
```

> **Wait ~10 seconds for propagation, then:**

```bash
# List buckets
aws s3 ls --profile demo-user

# Read from general bucket
aws s3 cp s3://${GENERAL_BUCKET}/general-file.txt - --profile demo-user

# Read from confidential bucket
aws s3 cp s3://${CONFIDENTIAL_BUCKET}/secret-file.txt - --profile demo-user
```

> **Expected:** ✅ All three commands succeed

> **Talking point:** "Now they can read BOTH buckets. The Allow policy grants access to ALL S3 resources. But what if we need to restrict access to the confidential bucket?"

---

### 🎬 Act 3: Explicit Deny ALWAYS wins

> **Say:** "Let's add a Deny policy for the confidential bucket — even though the Allow is still attached."

```bash
# Get deny policy ARN from stack outputs
DENY_ARN=$(aws cloudformation describe-stacks --stack-name mod02-demo --query "Stacks[0].Outputs[?OutputKey=='DenyConfidentialPolicyArn'].OutputValue" --output text)

# Attach the Deny policy (Allow policy remains!)
aws iam attach-user-policy \
  --user-name demo-user \
  --policy-arn $DENY_ARN
```

> **Wait ~10 seconds, then:**

```bash
# General bucket — still works
aws s3 cp s3://${GENERAL_BUCKET}/general-file.txt - --profile demo-user

# Confidential bucket — DENIED
aws s3 cp s3://${CONFIDENTIAL_BUCKET}/secret-file.txt - --profile demo-user
```

> **Expected:**
> - ✅ General bucket: shows file content
> - ❌ Confidential bucket: `An error occurred (AccessDenied): Access Denied`

> **Talking point:** "Both policies are attached simultaneously. The Allow says 'yes to all S3'. The Deny says 'no to this bucket'. **Deny ALWAYS wins.** This is the foundation of how SCPs work in AWS Organizations — they're deny guardrails that no amount of Allow policies can override."

---

### 🎬 Bonus Act: IAM Role Assumption (if time permits)

> **Say:** "What if demo-user needs temporary admin access for an emergency? We don't give them permanent admin credentials — we use a ROLE."

```bash
# Get the role ARN and assume-role policy ARN from stack outputs
ROLE_ARN=$(aws cloudformation describe-stacks --stack-name mod02-demo --query "Stacks[0].Outputs[?OutputKey=='EmergencyAdminRoleArn'].OutputValue" --output text)
ASSUME_ROLE_ARN=$(aws cloudformation describe-stacks --stack-name mod02-demo --query "Stacks[0].Outputs[?OutputKey=='AllowAssumeRolePolicyArn'].OutputValue" --output text)

# Give demo-user permission to assume the role
aws iam attach-user-policy \
  --user-name demo-user \
  --policy-arn $ASSUME_ROLE_ARN
```

> **Demo the assumption:**

```bash
# First show that demo-user can't create an EC2 instance (no EC2 perms)
aws ec2 describe-instances --profile demo-user
# ❌ Access Denied

# Now assume the role
CREDS=$(aws sts assume-role \
  --role-arn $ROLE_ARN \
  --role-session-name emergency-session \
  --profile demo-user)

# Extract temporary credentials
export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r '.Credentials.SessionToken')

# Now try again with the assumed role
aws ec2 describe-instances
# ✅ Works! (returns instances or empty list)

# Show who we are now
aws sts get-caller-identity
# Shows: "AssumedRole/EmergencyAdminRole/emergency-session"
```

> **Talking point:** "The user didn't get permanent admin access. They got TEMPORARY credentials that expire. This is auditable via CloudTrail — you can see exactly who assumed the role and when. This is how you grant privileged access safely."

---

## Part 3: Cleanup

```bash
# Delete the stack (removes user, policies, role, buckets)
aws cloudformation delete-stack --stack-name mod02-demo

# Unset environment variables
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

# Remove the CLI profile
aws configure --profile demo-user set aws_access_key_id ""
aws configure --profile demo-user set aws_secret_access_key ""
```

---

## Summary Slide / Whiteboard

| Scenario | Result | Why |
|----------|--------|-----|
| No policy attached | ❌ Denied | Implicit Deny (default) |
| Allow S3 Read attached | ✅ All buckets | Explicit Allow |
| Allow + Deny attached | ✅ General ❌ Confidential | **Explicit Deny always wins** |
| Role assumed | ✅ Temp admin | Temporary credentials via STS |

---

## Timing Guide

| Section | Duration |
|---------|----------|
| Act 1 (Implicit Deny) | 2 min |
| Act 2 (Explicit Allow) | 3 min |
| Act 3 (Deny Wins) | 4 min |
| Bonus (Role Assumption) | 5 min |
| **Total** | **~14 min** |
