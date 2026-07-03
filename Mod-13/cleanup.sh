#!/bin/bash
# Module 13 - Cleanup
set -e
STACK_NAME="mod13-object-storage-demo"

echo "[CLEANUP] Module 13 Demo..."

BUCKET=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' --output text 2>/dev/null)

if [ -n "$BUCKET" ] && [ "$BUCKET" != "None" ]; then
  echo "[INFO] Removing all object versions from ${BUCKET}..."
  # Handle versioned bucket: must delete all versions and delete markers
  aws s3api list-object-versions --bucket ${BUCKET} \
    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
    --output json > /tmp/mod13_versions.json 2>/dev/null || true
  VERSIONS=$(cat /tmp/mod13_versions.json | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('Objects') or []))" 2>/dev/null || echo "0")
  if [ "$VERSIONS" -gt "0" ]; then
    aws s3api delete-objects --bucket ${BUCKET} \
      --delete file:///tmp/mod13_versions.json 2>/dev/null || true
  fi

  aws s3api list-object-versions --bucket ${BUCKET} \
    --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
    --output json > /tmp/mod13_markers.json 2>/dev/null || true
  MARKERS=$(cat /tmp/mod13_markers.json | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('Objects') or []))" 2>/dev/null || echo "0")
  if [ "$MARKERS" -gt "0" ]; then
    aws s3api delete-objects --bucket ${BUCKET} \
      --delete file:///tmp/mod13_markers.json 2>/dev/null || true
  fi

  # Empty anything remaining
  aws s3 rm s3://${BUCKET} --recursive 2>/dev/null || true
fi

# Delete stack
aws cloudformation delete-stack --stack-name ${STACK_NAME}
aws cloudformation wait stack-delete-complete --stack-name ${STACK_NAME}

echo "[DONE] Cleanup complete!"
