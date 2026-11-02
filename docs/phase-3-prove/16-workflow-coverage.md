# Talentra: Schema Coverage against Business Workflow (Step 16)

**Phase:** 3 Prove | **Step:** 16 Schema Coverage against Business Workflow
**Generated** by `scripts/lifecycle/gen_workflow_coverage.py`. Do not hand-edit; workflows live in [`05-workflows.md`](../phase-1-discover/05-workflows.md).

For every workflow step: can the data be **stored** (a table, function or view the step cites exists), and is the workflow **audited** (its text says it writes `audit.audit_event`)? Retrieval is exercised by the query set (step 28) and is not assessed here.

## Workflow summary

| Workflow | Steps | Steps backed by a database object or verified artefact | Steps owned elsewhere | Objects cited | Objects that do not exist | Sensitive action classes evidenced (docket B79) |
|:--|--:|--:|--:|--:|--:|:--|
| WF-01 User registration and authentication | 7 | 7 | 0 | 10 | 0 | classes 1, 2, 5 |
| WF-02 Candidate profile creation and completion | 8 | 8 | 0 | 17 | 0 | none: profile edits are not a sensitive class; document access is recorded in profile.candidate_activity_log |
| WF-03 Job posting creation and publication | 6 | 6 | 0 | 14 | 0 | none: publishing a job is not a sensitive class; the status change is kept in the row history |
| WF-04 Candidate discovery and job application | 7 | 7 | 0 | 11 | 0 | none: creating an application is not a sensitive class; its stage history is class 12 under WF-05 |
| WF-05 Recruitment pipeline management | 5 | 4 | 1 | 2 | 0 | classes 12 |
| WF-06 Agency consultant sourcing | 5 | 5 | 0 | 7 | 0 | none: consultant requests are business records with their own status history, not a sensitive class |
| WF-07 Gig marketplace engagement | 6 | 6 | 0 | 10 | 0 | none: gig requests and assignments are business records, not a sensitive class |
| WF-08 Organisation and member administration | 7 | 7 | 0 | 9 | 0 | classes 6, 7 |
| WF-09 Licensing, subscription and entitlements | 8 | 8 | 0 | 9 | 0 | classes 14 |
| WF-10 Session management and revocation | 5 | 5 | 0 | 6 | 0 | classes 3, 4 |
| WF-11 Notification, consent and privacy management | 8 | 7 | 1 | 11 | 0 | classes 9, 10 |
| WF-12 Platform operations, validation and backup | 7 | 7 | 0 | 1 | 0 | none: operations; the restore check is recorded in audit.maintenance_run |
| WF-13 Analytical mart refresh | 4 | 4 | 0 | 9 | 0 | none: operations; each run is recorded in audit.maintenance_run |
| WF-14 Profile download and credit consumption | 6 | 5 | 1 | 8 | 0 | classes 11, 13 |
| WF-15 Integration exchange with an external system | 7 | 6 | 1 | 9 | 0 | none: failures are written to audit.system_error_log; the exchange itself is not a sensitive class |
| WF-16 Scheduled maintenance, retention and erasure | 5 | 5 | 0 | 11 | 0 | classes 7 |
| WF-17 Administrative support and impersonation | 6 | 6 | 0 | 8 | 0 | classes 8 |
| WF-18 Candidate development: courses, assessments and resume templates | 5 | 5 | 0 | 6 | 0 | none: learning records are not a sensitive class |
| WF-19 Recruiter search, bookmarks and profile views | 6 | 6 | 0 | 5 | 0 | classes 11 |
| WF-20 Community, support and referrals | 5 | 4 | 1 | 5 | 0 | none: community content is not a sensitive class |
| WF-21 Reference data and rule maintenance | 6 | 6 | 0 | 15 | 0 | none: changes arrive as reviewed migrations |
| **total** | **129** | **124** | **5** | | | |

## Steps that cite no table, and how each is accounted for

Every step that names no table, function or view is either backed by another verified artefact (a governed state machine, a query file, a script, a column, another workflow) or is owned outside the database by a named role. `docs/phase-3-prove/16-gap-owners.json` holds the disposition; this generator verifies each reference and fails when a step has none.

| Workflow | Step | Disposition | Reference or owner | Text |
|:--|--:|:--|:--|:--|
| WF-01 | 4 | state_machine | core.user_account | on activation set `account_status = 'active'` |
| WF-03 | 5 | state_machine | recruitment.job_posting | transition `job_status` to `published` and set `published_at` |
| WF-04 | 1 | query | db/queries/01_candidate_multicriteria_search.sql | Recruiter path: execute `db/queries/01_candidate_multicriteria_search.sql` — filter on `profile_status = 'active'`, `vis |
| WF-04 | 3 | workflow_ref | WF-14 | optionally download an unlocked profile → WF-14, which deducts credit |
| WF-04 | 4 | query | db/queries/02_job_feed_matching.sql | candidate path: execute `db/queries/02_job_feed_matching.sql` for the job feed |
| WF-04 | 7 | column_default | recruitment.candidate_application.application_status | the application starts at `application_status = 'applied'` |
| WF-05 | 3 | column | recruitment.application_status_history.change_reason | record the decision reason |
| WF-05 | 4 | application | Application: headcount counter on the job; the schema stores positions but no code increments a filled count | on reaching `joined`, update the headcount counter **[app-layer]** |
| WF-05 | 5 | query | db/queries/03_recruiter_pipeline_funnel.sql | view the funnel via `db/queries/03_recruiter_pipeline_funnel.sql` |
| WF-06 | 2 | state_machine | sourcing.consultant_sourcing_request | the employer accepts or declines → status becomes `accepted` or `declined`, and `decided_at` is set |
| WF-06 | 4 | state_machine | sourcing.sourcing_submission | the submission advances `submitted` → `shortlisted` → `accepted` → `hired` (or `rejected`) |
| WF-07 | 3 | state_machine | gig.gig_application | client accepts or rejects → status becomes `accepted` or `rejected` and `decided_at` is set |
| WF-07 | 5 | state_machine | gig.gig_assignment | on completion → `assignment_status = 'completed'` |
| WF-08 | 7 | workflow_ref | WF-09 | allocate licence seats → WF-09 |
| WF-09 | 5 | state_machine | commercial.payment_order | the gateway confirms → status becomes `authorized` then `captured` |
| WF-10 | 3 | function | core.revoke_user_session | the function sets `revoked_at` and `ended_at` |
| WF-11 | 5 | application | Application: the sender; the status column is a recorded exemption because provider callbacks arrive out of order | dispatch to the provider and update the status to `sent` → `delivered` → `read`, recording `external_provider_message_id |
| WF-12 | 1 | file | docker-compose.yml | Build the environment: `docker-compose up -d` → a single PostgreSQL 17 service with a volume |
| WF-12 | 2 | file | db/migrations | apply every migration in `db/migrations/` in order (`psql -v ON_ERROR_STOP=1`) |
| WF-12 | 3 | file | scripts/generate_data.py | seed reference data (migration 004) and generate test data (`scripts/generate_data.py`) |
| WF-12 | 4 | file | scripts/run_all_tests.py | run the test suite (`scripts/run_all_tests.py` → every suite in `tests/`, SQL and Python) |
| WF-12 | 5 | file | scripts/validate_data.py | run the data-quality validator (`scripts/validate_data.py` → 15 checks across RG1–RG10) |
| WF-12 | 6 | file | scripts/run_benchmarks.py | run the benchmark harness (`scripts/run_benchmarks.py` → 12 queries with p50/p95/p99) |
| WF-12 | 7 | file | scripts/backup_restore.sh | run the backup/restore runbook (`scripts/backup_restore.sh` → `pg_dump` → restore into a scratch database → exact row co |
| WF-13 | 3 | query | db/queries/10_analytics_time_to_hire_kpi.sql | verify the refreshed output via `db/queries/10` and `11` |
| WF-13 | 4 | view | audit.ops_job_freshness | confirm freshness |
| WF-14 | 2 | function | commercial.download_candidate_profile | a repeat download by the same organisation is recorded at zero cost and the function returns |
| WF-14 | 6 | application | Application: serving the document bytes from storage | the application delivers the document **[app-layer]** |
| WF-15 | 3 | application | Application: the call to the external system; the outbox around it is in the database | the worker calls the external system **[app-layer]** |
| WF-17 | 4 | function | audit.log_change | every audited change made meanwhile carries the impersonator's id |
| WF-17 | 6 | state_machine | messaging.support_ticket | the administrator updates the ticket |
| WF-18 | 4 | workflow_ref | WF-02 | uploads the resulting document → WF-02 |
| WF-19 | 5 | workflow_ref | WF-14 | a full download → WF-14 |
| WF-20 | 5 | application | Application: paying out the reward | when the invitee registers the event is completed and the reward is recorded **[reward payout is app-layer]** |

## Gaps

None.

## Tables no workflow touches

6 of 113 base tables are cited by no workflow. Either a workflow is missing or the table is unused.

| Schema | Tables |
|:--|:--|
| `core` | `identity_verification` |
| `recruitment` | `company_review_summary` |
| `messaging` | `external_reference`, `legacy_field_mapping`, `share_event`, `sync_conflict` |

## Gate G3 condition: workflow coverage

- Workflows whose every cited table exists: **21 / 21**.
- Main-flow steps backed by a database object: **124 / 129**.
- Tables reached by at least one workflow: **107 / 113**.
- Steps owned outside the database (Application or Operations): **5**, each with a named owner (roles assigned by the assistant, DEC-30).
- Steps with neither a backing artefact nor an owner: **0**. The playbook's test (100% or a logged gap with an owner) is met.
