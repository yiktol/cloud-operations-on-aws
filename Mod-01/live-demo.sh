#!/bin/bash
# Module 01 - Live Demo: "Review Your Workload with the Well-Architected Tool"
# Interactive - uses read prompts between acts

REGION=$(aws configure get region)

echo "============================================"
echo "  ACT 1: DEFINE A WORKLOAD"
echo "============================================"
echo ""
echo ">> Creating the Example Corp. Customer Portal workload..."
read -p "Press Enter..."

WORKLOAD_ID=$(aws wellarchitected create-workload \
  --workload-name "ExampleCorp-CustomerPortal-Live" \
  --description "Customer-facing portal migrating to AWS" \
  --environment PRODUCTION \
  --reviewer-name "CloudOps Team" \
  --lenses "wellarchitected" \
  --aws-regions "${REGION}" \
  --query WorkloadId --output text)

echo "Workload created: ${WORKLOAD_ID}"
aws wellarchitected get-workload --workload-id ${WORKLOAD_ID} \
  --query 'Workload.{Name:WorkloadName,Environment:Environment,Lenses:Lenses}' \
  --output table
echo ""
echo ">> A workload = the application plus all its resources."
echo ""

echo "============================================"
echo "  ACT 2: REVIEW THE PILLARS"
echo "============================================"
read -p "Press Enter to view Operational Excellence questions..."

aws wellarchitected list-answers \
  --workload-id ${WORKLOAD_ID} \
  --lens-alias wellarchitected \
  --pillar-id operationalExcellence \
  --query 'AnswerSummaries[*].{Question:QuestionTitle,Risk:Risk}' \
  --output table

echo ""
echo "The Six Pillars:"
echo "  1. operationalExcellence   2. security       3. reliability"
echo "  4. performance             5. costOptimization  6. sustainability"
echo ""

QUESTION_ID=$(aws wellarchitected list-answers \
  --workload-id ${WORKLOAD_ID} \
  --lens-alias wellarchitected \
  --pillar-id operationalExcellence \
  --query 'AnswerSummaries[0].QuestionId' --output text)

echo ">> Choices for the first question:"
aws wellarchitected get-answer \
  --workload-id ${WORKLOAD_ID} \
  --lens-alias wellarchitected \
  --question-id ${QUESTION_ID} \
  --query 'Answer.{Question:QuestionTitle,Choices:Choices[*].Title}' \
  --output json
echo ""

echo "============================================"
echo "  ACT 3: RISK REPORT"
echo "============================================"
read -p "Press Enter to see the risk summary..."

echo ">> Risk counts across all pillars:"
aws wellarchitected get-workload --workload-id ${WORKLOAD_ID} \
  --query 'Workload.RiskCounts' --output table

echo ""
echo ">> Creating a milestone (snapshot to track improvement)..."
aws wellarchitected create-milestone \
  --workload-id ${WORKLOAD_ID} \
  --milestone-name "Initial-Review-$(date +%Y%m%d)" 2>/dev/null || echo "(Milestone needs at least one answered question)"

echo ""
echo ">> Medium/High risks in Operational Excellence:"
aws wellarchitected list-answers \
  --workload-id ${WORKLOAD_ID} \
  --lens-alias wellarchitected \
  --pillar-id operationalExcellence \
  --query 'AnswerSummaries[?Risk==`HIGH` || Risk==`MEDIUM`].{Question:QuestionTitle,Risk:Risk}' \
  --output table

echo ""
echo ">> RESULT: The framework becomes a prioritized action plan!"
echo ""
echo "Cleanup this live workload with:"
echo "  aws wellarchitected delete-workload --workload-id ${WORKLOAD_ID}"
echo ""
echo "============ DEMO COMPLETE ============"
