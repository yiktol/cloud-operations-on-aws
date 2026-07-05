#!/bin/bash
# Module 01 - Cleanup
set -e
STACK_NAME="mod01-cloud-operations-demo"

echo "[CLEANUP] Module 01 Demo..."

# If a workload was created LIVE (not via CFN), clean it up too
LIVE_WORKLOAD=$(aws wellarchitected list-workloads \
  --query 'WorkloadSummaries[?WorkloadName==`ExampleCorp-CustomerPortal`].WorkloadId' \
  --output text 2>/dev/null)

# Delete the stack (removes the CFN-managed workload)
aws cloudformation delete-stack --stack-name ${STACK_NAME}
aws cloudformation wait stack-delete-complete --stack-name ${STACK_NAME} 2>/dev/null || true

# Clean up any duplicate live-created workload not managed by CFN
for WID in ${LIVE_WORKLOAD}; do
  aws wellarchitected delete-workload --workload-id ${WID} 2>/dev/null || true
done

echo "[DONE] Cleanup complete!"
