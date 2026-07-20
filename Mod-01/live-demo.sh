#!/bin/bash
# Module 01 - Live Demo: Review Your Workload with the Well-Architected Tool

REGION=$(aws configure get region)

# --- ACT 1: Define a Workload ---
# Create the Example Corp Customer Portal workload
WORKLOAD_ID=$(aws wellarchitected create-workload \
  --workload-name "ExampleCorp-CustomerPortal-Live" \
  --description "Customer-facing portal migrating to AWS" \
  --environment PRODUCTION \
  --reviewer-name "CloudOps Team" \
  --lenses "wellarchitected" \
  --aws-regions "${REGION}" \
  --query WorkloadId --output text)

# Show workload details
aws wellarchitected get-workload --workload-id ${WORKLOAD_ID} \
  --query 'Workload.{Name:WorkloadName,Environment:Environment,Lenses:Lenses}' \
  --output table

# --- ACT 2: Review the Pillars ---
# List Operational Excellence questions and risk levels
aws wellarchitected list-answers \
  --workload-id ${WORKLOAD_ID} \
  --lens-alias wellarchitected \
  --pillar-id operationalExcellence \
  --query 'AnswerSummaries[*].{Question:QuestionTitle,Risk:Risk}' \
  --output table

# Get the first question ID
QUESTION_ID=$(aws wellarchitected list-answers \
  --workload-id ${WORKLOAD_ID} \
  --lens-alias wellarchitected \
  --pillar-id operationalExcellence \
  --query 'AnswerSummaries[0].QuestionId' --output text)

# Show choices for the first question
aws wellarchitected get-answer \
  --workload-id ${WORKLOAD_ID} \
  --lens-alias wellarchitected \
  --question-id ${QUESTION_ID} \
  --query 'Answer.{Question:QuestionTitle,Choices:Choices[*].Title}' \
  --output json

# --- ACT 3: Risk Report ---
# Show risk counts across all pillars
aws wellarchitected get-workload --workload-id ${WORKLOAD_ID} \
  --query 'Workload.RiskCounts' --output table

# Create a milestone to track improvement over time
aws wellarchitected create-milestone \
  --workload-id ${WORKLOAD_ID} \
  --milestone-name "Initial-Review-$(date +%Y%m%d)" 2>/dev/null || true

# Show medium/high risks in Operational Excellence
aws wellarchitected list-answers \
  --workload-id ${WORKLOAD_ID} \
  --lens-alias wellarchitected \
  --pillar-id operationalExcellence \
  --query 'AnswerSummaries[?Risk==`HIGH` || Risk==`MEDIUM`].{Question:QuestionTitle,Risk:Risk}' \
  --output table

# Cleanup
# aws wellarchitected delete-workload --workload-id ${WORKLOAD_ID}
