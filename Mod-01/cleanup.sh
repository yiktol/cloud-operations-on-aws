#!/bin/bash
# Module 01 - Cleanup
set -e

echo "[CLEANUP] Module 01 Demo..."

WORKLOAD_NAME="Online-Store-Production"

# Find and delete the workload
WORKLOAD_IDS=$(aws wellarchitected list-workloads \
  --query "WorkloadSummaries[?WorkloadName=='${WORKLOAD_NAME}'].WorkloadId" \
  --output text 2>/dev/null || true)

if [ -z "$WORKLOAD_IDS" ] || [ "$WORKLOAD_IDS" = "None" ]; then
  echo "[SKIP] No workload found to delete."
else
  for WID in ${WORKLOAD_IDS}; do
    aws wellarchitected delete-workload --workload-id "${WID}"
    echo "[DELETED] Workload: ${WID}"
  done
fi

echo "[DONE] Cleanup complete!"
