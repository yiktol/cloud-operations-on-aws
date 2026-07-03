# Module 02 Demo: IAM Policy Evaluation — "The Deny Always Wins"

## Prerequisites
- AWS CLI configured with admin credentials
- An AWS account with permissions to create IAM users, policies, and S3 buckets

---

## Part 1: Setup (do before class)

### Step 1: Create the S3 buckets
```bash
# Replace UNIQUE_SUFFIX with something unique (e.g., your initials + date)
SUFFIX="demo-$(date +%Y%m%d)"

aws s3 mb s3://general-${SUFFIX}
aws s3 mb s3://confidential-${SUFFIX}

# Upload sample files
echo "This is general data." > /tmp/general-file.txt
echo "This is CONFIDENTIAL data." > /tmp/secret-file.txt

aws s3 cp /tmp/general-file.txt s3://general-${SUFFIX}/
aws s3 cp /tmp/secret-file.txt s3://confidential-${SUFFIX}/
```

### Step 2: Create the IAM policies

**Save as `allow-s3-read.json`:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowS3Read",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket",
        "s3:ListAllMyBuckets"
      ],
      "Resource": "*"
    }
  ]
}
```

**Save as `deny-confidential.json`** (replace SUFFIX):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyConfidentialBucket",
      "Effect": "Deny",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::confidential-SUFFIX",
        "arn:aws:s3:::confidential-SUFFIX/*"
      ]
    }
  ]
}
```

```bash
# Create the policies
aws iam create-policy \
  --policy-name AllowS3Read \
  --policy-document file://allow-s3-read.json

aws iam create-policy \
  --policy-name DenyConfidentialBucket \
  --policy-document file://deny-confidential.json
```

### Step 3: Create the demo IAM user
```bash
# Create user with programmatic access
aws iam create-user --user-name demo-user

# Create access keys (save the output!)
aws iam create-access-key --user-name demo-user
```

### Step 4: Configure a separate CLI profile for demo-user
```bash
aws configure --profile demo-user
# Enter the Access Key ID and Secret Access Key from Step 3
# Region: your preferred region
# Output: json
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
# Get your account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Attach the Allow policy
aws iam attach-user-policy \
  --user-name demo-user \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/AllowS3Read
```

> **Wait ~10 seconds for propagation, then:**

```bash
# List buckets
aws s3 ls --profile demo-user

# Read from general bucket
aws s3 cp s3://general-${SUFFIX}/general-file.txt - --profile demo-user

# Read from confidential bucket
aws s3 cp s3://confidential-${SUFFIX}/secret-file.txt - --profile demo-user
```

> **Expected:** ✅ All three commands succeed

> **Talking point:** "Now they can read BOTH buckets. The Allow policy grants access to ALL S3 resources. But what if we need to restrict access to the confidential bucket?"

---

### 🎬 Act 3: Explicit Deny ALWAYS wins

> **Say:** "Let's add a Deny policy for the confidential bucket — even though the Allow is still attached."

```bash
# Attach the Deny policy (Allow policy remains!)
aws iam attach-user-policy \
  --user-name demo-user \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/DenyConfidentialBucket
```

> **Wait ~10 seconds, then:**

```bash
# General bucket — still works
aws s3 cp s3://general-${SUFFIX}/general-file.txt - --profile demo-user

# Confidential bucket — DENIED
aws s3 cp s3://confidential-${SUFFIX}/secret-file.txt - --profile demo-user
```

> **Expected:**
> - ✅ General bucket: shows file content
> - ❌ Confidential bucket: `An error occurred (AccessDenied): Access Denied`

> **Talking point:** "Both policies are attached simultaneously. The Allow says 'yes to all S3'. The Deny says 'no to this bucket'. **Deny ALWAYS wins.** This is the foundation of how SCPs work in AWS Organizations — they're deny guardrails that no amount of Allow policies can override."

---

### 🎬 Bonus Act: IAM Role Assumption (if time permits)

> **Say:** "What if demo-user needs temporary admin access for an emergency? We don't give them permanent admin credentials — we use a ROLE."

```bash
# Create a trust policy that allows demo-user to assume the role
cat > trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${ACCOUNT_ID}:user/demo-user"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Create the emergency admin role
aws iam create-role \
  --role-name EmergencyAdminRole \
  --assume-role-policy-document file://trust-policy.json

# Attach admin policy to the role
aws iam attach-role-policy \
  --role-name EmergencyAdminRole \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

# Give demo-user permission to assume this role
cat > allow-assume-role.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "arn:aws:iam::${ACCOUNT_ID}:role/EmergencyAdminRole"
    }
  ]
}
EOF

aws iam create-policy \
  --policy-name AllowAssumeEmergencyRole \
  --policy-document file://allow-assume-role.json

aws iam attach-user-policy \
  --user-name demo-user \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/AllowAssumeEmergencyRole
```

> **Demo the assumption:**

```bash
# First show that demo-user can't create an EC2 instance (no EC2 perms)
aws ec2 describe-instances --profile demo-user
# ❌ Access Denied

# Now assume the role
CREDS=$(aws sts assume-role \
  --role-arn arn:aws:iam::${ACCOUNT_ID}:role/EmergencyAdminRole \
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
# Detach policies from user
aws iam detach-user-policy --user-name demo-user \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/AllowS3Read
aws iam detach-user-policy --user-name demo-user \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/DenyConfidentialBucket
aws iam detach-user-policy --user-name demo-user \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/AllowAssumeEmergencyRole

# Delete access keys
ACCESS_KEY=$(aws iam list-access-keys --user-name demo-user --query 'AccessKeyMetadata[0].AccessKeyId' --output text)
aws iam delete-access-key --user-name demo-user --access-key-id $ACCESS_KEY

# Delete user
aws iam delete-user --user-name demo-user

# Delete policies
aws iam delete-policy --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/AllowS3Read
aws iam delete-policy --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/DenyConfidentialBucket
aws iam delete-policy --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/AllowAssumeEmergencyRole

# Detach and delete role
aws iam detach-role-policy --role-name EmergencyAdminRole \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
aws iam delete-role --role-name EmergencyAdminRole

# Delete S3 buckets
aws s3 rb s3://general-${SUFFIX} --force
aws s3 rb s3://confidential-${SUFFIX} --force

# Unset environment variables
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
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
