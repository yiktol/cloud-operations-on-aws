#!/bin/bash
# Module 01 - Deploy Setup (Well-Architected workload with pre-filled OpEx answers)
set -e

echo "[DEPLOY] Module 01 Demo — Creating Well-Architected workload..."

REGION="${AWS_DEFAULT_REGION:-ap-southeast-1}"
LENS="wellarchitected"
WORKLOAD_NAME="Online-Store-Production"

# Check if a workload with this name already exists
EXISTING=$(aws wellarchitected list-workloads \
  --query "WorkloadSummaries[?WorkloadName=='${WORKLOAD_NAME}'].WorkloadId" \
  --output text 2>/dev/null || true)

if [ -n "$EXISTING" ] && [ "$EXISTING" != "None" ]; then
  echo "[SKIP] Workload already exists: ${EXISTING}"
  WORKLOAD_ID="$EXISTING"
else
  WORKLOAD_ID=$(aws wellarchitected create-workload \
    --workload-name "${WORKLOAD_NAME}" \
    --description "Production e-commerce platform — web tier, API, database, and CDN" \
    --environment PRODUCTION \
    --review-owner "CloudOps Team" \
    --lenses "$LENS" \
    --aws-regions "${REGION}" \
    --query "WorkloadId" --output text)
  echo "[CREATED] Workload: ${WORKLOAD_ID}"
fi

echo ""
echo "[ANSWERS] Pre-filling Operational Excellence pillar answers..."

# ─── OPS01: How do you determine what your priorities are? ───────────────────
aws wellarchitected update-answer \
  --workload-id "$WORKLOAD_ID" \
  --lens-alias "$LENS" \
  --question-id "priorities" \
  --selected-choices \
    "ops_priorities_ext_cust_needs" \
    "ops_priorities_int_cust_needs" \
    "ops_priorities_compliance_reqs" \
    "ops_priorities_eval_tradeoffs" \
  --notes "• [SELECTED] Evaluate external customer needs — Monthly NPS surveys and support ticket analysis feed into quarterly roadmap prioritization.
• [SELECTED] Evaluate internal customer needs — Platform team runs bi-weekly intake meetings with product squads to capture internal tooling requirements.
• [NOT SELECTED] Evaluate governance requirements — No formal governance framework established yet; operating under ad-hoc approval processes.
• [SELECTED] Evaluate compliance requirements — PCI-DSS compliance register maintained in Confluence; quarterly audits with external assessor.
• [NOT SELECTED] Evaluate threat landscape — Security team exists but no structured threat modeling process for operational priorities; relying on reactive patching.
• [SELECTED] Evaluate tradeoffs while managing benefits and risks — Architecture Decision Records (ADRs) required for any change affecting availability or cost >5%." \
  --output text --query 'Answer.QuestionId' > /dev/null
echo "  ✓ OPS01 - priorities"

# ─── OPS02: How do you structure your organization to support your business outcomes?
aws wellarchitected update-answer \
  --workload-id "$WORKLOAD_ID" \
  --lens-alias "$LENS" \
  --question-id "ops-model" \
  --selected-choices \
    "ops_ops_model_def_resource_owners" \
    "ops_ops_model_def_proc_owners" \
    "ops_ops_model_def_activity_owners" \
    "ops_ops_model_def_responsibilities_ownership" \
  --notes "• [SELECTED] Resources have identified owners — Every AWS resource tagged with 'Owner' pointing to the responsible team in PagerDuty.
• [SELECTED] Processes and procedures have identified owners — Runbooks and SOPs have named owners; reviewed quarterly for accuracy.
• [SELECTED] Operations activities have identified owners — On-call rotation covers all production services; escalation matrix published in wiki.
• [SELECTED] Mechanisms exist to manage responsibilities and ownership — RACI matrix in Confluence updated each sprint; ownership transfers require formal handoff.
• [NOT SELECTED] Mechanisms exist to request additions, changes, and exceptions — No formal change request process beyond Jira tickets; exceptions handled ad-hoc in Slack.
• [NOT SELECTED] Responsibilities between teams are predefined or negotiated — Cross-team boundaries are informal; leads to occasional gaps during incidents spanning multiple services." \
  --output text --query 'Answer.QuestionId' > /dev/null
echo "  ✓ OPS02 - ops-model"

# ─── OPS03: How does your organizational culture support your business outcomes?
aws wellarchitected update-answer \
  --workload-id "$WORKLOAD_ID" \
  --lens-alias "$LENS" \
  --question-id "org-culture" \
  --selected-choices \
    "ops_org_culture_executive_sponsor" \
    "ops_org_culture_team_enc_escalation" \
    "ops_org_culture_team_emp_take_action" \
    "ops_org_culture_team_enc_experiment" \
    "ops_org_culture_team_enc_learn" \
  --notes "• [SELECTED] Provide executive sponsorship — CTO sponsors cloud-first strategy; monthly ops review with VP Engineering.
• [SELECTED] Escalation is encouraged — Blameless culture; on-call engineers praised for early escalation; no penalties for false alarms.
• [NOT SELECTED] Communications are timely, clear, and actionable — Incident comms are inconsistent; no standardized status page or template for stakeholder updates during outages.
• [SELECTED] Team members are empowered to take action when outcomes are at risk — Engineers authorized to scale resources and roll back deployments without manager approval.
• [SELECTED] Experimentation is encouraged — Quarterly hack days; teams can propose experiments with defined blast radius and success criteria.
• [SELECTED] Team members are encouraged to maintain and grow their skill sets — Annual AWS certification budget per engineer; dedicated learning Fridays twice a month.
• [NOT SELECTED] Resource teams appropriately — Teams are slightly understaffed for current service count; hiring pipeline active but 2 roles unfilled for 3+ months." \
  --output text --query 'Answer.QuestionId' > /dev/null
echo "  ✓ OPS03 - org-culture"

# ─── OPS04: How do you implement observability in your workload? ─────────────
aws wellarchitected update-answer \
  --workload-id "$WORKLOAD_ID" \
  --lens-alias "$LENS" \
  --question-id "observability" \
  --selected-choices \
    "ops_observability_identify_kpis" \
    "ops_observability_application_telemetry" \
    "ops_observability_dependency_telemetry" \
  --notes "• [SELECTED] Identify key performance indicators — KPIs defined: p99 latency <200ms, error rate <0.1%, availability 99.95%, order success rate >99.5%.
• [SELECTED] Implement application telemetry — CloudWatch embedded metrics format used; custom metrics for business events (orders, cart abandonment).
• [NOT SELECTED] Implement user experience telemetry — No Real User Monitoring (RUM) in place; frontend team plans to add CloudWatch RUM next quarter.
• [SELECTED] Implement dependency telemetry — Health checks on RDS, ElastiCache, and third-party payment gateway; alerts on connection pool exhaustion.
• [NOT SELECTED] Implement distributed tracing — X-Ray SDK not yet instrumented across microservices; correlation IDs exist in logs but no visual trace map. Planned for Q4." \
  --output text --query 'Answer.QuestionId' > /dev/null
echo "  ✓ OPS04 - observability"

# ─── OPS05: How do you reduce defects, ease remediation, and improve flow? ───
aws wellarchitected update-answer \
  --workload-id "$WORKLOAD_ID" \
  --lens-alias "$LENS" \
  --question-id "dev-integ" \
  --selected-choices \
    "ops_dev_integ_version_control" \
    "ops_dev_integ_test_val_chg" \
    "ops_dev_integ_build_mgmt_sys" \
    "ops_dev_integ_multi_env" \
    "ops_dev_integ_freq_sm_rev_chg" \
  --notes "• [SELECTED] Use version control — All code in CodeCommit with branch protection; infrastructure as code in separate repo.
• [SELECTED] Test and validate changes — CI pipeline runs unit tests (>80% coverage), integration tests, and SAST scanning on every PR.
• [NOT SELECTED] Use configuration management systems — Application config stored in Parameter Store but no formal config-as-code drift detection.
• [SELECTED] Use build and deployment management systems — CodePipeline orchestrates build/test/deploy; artifacts stored in ECR and S3.
• [NOT SELECTED] Perform patch management — OS patching is manual and inconsistent; no Systems Manager Patch Manager baseline configured yet.
• [NOT SELECTED] Share design standards — Architecture guidelines exist in wiki but no automated enforcement or linting for CloudFormation/CDK templates.
• [NOT SELECTED] Implement practices to improve code quality — No static analysis beyond basic linting; no code quality gates in pipeline.
• [SELECTED] Use multiple environments — Three environments: dev (on-demand), staging (mirrors prod topology), production.
• [SELECTED] Make frequent, small, reversible changes — PRs limited to <400 lines; feature flags for gradual rollout of major changes.
• [NOT SELECTED] Fully automate integration and deployment — Staging deploys are automated but production requires manual approval click; goal is full GitOps." \
  --output text --query 'Answer.QuestionId' > /dev/null
echo "  ✓ OPS05 - dev-integ"

# ─── OPS06: How do you mitigate deployment risks? ────────────────────────────
aws wellarchitected update-answer \
  --workload-id "$WORKLOAD_ID" \
  --lens-alias "$LENS" \
  --question-id "mit-deploy-risks" \
  --selected-choices \
    "ops_mit_deploy_risks_plan_for_unsucessful_changes" \
    "ops_mit_deploy_risks_test_val_chg" \
    "ops_mit_deploy_risks_deploy_mgmt_sys" \
  --notes "• [SELECTED] Plan for unsuccessful changes — Every deployment checklist includes rollback steps; database migrations are backward-compatible by policy.
• [SELECTED] Test deployments — Staging environment receives identical deployment before production; smoke tests validate critical paths post-deploy.
• [SELECTED] Employ safe deployment strategies — CodeDeploy rolling (OneAtATime) for EC2 fleet; blue/green for ECS services.
• [NOT SELECTED] Automate testing and rollback — CloudWatch alarm-triggered automatic rollback not yet configured; rollbacks are manual but fast (~3 min). HIGH risk item — next sprint priority." \
  --output text --query 'Answer.QuestionId' > /dev/null
echo "  ✓ OPS06 - mit-deploy-risks"

# ─── OPS07: How do you know that you are ready to support a workload? ────────
aws wellarchitected update-answer \
  --workload-id "$WORKLOAD_ID" \
  --lens-alias "$LENS" \
  --question-id "ready-to-support" \
  --selected-choices \
    "ops_ready_to_support_personnel_capability" \
    "ops_ready_to_support_use_runbooks" \
    "ops_ready_to_support_use_playbooks" \
  --notes "• [SELECTED] Ensure personnel capability — All on-call engineers AWS certified (SysOps or DevOps Pro); quarterly game days simulate real failures.
• [NOT SELECTED] Ensure a consistent review of operational readiness — No formal ORR checklist before launching new features; readiness is assessed informally by tech leads.
• [SELECTED] Use runbooks to perform procedures — 12 runbooks cover common operations (failover, scaling, cache flush, certificate rotation, etc.).
• [SELECTED] Use playbooks to investigate issues — Investigation playbooks for high-latency, 5xx spikes, and data inconsistency scenarios.
• [NOT SELECTED] Make informed decisions to deploy systems and changes — Deployment go/no-go is based on gut feel rather than quantitative readiness metrics.
• [NOT SELECTED] Create support plans for production workloads — Running on Developer Support; Business Support not yet approved by finance. Limits access to Trusted Advisor and faster response SLAs." \
  --output text --query 'Answer.QuestionId' > /dev/null
echo "  ✓ OPS07 - ready-to-support"

# ─── OPS08: How do you utilize workload observability in your organization? ──
aws wellarchitected update-answer \
  --workload-id "$WORKLOAD_ID" \
  --lens-alias "$LENS" \
  --question-id "workload-observability" \
  --selected-choices \
    "ops_workload_observability_create_alerts" \
    "ops_workload_observability_analyze_workload_metrics" \
    "ops_workload_observability_create_dashboards" \
  --notes "• [SELECTED] Create actionable alerts — Alarms configured for 5xx error rate >1%, p99 latency >500ms, CPU >80% sustained 5 min. Each alarm links to a runbook.
• [SELECTED] Analyze workload metrics — Weekly review of CloudWatch metrics; anomaly detection enabled on order volume to catch traffic drops.
• [NOT SELECTED] Analyze workload logs — Logs shipped to CloudWatch Logs but analysis is reactive; no scheduled log insight queries or pattern detection rules.
• [NOT SELECTED] Analyze workload traces — No X-Ray tracing instrumented; debugging cross-service latency relies on timestamp correlation in logs.
• [SELECTED] Create dashboards — Per-service CloudWatch dashboards showing golden signals; shared team dashboard on wall-mounted monitor in office." \
  --output text --query 'Answer.QuestionId' > /dev/null
echo "  ✓ OPS08 - workload-observability"

# ─── OPS09: How do you understand the health of your operations? ─────────────
aws wellarchitected update-answer \
  --workload-id "$WORKLOAD_ID" \
  --lens-alias "$LENS" \
  --question-id "operations-health" \
  --selected-choices \
    "ops_operations_health_measure_ops_goals_kpis" \
    "ops_operations_health_communicate_status_trends" \
  --notes "• [SELECTED] Measure operations goals and KPIs with metrics — Track MTTR, deployment frequency, change failure rate, and lead time for changes weekly.
• [SELECTED] Communicate status and trends to ensure visibility into operation — Weekly ops summary in Slack; monthly report to leadership with trend graphs.
• [NOT SELECTED] Review operations metrics and prioritize improvement — Improvement items are logged but lack a formal scoring/prioritization framework; backlog grows faster than items are addressed." \
  --output text --query 'Answer.QuestionId' > /dev/null
echo "  ✓ OPS09 - operations-health"

# ─── OPS10: How do you manage workload and operations events? ────────────────
aws wellarchitected update-answer \
  --workload-id "$WORKLOAD_ID" \
  --lens-alias "$LENS" \
  --question-id "event-response" \
  --selected-choices \
    "ops_event_response_event_incident_problem_process" \
    "ops_event_response_process_per_alert" \
    "ops_event_response_prioritize_events" \
    "ops_event_response_define_escalation_paths" \
  --notes "• [SELECTED] Use a process for event, incident, and problem management — Sev1-4 classification with defined response SLAs per severity level.
• [SELECTED] Have a process per alert — Every CloudWatch alarm has a linked runbook with first-response steps and expected resolution time.
• [SELECTED] Prioritize operational events based on business impact — Severity based on revenue impact: Sev1 = checkout down, Sev2 = degraded search, Sev3 = internal tooling.
• [SELECTED] Define escalation paths — On-call engineer (5 min ack) → team lead (15 min) → VP Engineering (30 min); auto-escalation via PagerDuty.
• [NOT SELECTED] Define a customer communication plan for service-impacting events — No public status page; customer comms during incidents are ad-hoc via support team email.
• [NOT SELECTED] Communicate status through dashboards — Internal dashboards exist but no real-time status page for customers or stakeholders outside engineering.
• [NOT SELECTED] Automate responses to events — Partial: Auto Scaling handles traffic spikes, but self-healing (restart failed tasks, failover) requires manual intervention." \
  --output text --query 'Answer.QuestionId' > /dev/null
echo "  ✓ OPS10 - event-response"

# ─── OPS11: How do you evolve operations? ────────────────────────────────────
aws wellarchitected update-answer \
  --workload-id "$WORKLOAD_ID" \
  --lens-alias "$LENS" \
  --question-id "evolve-ops" \
  --selected-choices \
    "ops_evolve_ops_process_cont_imp" \
    "ops_evolve_ops_perform_rca_process" \
    "ops_evolve_ops_feedback_loops" \
    "ops_evolve_ops_share_lessons_learned" \
    "ops_evolve_ops_allocate_time_for_imp" \
  --notes "• [SELECTED] Have a process for continuous improvement — Bi-weekly retrospectives produce ranked action items tracked in Jira improvement board.
• [SELECTED] Perform post-incident analysis — Blameless PIRs mandatory within 48h of Sev1/Sev2; findings stored in shared incident database.
• [SELECTED] Implement feedback loops — Deployment metrics (lead time, failure rate) reviewed weekly; customer support trends fed back to product team monthly.
• [NOT SELECTED] Perform knowledge management — Tribal knowledge still dominant; no structured onboarding knowledge base or decision log beyond scattered wiki pages.
• [NOT SELECTED] Define drivers for improvement — Improvements are reactive (triggered by incidents) rather than proactive (driven by trend analysis or benchmarks).
• [NOT SELECTED] Validate insights — No A/B testing or controlled experiments for operational changes; improvements assumed effective without measurement.
• [NOT SELECTED] Perform operations metrics reviews — DORA metrics tracked but not formally reviewed against targets or industry benchmarks.
• [SELECTED] Document and share lessons learned — PIR findings published in #incidents Slack channel and quarterly all-hands ops review.
• [SELECTED] Allocate time to make improvements — 20% of sprint capacity reserved for tech debt and operational improvements; protected from feature work." \
  --output text --query 'Answer.QuestionId' > /dev/null
echo "  ✓ OPS11 - evolve-ops"

echo ""
echo "[DONE] Setup complete!"
echo "   Workload ID: ${WORKLOAD_ID}"
echo "   Region:      ${REGION}"
echo "   Pillar:      Operational Excellence (11 questions answered with notes)"
echo "   Note: The Well-Architected Tool is free — no resource costs."
