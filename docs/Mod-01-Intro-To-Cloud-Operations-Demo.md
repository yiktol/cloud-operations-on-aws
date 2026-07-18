# Module 01 Demo: Introduction to Cloud Operations — "Review Your Workload with the Well-Architected Tool"

## Prerequisites
- AWS CLI configured with admin credentials
- Permission to use AWS Well-Architected Tool (`wellarchitected:*`)
- The Well-Architected Tool is free and available in most regions

---

## Demo Concept

Module 01 is conceptual — it introduces cloud operations and the **AWS Well-Architected Framework** (six pillars + general design principles). The best hands-on demonstration is the **AWS Well-Architected Tool**, which lets students *see* the framework in action: define a workload, answer pillar questions, and get a risk report with improvement recommendations.

This makes the abstract "six pillars" concrete and shows how operations teams actually apply the framework.

---

## Part 1: Setup (do before class)

The `deploy.sh` script creates a sample Well-Architected workload review so you have something to show immediately. You can also build it live in Act 1.

```bash
bash Mod-01/deploy.sh
```

---

## Part 2: Live Demo (in class)

### 🎬 Act 1: Define a Workload

> **Say:** "The Well-Architected Framework isn't just theory — AWS gives us a free tool to measure any workload against the six pillars. Let's define our production online store as a workload."

```bash
# Create a workload
WORKLOAD_ID=$(aws wellarchitected create-workload \
  --workload-name "Online-Store-Production" \
  --description "Production e-commerce platform — web tier, API, database, and CDN" \
  --environment PRODUCTION \
  --review-owner "CloudOps Team" \
  --lenses "wellarchitected" \
  --aws-regions "ap-southeast-1" \
  --query WorkloadId --output text)

echo "Workload created: ${WORKLOAD_ID}"

# Show the workload
aws wellarchitected get-workload --workload-id ${WORKLOAD_ID} \
  --query 'Workload.{Name:WorkloadName,Environment:Environment,Lenses:Lenses}' \
  --output table
```

> **Talking points:**
> - "A 'workload' is the application plus all its resources — exactly what we operate."
> - "The 'wellarchitected' lens is the standard six-pillar framework."
> - "You can add specialized lenses too — serverless, SaaS, financial services."

---

### 🎬 Act 2: Review the Pillars

> **Say:** "Now the tool walks us through questions for each of the six pillars. Let's look at the Operational Excellence pillar — the one we spend the most time on in this course."

```bash
# List all pillars and their questions
aws wellarchitected list-answers \
  --workload-id ${WORKLOAD_ID} \
  --lens-alias wellarchitected \
  --pillar-id operationalExcellence \
  --query 'AnswerSummaries[*].{Question:QuestionTitle,Risk:Risk}' \
  --output table

# Show the six pillars covered
echo "
The Six Pillars being evaluated:
  1. operationalExcellence  - Run and monitor systems
  2. security               - Protect information and assets
  3. reliability            - Recover from disruptions
  4. performance            - Use resources efficiently
  5. costOptimization       - Deliver value at lowest price
  6. sustainability         - Minimize environmental impact
"

# Answer a question (simulate a review decision)
QUESTION_ID=$(aws wellarchitected list-answers \
  --workload-id ${WORKLOAD_ID} \
  --lens-alias wellarchitected \
  --pillar-id operationalExcellence \
  --query 'AnswerSummaries[0].QuestionId' --output text)

# View the choices for this question
aws wellarchitected get-answer \
  --workload-id ${WORKLOAD_ID} \
  --lens-alias wellarchitected \
  --question-id ${QUESTION_ID} \
  --query 'Answer.{Question:QuestionTitle,Choices:Choices[*].{Id:ChoiceId,Title:Title}}' \
  --output json
```

> **Talking points:**
> - "Each pillar has a set of questions based on AWS best practices from thousands of customer reviews."
> - "You answer based on what your workload actually does — 'How do you monitor your workload?'"
> - "Unanswered or poorly-answered questions become identified risks."

---

### 🎬 Act 3: Generate the Risk Report

> **Say:** "After answering the questions, the tool produces a risk report — a prioritized list of what to improve. This is how the framework turns into an action plan."

```bash
# Get the risk summary across all pillars
aws wellarchitected get-workload --workload-id ${WORKLOAD_ID} \
  --query 'Workload.RiskCounts' --output table

# Create a milestone (snapshot in time to track improvement)
aws wellarchitected create-milestone \
  --workload-id ${WORKLOAD_ID} \
  --milestone-name "Initial-Review-$(date +%Y%m%d)"

# List improvement recommendations
aws wellarchitected list-answers \
  --workload-id ${WORKLOAD_ID} \
  --lens-alias wellarchitected \
  --pillar-id operationalExcellence \
  --query 'AnswerSummaries[?Risk==`HIGH` || Risk==`MEDIUM`].{Question:QuestionTitle,Risk:Risk}' \
  --output table
```

> **Talking points:**
> - "HIGH risks are addressed first — these are the biggest gaps in best practices."
> - "Milestones let you snapshot today, improve, then re-review to measure progress."
> - "This is 'evolve' from the operational excellence pillar — continuous improvement backed by data."

---

### 🎬 Bonus: Show the Console

Open the **AWS Well-Architected Tool** console and show:
1. The workload dashboard with the six-pillar risk overview
2. The question flow for a pillar (checkboxes for best practices)
3. The generated improvement plan with links to AWS documentation

> **Talking point:** "In the real world, teams run a Well-Architected Review quarterly. It's the practical embodiment of everything in this module."

---

## Part 3: Cleanup

```bash
bash Mod-01/cleanup.sh
```

---

## Summary Table

| Concept (from slides) | Tool feature | How it maps |
|----------------------|-------------|-------------|
| **Six Pillars** | Lens questions | Each pillar = a question set |
| **General design principles** | Best-practice choices | "Stop guessing capacity", "automate", etc. |
| **Operational Excellence** | OpEx pillar review | Organize, prepare, operate, evolve |
| **Data-driven decisions** | Risk report + milestones | Measure, improve, re-measure |

---

## Timing Guide

| Section | Duration |
|---------|----------|
| Act 1 (Define workload) | 3 min |
| Act 2 (Review pillars) | 5 min |
| Act 3 (Risk report) | 4 min |
| Bonus (Console) | 3 min |
| **Total** | **~15 min** |

---

## Instructor Notes
- The Well-Architected Tool is **free** — no resource costs, safe to demo in any account.
- The workload review persists — you can build it once and reuse across classes, or rebuild live.
- If short on time, skip Act 1 (use the pre-deployed workload) and focus on Acts 2–3.
- Great tie-in: mention that later modules (monitoring, security, scaling, cost) each map to a specific pillar.
