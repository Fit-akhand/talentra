# Talentra: Business Rules Catalogue v2 (Step 18)

**Phase:** 3 Prove | **Step:** 18 Business Rules and Data Constraints v2
**Generated** by `scripts/lifecycle/gen_rules_catalogue.py`. Do not hand-edit; rule text lives in [`01-requirements.md`](../phase-1-discover/01-requirements.md).

Every rule has an ID, an owner (a role, DEC-30), an enforcement point and a named test. BR-001 to BR-027 come from the requirement register; BR-028 to BR-040 are docket and later rules that the register did not carry (`docs/phase-3-prove/18-rule-extensions.json`). Named objects are looked up in the live catalog, so a renamed or dropped constraint shows up here as a downgrade.

## Enforcement summary

| Enforcement point | Rules |
|:--|--:|
| database | 39 |
| database (inferred) | 0 |
| reconciled | 1 |
| query only | 0 |
| documentation only | 0 |
| **total** | **40** |

## Rules

| ID | Rule | Owner | Enforced in | Mechanism | Test files |
|:--|:--|:--|:--|:--|:--|
| BR-001 | Email addresses are unique across all user accounts and stored in lowercase | Platform | **database** | constraint CHECK `ck_user_account_email_lowercase`; constraint UNIQUE `uq_user_account_email` | test_identity.sql |
| BR-002 | A user may hold no more concurrent active sessions than the device entitlement of their active licence; a personal account defaults to 2 | Platform | **database** | function core.create_session_with_device_limit locks the user row and counts distinct active devices against the licence entitlement | test_concurrency.py, test_identity.sql, test_licences.sql |
| BR-003 | A revoked session is terminal and cannot be reused; revocation writes an audit event | Security | **database** | function core.revoke_user_session sets revoked_at and ended_at and writes the audit event | test_administration.sql, test_licences.sql |
| BR-004 | Consent state is recorded per subject and category and is queryable for disclosure decisions | Security | **database** | constraint CHECK `ck_user_block_not_self`; constraint CHECK `ck_user_block_target_xor`; constraint FOREIGN KEY `fk_user_block_blocked_organization`; constraint FOREIGN KEY `fk_user_block_blocked_user`; constraint FOREIGN KEY `fk_user_block_blocker`; constraint PRIMARY KEY `pk_user_block`; index `uq_user_block_organization`; index `uq_user_block_user` | test_administration.sql, test_audit_coverage.sql, test_candidate_privacy.sql |
| BR-005 | Master reference data is read-only after seeding and carries no outbound foreign keys | Platform | **database** | the application role holds no INSERT, UPDATE or DELETE on the master code tables; no master table has a foreign key outside master except the audit columns to core.user_account | test_br_decision_and_outreach.sql, test_master_data.sql, test_seed_master_data.sql |
| BR-006 | A candidate profile carries exactly one visibility state governing who may discover it | Product | **database** | CHECK ck_candidate_profile_visibility allows exactly private, recruiters or public; row-level security reads it through core.can_view_candidate | test_candidate_extensions.sql, test_candidate_profile.sql |
| BR-007 | Profile completeness is derived from the presence of headline, summary, skills, education, experience, resume and projects, and is bounded to 0–100% | Product | **database** | constraint CHECK `ck_candidate_profile_completion_percentage`; constraint FOREIGN KEY `fk_candidate_profile_completion_profile`; constraint PRIMARY KEY `pk_candidate_profile_completion`; constraint UNIQUE `uq_candidate_profile_completion_profile` | test_candidate_extensions.sql |
| BR-008 | A candidate may have at most one active primary resume; only a resume may be marked primary | Product | **database** | partial unique index uq_candidate_document_primary_resume allows one active primary resume per candidate | test_candidate_document.sql |
| BR-009 | A skill claim carries a proficiency level and optional per-skill experience in years | Product | **database** | CHECK constraints ck_candidate_skill_proficiency and ck_candidate_skill_experience; one claim per skill (uq_candidate_skill_profile_skill) | test_candidate_profile.sql |
| BR-010 | Candidate search honours profile visibility and the block rules in BR-021 | Security | **database** | function `core.is_candidate_visible_to` | test_access_control.sql |
| BR-011 | An organisation has one type, may have a hierarchy, and holds its own locations and legal identifiers | Product | **database** | CHECK ck_organization_type; identifiers in organization_identifier (unique per country and type); ck_organization_hierarchy_not_self forbids an organisation being its own parent | test_organization.sql, test_organization_extensions.sql |
| BR-012 | Salary fields are all-or-none: either all salary and currency and period fields are populated, or none are | Product | **database** | constraint CHECK `ck_job_posting_experience`; constraint CHECK `ck_job_posting_salary_currency` | test_job_posting.sql |
| BR-013 | A job carries at most one questionnaire; a filled position requires a candidate answer | Product | **database** | unique constraint uq_job_questionnaire_job allows one questionnaire per job | test_job_questionnaire.sql |
| BR-014 | A candidate may hold at most one application to a given job | Product | **database** | constraint UNIQUE `uq_candidate_application_candidate_job` | test_candidate_application.sql |
| BR-015 | An application stage is one of the seven permitted values | Product | **database** | constraint CHECK `ck_candidate_application_status` | test_candidate_application.sql |
| BR-016 | Every stage change is captured in `application_status_history` with previous and new values; a change to the same value is not recorded | Product | **database** | function `recruitment.record_application_status_change`; trigger `trg_candidate_application_status_history` | test_candidate_application.sql |
| BR-017 | Funnel and feed aggregations are derived from the authoritative application and job tables, not from denormalised copies | Data | **reconciled** | the marts are rebuilt from the authoritative tables (analytics.load_reporting_marts) and sixteen KPIs are reconciled to a hand-built dataset; a denormalised copy that drifted would fail that reconciliation | test_golden_kpis.py |
| BR-018 | A consultant sourcing request is unique per (job, consultant); a decision is recorded iff the request is accepted or declined | Product | **database** | constraint CHECK `ck_consultant_sourcing_req_decision_consistency`; constraint CHECK `ck_consultant_sourcing_req_status`; constraint FOREIGN KEY `fk_consultant_sourcing_req_consultant`; constraint FOREIGN KEY `fk_consultant_sourcing_req_decided_by`; constraint FOREIGN KEY `fk_consultant_sourcing_req_job`; constraint PRIMARY KEY `pk_consultant_sourcing_request`; constraint UNIQUE `uq_consultant_sourcing_request` | test_sourcing.sql |
| BR-019 | A consultant may act only on a job whose consultant policy is open | Product | **database** | function `sourcing.enforce_consultant_openness`; trigger `trg_enforce_consultant_openness` | test_business_rules.sql, test_sourcing.sql |
| BR-020 | A consultant may submit a given candidate to a given job only once | Product | **database** | constraint UNIQUE `uq_sourcing_submission_job_candidate` | test_sourcing.sql |
| BR-021 | Outreach recipients are filtered against candidate block state before dispatch | Security | **database** | trigger trg_outreach_recipient_block (migration 037) stores a blocked recipient as blocked and refuses delivery | test_br_decision_and_outreach.sql, test_sourcing.sql |
| BR-022 | A gig worker's verification state is one of unverified, verified or suspended | Product | **database** | CHECK ck_gig_worker_profile_verification allows unverified, verified or suspended | test_gig.sql |
| BR-023 | A gig request has a positive budget, a single currency, an ordered date window, and one pricing type | Product | **database** | constraint CHECK `ck_gig_request_budget`; constraint CHECK `ck_gig_request_currency`; constraint CHECK `ck_gig_request_dates`; constraint CHECK `ck_gig_request_deliverables`; constraint CHECK `ck_gig_request_pricing_type` | test_gig.sql |
| BR-024 | A gig application is decided iff it is accepted or rejected; `decided_at` is otherwise null | Product | **database** | constraint CHECK `ck_gig_application_decided` | test_gig.sql |
| BR-025 | A gig worker may hold no two active assignments with overlapping `daterange` windows | Product | **database** | constraint EXCLUDE `ex_gig_assignment_no_overlap` | test_business_rules.sql, test_concurrency.py |
| BR-026 | A gig assignment may be active, completed or terminated; only active assignments are constrained against overlap | Product | **database** | constraint CHECK `ck_gig_assignment_status`; constraint EXCLUDE `ex_gig_assignment_no_overlap` | test_gig.sql |
| BR-027 | Gig ratings are scored 1–5 on quality and communication dimensions | Product | **database** | constraint CHECK `ck_gig_rating_communication`; constraint CHECK `ck_gig_rating_quality` | test_gig.sql |
| BR-028 | Recruiters and other users cannot create a candidate profile for someone else; candidates register themselves (docket GAP-06) | Security | **database** | `trg_candidate_profile_self_registration` | test_domains_and_transitions.sql |
| BR-029 | Wallet and payment ledgers are append-only; a correction is a new entry that references the original | Finance | **database** | `trg_prevent_wallet_ledger_tampering`; `ck_wallet_ledger_correction_reference` | test_commercial.sql, test_access_control.sql |
| BR-030 | Profile download and view history is append-only and records actor, subject, time and credit | Security | **database** | `trg_prevent_download_history_tampering`; `trg_candidate_profile_download_history_block_truncate` | test_domains_and_transitions.sql, test_commercial.sql |
| BR-031 | A wallet balance is never negative and changes only together with a ledger entry | Finance | **database** | `ck_wallet_balance`; `post_wallet_entry` | test_wallet_functions.sql, test_concurrency.py |
| BR-032 | A status column changes only along a listed transition, or is a recorded exemption | Platform | **database** | `enforce_status_transition`; `trg_candidate_application_status_transition` | test_state_machines.sql, test_domains_and_transitions.sql |
| BR-033 | Each of the 14 sensitive action classes writes an audit event or is evidenced by an append-only ledger | Security | **database** | `log_change`; `fk_audit_event_action` | test_audit_coverage.sql |
| BR-034 | Audit events cannot be updated, deleted or truncated | Security | **database** | `trg_prevent_audit_event_tampering` | test_administration.sql, test_audit_coverage.sql |
| BR-035 | Personal data past its retention period is purged by a scheduled, audited job | Security | **database** | `purge_expired_data` | test_lifecycle.sql, test_integration_maintenance.sql |
| BR-036 | Erasing an account anonymises the person and keeps the financial and audit records | Security | **database** | `erase_user_account` | test_lifecycle.sql, test_audit_coverage.sql |
| BR-037 | A registration or tax identifier is stored encrypted and is unique per country and type | Security | **database** | `uq_organization_identifier_bidx`; `ck_organization_identifier_bidx`; `trg_organization_identifier_binding` | test_identifier_encryption.sql, test_identifier_crypto.py |
| BR-038 | A profile download is charged at the listed price once per organisation and candidate | Finance | **database** | `download_candidate_profile`; `uq_credit_price` | test_wallet_functions.sql |
| BR-039 | Impersonation needs a platform administrator and a reason, and is audited at start and end | Security | **database** | `begin_impersonation`; `end_impersonation` | test_audit_coverage.sql, test_administration.sql |
| BR-040 | An integration exchange is idempotent and dead-letters after the boundary's maximum attempts | Platform | **database** | `uq_integration_event_idempotency`; `fail_integration_event`; `ck_integration_event_attempts` | test_integration_maintenance.sql |

## Rules the database does not enforce

None.

A *query only* rule is a convention: any writer can create data that breaks it. Each needs a constraint, a trigger or a documented decision to leave it to the application.

Rules with no named test: **none**.

## Database-wide enforcement inventory

| Object | Count |
|:--|--:|
| PRIMARY KEY | 116 |
| FOREIGN KEY | 368 |
| UNIQUE | 87 |
| CHECK | 327 |
| EXCLUDE | 2 |
| Triggers (non-internal) | 159 |
| Indexes | 372 |

## Decision table: BR-002 device limit at login

Source: `core.create_session_with_device_limit`. The user row is locked (`FOR UPDATE`) so concurrent logins serialise. Allowed devices = the largest `max_devices_per_user` among the user's active, unexpired licence seats, or **2** if there is none. Sessions that have ended or been revoked are not counted, and the count is of distinct devices.

| Device already has an active session | Active devices >= allowed | Outcome | Test |
|:--|:--|:--|:--|
| N | N | Allow: register the device and create the session | tests/test_licences.sql (sessions 1 and 2) |
| N | Y | Reject: return NULL and write audit action `device.limit_exceeded` | tests/test_licences.sql, tests/test_business_rules.sql, tests/test_concurrency.py |
| Y | N | Allow: device already active, create the session | tests/test_br_decision_and_outreach.sql (row 3) |
| Y | Y | Allow: device already active, so the limit is not applied | tests/test_br_decision_and_outreach.sql (row 4) |

All four rows are tested. The earlier gap (two rows with no test) is closed by `tests/test_br_decision_and_outreach.sql`.

## Rules checked against the live catalog

Objects and test files named by BR-028 to BR-040 and by the overrides: **0 not found**.

`reconciled` means the rule is a statement about derived data (BR-017); the evidence is a reconciliation test, not a constraint.

