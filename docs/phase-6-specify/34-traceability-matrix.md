# Talentra: Requirements Traceability Matrix (Step 34)

**Phase:** 6 Specify | **Step:** 34 Traceability Matrix
**Generated** by `scripts/lifecycle/gen_traceability.py` from [`01-requirements.md`](../phase-1-discover/01-requirements.md). Do not hand-edit.

Links each requirement to its actors, linked rules, features, workflows, migration source and named tests. Code and KPI columns follow in steps 42 and 46 of the lifecycle; for a database project the code is the migration.

## Integrity checks

| Check | Result |
|:--|:--|
| Requirements parsed | **120** (BR 27, DATA 8, NFR 27, OPS 10, REQ 34, SEC 14) |
| Cross-references to an ID that does not exist | **0** |
| Named test files that do not exist | **0** |
| Cited migration files that do not exist | **0** |
| Functional, security, data and operational requirements with no named file under `tests/` | **0** |
| Test files with no `Covers:` header | **0** |
| `Covers:` tags naming an ID that exists in no register | **0** |
| Test files that no requirement names and that carry no tag | **0** |

## Matrix

| ID | Requirement | Actors | Linked | Priority | Migration | Tests | Status |
|:--|:--|:--|:--|:--|:--|:--|:--|
| REQ-001 | The system shall provide a single user identity record that all other domains reference | ACT-01, ACT-02, ACT-03, ACT-04, ACT-05,  | BR-001, FEAT-001, NFR-014, WF-01 | Must | 002 | test_identity.sql | Confirmed |
| REQ-002 | The system shall record credentials separately from the account record, with an algorithm identifier | ACT-01, ACT-02, ACT-03, ACT-04, ACT-05,  | BR-001, FEAT-001, NFR-014, NFR-015, SEC-006, WF-01 | Must | 012 | test_identity.sql | Confirmed |
| REQ-003 | The system shall authenticate a user by issuing a session record bound to a device identifier | ACT-01, ACT-02, ACT-03, ACT-04, ACT-05,  | BR-002, FEAT-001, NFR-002, SEC-002, WF-01, WF-10 | Must | 002 | test_identity.sql, test_licences.sql | Confirmed |
| REQ-004 | The system shall enforce a maximum concurrent-device entitlement per user, rejecting logins above it | ACT-01, ACT-02, ACT-03, ACT-04, ACT-05,  | BR-002, FEAT-002, FEAT-030, NFR-002, SEC-002, WF-01, WF-09 | Must | 015 | test_concurrency.py, test_licences.sql | Confirmed |
| REQ-005 | The system shall maintain an explicit device registry per user | ACT-01 | BR-002, FEAT-002, NFR-015, WF-01 | Should | 015 | test_licences.sql | Confirmed |
| REQ-006 | The system shall support revocation of an individual user session | ACT-01, ACT-08 | BR-003, FEAT-003, OPS-003, SEC-003, WF-10 | Must | 012 | test_administration.sql, test_licences.sql | Confirmed |
| REQ-007 | The system shall record the actor's consent state and privacy preferences | ACT-01, ACT-03, ACT-08 | BR-004, FEAT-004, NFR-013, SEC-011, WF-11 | Should | 012 | test_administration.sql, test_audit_coverage.sql, test_candidate_privacy.sql, test_messaging.sql | Confirmed |
| REQ-008 | The system shall maintain a single user identity capable of simultaneously holding a candidate profile and ... | ACT-01, ACT-03 | BR-001, FEAT-005, NFR-009, WF-02, WF-07 | Must | 002 | test_candidate_profile.sql, test_gig.sql | Confirmed |
| REQ-009 | The system shall maintain canonical reference taxonomies (skill, city, country, qualification, role, indust... | ACT-01, ACT-02, ACT-07, ACT-08 | BR-005, FEAT-006, NFR-006, WF-01, WF-02, WF-03 | Must | 003, 004 | test_master_data.sql, test_seed_master_data.sql | Confirmed |
| REQ-010 | The system shall maintain a candidate profile with headline, summary, experience, skills, education, locati... | ACT-01, ACT-03 | BR-006, DATA-002, FEAT-007, NFR-011, WF-02 | Must | 005, 010 | test_candidate_extensions.sql, test_candidate_profile.sql | Confirmed |
| REQ-011 | The system shall compute and store a profile-completeness score for a candidate profile | ACT-01, ACT-03 | BR-007, FEAT-008, NFR-011, WF-02 | Should | 010 | test_candidate_extensions.sql | Confirmed |
| REQ-012 | The system shall store candidate documents (resumes) with type, MIME type, size, checksum and archival state | ACT-01, ACT-03 | BR-008, FEAT-009, NFR-011, SEC-009, WF-02 | Must | 006 | test_candidate_document.sql | Confirmed |
| REQ-013 | The system shall track candidate skill proficiency and years of experience per skill | ACT-01, ACT-03 | BR-009, FEAT-007, NFR-002, WF-02 | Must | 005 | test_candidate_profile.sql | Confirmed |
| REQ-014 | The system shall support recruiter-side candidate search by skill, experience, location and visibility | ACT-02, ACT-04, ACT-05, ACT-06 | BR-010, FEAT-010, NFR-002, NFR-005, WF-04, WF-14 | Must | - | test_access_control.sql | Confirmed |
| REQ-015 | The system shall maintain a corporate organisation with type, hierarchy, locations, identifiers and members | ACT-02, ACT-04, ACT-06 | BR-011, FEAT-011, NFR-012, WF-08 | Must | 007, 013 | test_organization.sql, test_organization_extensions.sql | Confirmed |
| REQ-016 | The system shall record a recruiter-to-client organisation mapping | ACT-02, ACT-04 | BR-011, FEAT-011, SEC-002, WF-08 | Could | 013 | test_organization_extensions.sql | Confirmed |
| REQ-017 | The system shall allow an authorised recruiter or organisation administrator to post a job requirement with... | ACT-02, ACT-04 | BR-012, FEAT-012, NFR-003, NFR-012, WF-03 | Must | 008 | test_job_posting.sql | Confirmed |
| REQ-018 | The system shall support a structured job questionnaire and per-application question responses | ACT-02, ACT-01 | BR-013, DATA-004, FEAT-013, WF-03, WF-04 | Should | 011 | test_job_questionnaire.sql | Confirmed |
| REQ-019 | The system shall allow a candidate to apply to a published job exactly once | ACT-01, ACT-02 | BR-014, FEAT-014, NFR-002, NFR-009, WF-04 | Must | 009 | test_candidate_application.sql | Confirmed |
| REQ-020 | The system shall record an application with its source, cover letter, screening answers and recruitment stage | ACT-01, ACT-02, ACT-07 | BR-015, DATA-001, FEAT-014, NFR-009, WF-04, WF-05 | Must | 009 | test_candidate_application.sql, test_domains_and_transitions.sql, test_state_machines.sql | Confirmed |
| REQ-021 | The system shall record every change to an application's recruitment stage, with actor, previous value, new... | ACT-02, ACT-04 | BR-016, FEAT-015, NFR-009, SEC-003, WF-05 | Must | 009 | test_candidate_application.sql, test_domains_and_transitions.sql | Confirmed |
| REQ-022 | The system shall maintain the recruitment pipeline stage set (`applied`, `shortlisted`, `interviewed`, `off... | ACT-01, ACT-02, ACT-04 | BR-015, DATA-001, FEAT-015, WF-05 | Must | 009 | test_candidate_application.sql, test_state_machines.sql | Confirmed |
| REQ-023 | The system shall support job-feed matching of candidates to published jobs by role, city, arrangement and s... | ACT-01, ACT-03 | BR-017, FEAT-016, NFR-002, WF-04 | Must | - | - | Confirmed |
| REQ-024 | The system shall support a recruiter pipeline funnel aggregation by application stage | ACT-02, ACT-04 | BR-017, FEAT-017, NFR-003, WF-05 | Should | - | test_golden_kpis.py | Confirmed |
| REQ-025 | The system shall support agency consultants requesting to source for a job, and the employer accepting or d... | ACT-05, ACT-04 | BR-018, FEAT-018, SEC-002, WF-06 | Should | 016 | test_sourcing.sql | Confirmed |
| REQ-026 | The system shall permit a consultant to submit candidates only for jobs explicitly open to consultants | ACT-05 | BR-019, FEAT-018, SEC-002, WF-06 | Must | 016 | test_business_rules.sql, test_sourcing.sql | Confirmed |
| REQ-027 | The system shall record a consultant's candidate submission and its progression to hired | ACT-05, ACT-04 | BR-020, FEAT-018, NFR-009, WF-06 | Should | 016 | test_sourcing.sql | Confirmed |
| REQ-028 | The system shall support batched outreach to candidates with per-recipient delivery state | ACT-05, ACT-02 | BR-021, FEAT-024, NFR-008, WF-06 | Should | 016 | test_sourcing.sql | Confirmed |
| REQ-029 | The system shall allow a candidate to publish a gig-worker profile with services, rates and verification state | ACT-01, ACT-03 | BR-022, FEAT-025, NFR-011, WF-07 | Must | 014 | test_gig.sql | Confirmed |
| REQ-030 | The system shall allow a corporate client to raise a gig request with deliverables, budget, pricing type an... | ACT-02, ACT-04 | BR-023, FEAT-026, NFR-003, WF-07 | Must | 014 | test_gig.sql | Confirmed |
| REQ-031 | The system shall allow a gig worker to apply to a gig request, and the client to accept or reject | ACT-03, ACT-04 | BR-024, FEAT-026, NFR-009, WF-07 | Must | 014 | test_gig.sql | Confirmed |
| REQ-032 | The system shall prevent a gig worker from holding two active assignments with overlapping date ranges | ACT-02, ACT-01, ACT-03 | BR-025, FEAT-027, NFR-002, SEC-004, WF-07 | Must | 014 | test_business_rules.sql, test_concurrency.py | Confirmed |
| REQ-033 | The system shall schedule gig assignments with agreed amount, dates and status, and support termination | ACT-02, ACT-01, ACT-03 | BR-026, FEAT-026, NFR-009, WF-07 | Must | 014 | test_gig.sql | Confirmed |
| REQ-034 | The system shall record gig ratings across quality and communication dimensions | ACT-02, ACT-01, ACT-03 | BR-027, FEAT-028, NFR-011, WF-07 | Could | 014 | test_gig.sql | Confirmed |
| BR-001 | Email addresses are unique across all user accounts and stored in lowercase | ACT-01 | REQ-001 | Must | 002 | test_identity.sql | Confirmed |
| BR-002 | A user may hold no more concurrent active sessions than the device entitlement of their active licence; a p... | ACT-01..ACT-08 | REQ-003, REQ-004 | Must | 015 | test_br_decision_and_outreach.sql, test_concurrency.py, test_identity.sql, test_licences.sql | Confirmed |
| BR-003 | A revoked session is terminal and cannot be reused; revocation writes an audit event | ACT-01, ACT-08 | REQ-006 | Must | 015 | test_administration.sql, test_licences.sql | Confirmed |
| BR-004 | Consent state is recorded per subject and category and is queryable for disclosure decisions | ACT-01, ACT-08 | REQ-007 | Should | 012 | test_administration.sql | Confirmed |
| BR-005 | Master reference data is read-only after seeding and carries no outbound foreign keys | ACT-08 | REQ-009 | Must | - | test_access_control.sql, test_br_decision_and_outreach.sql, test_master_data.sql, test_seed_master_data.sql | Confirmed |
| BR-006 | A candidate profile carries exactly one visibility state governing who may discover it | ACT-01, ACT-02 | REQ-010 | Must | 005 | test_candidate_extensions.sql, test_candidate_profile.sql | Confirmed |
| BR-007 | Profile completeness is derived from the presence of headline, summary, skills, education, experience, resu... | ACT-01 | REQ-011 | Should | 010 | test_candidate_extensions.sql | Confirmed |
| BR-008 | A candidate may have at most one active primary resume; only a resume may be marked primary | ACT-01, ACT-03 | REQ-012 | Must | 006 | test_candidate_document.sql | Confirmed |
| BR-009 | A skill claim carries a proficiency level and optional per-skill experience in years | ACT-01 | REQ-013 | Must | 005 | test_candidate_profile.sql | Confirmed |
| BR-010 | Candidate search honours profile visibility and the block rules in BR-021 | ACT-02, ACT-04, ACT-06 | REQ-014 | Must | - | test_access_control.sql, test_candidate_privacy.sql | Confirmed |
| BR-011 | An organisation has one type, may have a hierarchy, and holds its own locations and legal identifiers | ACT-02, ACT-04, ACT-06 | REQ-015 | Must | 007 | test_organization.sql, test_organization_extensions.sql | Confirmed |
| BR-012 | Salary fields are all-or-none: either all salary and currency and period fields are populated, or none are | ACT-02, ACT-04 | REQ-017 | Must | 008 | test_job_posting.sql | Confirmed |
| BR-013 | A job carries at most one questionnaire; a filled position requires a candidate answer | ACT-02, ACT-01 | REQ-018 | Should | 011 | test_job_questionnaire.sql | Confirmed |
| BR-014 | A candidate may hold at most one application to a given job | ACT-01 | REQ-019 | Must | 009 | test_candidate_application.sql | Confirmed |
| BR-015 | An application stage is one of the seven permitted values | ACT-01, ACT-02 | REQ-020, REQ-022 | Must | 009 | test_candidate_application.sql, test_domains_and_transitions.sql, test_state_machines.sql | Confirmed |
| BR-016 | Every stage change is captured in `application_status_history` with previous and new values; a change to th... | ACT-02, ACT-04 | REQ-021 | Must | 009 | test_candidate_application.sql, test_domains_and_transitions.sql | Confirmed |
| BR-017 | Funnel and feed aggregations are derived from the authoritative application and job tables, not from denorm... | ACT-02, ACT-04 | REQ-023, REQ-024 | Should | - | test_golden_kpis.py | Confirmed |
| BR-018 | A consultant sourcing request is unique per (job, consultant); a decision is recorded iff the request is ac... | ACT-05, ACT-04 | REQ-025 | Should | 016 | test_sourcing.sql | Confirmed |
| BR-019 | A consultant may act only on a job whose consultant policy is open | ACT-05 | REQ-026 | Must | 016 | test_business_rules.sql, test_sourcing.sql | Confirmed |
| BR-020 | A consultant may submit a given candidate to a given job only once | ACT-05 | REQ-027 | Should | 016 | test_sourcing.sql | Confirmed |
| BR-021 | Outreach recipients are filtered against candidate block state before dispatch | ACT-05, ACT-02 | REQ-028 | Should | - | test_br_decision_and_outreach.sql, test_sourcing.sql | Confirmed |
| BR-022 | A gig worker's verification state is one of unverified, verified or suspended | ACT-01, ACT-03 | REQ-029 | Should | 014 | test_gig.sql | Confirmed |
| BR-023 | A gig request has a positive budget, a single currency, an ordered date window, and one pricing type | ACT-02, ACT-04 | REQ-030 | Must | 014 | test_gig.sql | Confirmed |
| BR-024 | A gig application is decided iff it is accepted or rejected; `decided_at` is otherwise null | ACT-01, ACT-02 | REQ-031 | Must | 014 | test_gig.sql | Confirmed |
| BR-025 | A gig worker may hold no two active assignments with overlapping `daterange` windows | ACT-01, ACT-02 | REQ-032 | Must | 014 | test_business_rules.sql, test_concurrency.py | Confirmed |
| BR-026 | A gig assignment may be active, completed or terminated; only active assignments are constrained against ov... | ACT-01, ACT-02 | REQ-033 | Must | 014 | test_gig.sql, test_state_machines.sql | Confirmed |
| BR-027 | Gig ratings are scored 1–5 on quality and communication dimensions | ACT-01, ACT-02 | REQ-034 | Could | 014 | test_gig.sql | Confirmed |
| SEC-001 | Access to data shall be governed by a role and permission model | ACT-01..ACT-08 | REQ-001 | Must | 012 | test_access_control.sql, test_administration.sql, test_security.sql | Confirmed — 28 permissions and 99 role m |
| SEC-002 | Tenant and consultant scope shall be enforced so a recruiter sees only their own organisation's data and a ... | ACT-02, ACT-04, ACT-05 | REQ-015, REQ-025, REQ-026 | Must | 016 | test_access_control.sql, test_administration.sql, test_candidate_privacy.sql, test_security.sql, test_sourcing.sql | Confirmed — the consultant rule is a tri |
| SEC-003 | Security-relevant actions shall be written to an append-only audit log | ACT-01, ACT-02, ACT-04, ACT-05, ACT-06,  | REQ-006, REQ-021 | Must | 012 | test_administration.sql, test_audit_coverage.sql, test_domains_and_transitions.sql, test_lifecycle.sql | Confirmed — all 14 sensitive action clas |
| SEC-004 | Concurrent conflicting writes to a gig calendar shall be rejected at the storage layer | ACT-03, ACT-04 | REQ-032 | Must | 014 | test_concurrency.py | Confirmed |
| SEC-005 | Financial and download-history records shall be immutable after write | ACT-06, ACT-08 | REQ-033 | Must | 017 | test_access_control.sql, test_administration.sql, test_commercial.sql, test_security.sql | Confirmed — but `TRUNCATE` is not blocke |
| SEC-006 | Passwords shall be stored as salted hashes and the algorithm recorded | ACT-01..ACT-08 | REQ-002 | Must | 012 | test_access_control.sql, test_identifier_encryption.sql | Confirmed — `ck_user_credential_password |
| SEC-007 | Session tokens shall be stored hashed | ACT-01..ACT-08 | REQ-003 | Must | 002 | test_access_control.sql, test_identity.sql, test_integration_structures.sql | Confirmed — `ck_user_session_token_hash_ |
| SEC-008 | Login attempts exceeding the device entitlement shall be refused and recorded | ACT-01..ACT-08 | REQ-004 | Must | 015 | test_concurrency.py, test_licences.sql | Confirmed |
| SEC-009 | Uploaded documents shall be size- and type-constrained and integrity-checked | ACT-01, ACT-03 | REQ-012 | Must | 006 | test_candidate_document.sql | Confirmed |
| SEC-010 | Candidates shall be able to block, and be blocked by, users and organisations, and visibility checks shall ... | ACT-01, ACT-02, ACT-04 | REQ-010 | Must | 012 | test_administration.sql, test_candidate_privacy.sql, test_security.sql | Confirmed — function-scoped: applies onl |
| SEC-011 | Consent and privacy preference state shall be queryable to support disclosure decisions | ACT-01, ACT-03, ACT-08 | REQ-007 | Should | 012 | test_administration.sql, test_audit_coverage.sql, test_candidate_privacy.sql | Confirmed |
| SEC-012 | PII columns shall carry a sensitivity classification | ACT-08 | REQ-010, REQ-012 | Should | - | test_classification.sql, test_identifier_encryption.sql | Confirmed — every column of every base t |
| SEC-013 | Data access to sensitive candidate fields shall be masked for unauthorised viewers | ACT-01, ACT-02, ACT-04 | REQ-010 | Should | - | test_access_control.sql, test_classification.sql | Confirmed for support staff — `core.mask |
| SEC-014 | Least-privilege database roles and row-level security shall separate application, reporting and administrat... | ACT-08 | REQ-001 | Should | - | test_access_control.sql, test_security.sql | Confirmed — five NOLOGIN roles with gran |
| DATA-001 | Enumerated business states shall be stored as constrained codes, not free text | ACT-08 | - | Must | 009 | test_constraints.sql, test_enumerations.sql | Confirmed |
| DATA-002 | Missing data shall be represented strictly as SQL NULL, with no sentinel strings or numbers | ACT-08 | - | Must | - | - | Confirmed |
| DATA-003 | All instant-valued timestamps shall be timezone-aware and normalised to UTC; calendar dates shall use `DATE` | ACT-08 | - | Must | - | test_lifecycle.sql | Confirmed — 9 `DATE` columns are by desi |
| DATA-004 | Free-text business payloads shall be length-bounded | ACT-08 | - | Should | 009 | test_constraints.sql | Confirmed |
| DATA-005 | All operational tables shall use a surrogate identity primary key named `id` | ACT-08 | - | Must | - | - | Confirmed — 4 `analytics.dim_*` use `*_k |
| DATA-006 | Referential integrity shall be enforced by foreign keys with explicit delete behaviour | ACT-08 | - | Must | 001 | - | Confirmed |
| DATA-007 | Names and identifiers shall follow canonical formats (lowercase RFC email, E.164 phone, ISO 4217 currency, ... | ACT-08 | - | Must | 002 | - | Confirmed |
| DATA-008 | Sensitive personal data shall be classified in the data dictionary | ACT-08 | - | Should | - | test_classification.sql | Confirmed — see SEC-012; the dictionary  |
| OPS-001 | The database shall be created and seeded by ordered, idempotent migration scripts | ACT-08 | - | Must | 001 | - | Confirmed |
| OPS-002 | The schema shall be delivered as a reproducible containerised environment | ACT-08 | - | Must | - | - | Confirmed |
| OPS-003 | Session revocation shall be invocable as a database function with an audit trail | ACT-08 | - | Must | 012 | test_licences.sql | Confirmed |
| OPS-004 | The system shall provide a logical backup and restore-and-verify runbook | ACT-08 | - | Must | - | - | Confirmed — executed 2026-10-27 on Postg |
| OPS-005 | Analytical marts shall be refreshable on demand | ACT-08 | - | Should | 019 | test_analytics.sql, test_golden_kpis.py, test_integration_maintenance.sql | Confirmed — `analytics.refresh_reporting |
| OPS-006 | The system shall provide a repeatable benchmark harness producing latency percentiles and cache-hit ratios | ACT-08 | - | Should | - | test_benchmark_harness.py | Confirmed — all 12 queries return valid  |
| OPS-007 | The system shall provide an automated data-quality validator covering the ten rule groups | ACT-08 | - | Should | - | - | Confirmed — 15 of 15 pass on a freshly s |
| OPS-008 | The schema shall be verified by an executable test suite covering identity, tenancy, commerce, gig, sourcin... | ACT-08 | - | Must | - | - | Confirmed — executed 2026-10-27: all sui |
| OPS-009 | High-volume application data shall have a declared scale-out path | ACT-08 | - | Should | 019 | test_analytics.sql | Confirmed — but no benchmark query targe |
| OPS-010 | The platform shall run on a single containerised PostgreSQL 17 service | ACT-08 | - | Must | - | - | Confirmed — note: single-service means n |
| NFR-001 | Candidate search shall return within the declared latency envelope at the declared workload | ACT-02, ACT-04, ACT-06 | REQ-014 | - | - | - | Delegated Decision; Met — evidence in [` |
| NFR-002 | Authenticated reads shall complete within the declared latency envelope | ACT-01..ACT-08 | REQ-003, REQ-004, REQ-014, REQ-019, REQ-032 | - | - | - | Delegated Decision; Met — evidence in [` |
| NFR-003 | Transactional writes shall complete within the declared latency envelope | ACT-02, ACT-04 | REQ-017, REQ-024, REQ-030 | - | - | - | Delegated Decision; Met — evidence in [` |
| NFR-004 | Analytical queries shall complete within the declared latency envelope | ACT-02, ACT-08 | REQ-024 | - | - | - | Delegated Decision; Met — evidence in [` |
| NFR-005 | The platform shall sustain a declared concurrent-user level | ACT-01..ACT-08 | NFR-002, REQ-014 | - | - | - | Delegated Decision; Met (500 sessions, a |
| NFR-006 | Reference-data reads shall complete within the declared latency envelope | ACT-01..ACT-08 | REQ-009 | - | - | - | Delegated Decision; Met — evidence in [` |
| NFR-007 | The platform shall meet a declared availability objective | ACT-01..ACT-08 | OPS-002 | - | - | - | Delegated Decision; Database side met; n |
| NFR-008 | Outbound messaging shall be delivered within a declared window | ACT-01, ACT-02 | REQ-028 | - | - | test_integration_maintenance.sql, test_messaging.sql | Delegated Decision; Database side met; n |
| NFR-009 | Recruitment pipelines shall be queryable at the declared volume | ACT-02, ACT-04 | REQ-020, REQ-021, REQ-027, REQ-031, REQ-033 | - | - | - | Delegated Decision; Met — evidence in [` |
| NFR-010 | The platform shall meet a declared recovery time objective | ACT-08 | OPS-004 | - | - | - | Delegated Decision; Met — evidence in [` |
| NFR-011 | The platform shall meet a declared recovery point objective | ACT-08 | OPS-004 | - | - | - | Delegated Decision; Needs an operator to |
| NFR-012 | Financial ledgers shall reconcile to the stored balance with zero discrepancy | ACT-06, ACT-08 | REQ-017, REQ-033, SEC-005 | - | - | test_wallet_functions.sql | Delegated Decision; Met — evidence in [` |
| NFR-013 | Consent and block state shall be enforced on every read path that touches candidate PII | ACT-01, ACT-02 | REQ-007, SEC-010 | - | - | test_candidate_privacy.sql | Delegated Decision; Met — evidence in [` |
| NFR-014 | Credentials shall be stored using a cryptographically approved hash | ACT-01..ACT-08 | REQ-002, SEC-006 | - | - | - | Delegated Decision; Met — evidence in [` |
| NFR-015 | Data quality shall meet a declared compliance rate | ACT-08 | DATA-001, DATA-008 | - | - | - | Delegated Decision; Met — evidence in [` |
| NFR-016 | Sensitive actions shall be auditable at a declared coverage | ACT-08 | SEC-003 | - | - | test_audit_coverage.sql | Delegated Decision; Met (14 of 14 classe |
| NFR-017 | Personal data shall be retained for a declared period and then removed | ACT-08 | REQ-007, SEC-011 | - | - | test_integration_maintenance.sql | Delegated Decision; Met — evidence in [` |
| NFR-018 | The platform shall meet a declared data-protection obligation | ACT-01, ACT-02, ACT-08 | SEC-006, SEC-010, SEC-011, SEC-012 | - | - | test_integration_maintenance.sql | Delegated Decision; Met — evidence in [` |
| NFR-019 | The platform shall meet a declared accessibility conformance level | ACT-01, ACT-02 | - | - | - | - | Scope decision required (see [`docs/phas |
| NFR-020 | Analytical marts shall be refreshed within a declared staleness window | ACT-08 | OPS-005 | - | - | test_integration_maintenance.sql | Delegated Decision; Met by construction  |
| NFR-021 | The platform shall meet a declared regulatory obligation | ACT-08 | NFR-018, SEC-006, SEC-014 | - | - | test_integration_maintenance.sql | Delegated Decision; Met — evidence in [` |
| NFR-022 | The platform shall be reproducible from a clean checkout | ACT-08 | OPS-001, OPS-002, OPS-008 | - | - | - | Delegated Decision; Met locally; CI unru |
| NFR-023 | The platform shall remain portable across supported PostgreSQL versions | ACT-08 | OPS-010 | - | - | - | Delegated Decision; Boundary — evidence  |
| NFR-024 | The platform shall be maintainable, measured by a declared documentation-coverage ratio | ACT-08 | DATA-008, SEC-012 | - | - | test_column_definitions.sql | Delegated Decision; Met — evidence in [` |
| NFR-025 | The platform shall operate within a declared resource envelope | ACT-08 | OPS-002 | - | - | - | Delegated Decision; Boundary (measured t |
| NFR-026 | The platform shall produce observable operational telemetry | ACT-08 | NFR-020, OPS-005, OPS-006 | - | - | test_integration_maintenance.sql | Delegated Decision; Met by construction  |
| NFR-027 | The platform shall detect and isolate a failing integration boundary | ACT-08 | OPS-003, SEC-008 | - | - | test_integration_maintenance.sql, test_integration_structures.sql | Delegated Decision; Met — evidence in [` |

## Tests by requirement count

| Test file | Requirements covered |
|:--|--:|
| `tests/test_gig.sql` | 11 |
| `tests/test_administration.sql` | 10 |
| `tests/test_access_control.sql` | 10 |
| `tests/test_sourcing.sql` | 9 |
| `tests/test_licences.sql` | 8 |
| `tests/test_integration_maintenance.sql` | 8 |
| `tests/test_candidate_application.sql` | 7 |
| `tests/test_identity.sql` | 6 |
| `tests/test_concurrency.py` | 6 |
| `tests/test_candidate_privacy.sql` | 6 |
| `tests/test_candidate_profile.sql` | 5 |
| `tests/test_domains_and_transitions.sql` | 5 |
| `tests/test_security.sql` | 5 |
| `tests/test_audit_coverage.sql` | 4 |
| `tests/test_candidate_extensions.sql` | 4 |
| `tests/test_state_machines.sql` | 4 |
| `tests/test_business_rules.sql` | 4 |
| `tests/test_candidate_document.sql` | 3 |
| `tests/test_organization_extensions.sql` | 3 |
| `tests/test_golden_kpis.py` | 3 |
| `tests/test_br_decision_and_outreach.sql` | 3 |
| `tests/test_classification.sql` | 3 |
| `tests/test_messaging.sql` | 2 |
| `tests/test_master_data.sql` | 2 |
| `tests/test_seed_master_data.sql` | 2 |
| `tests/test_organization.sql` | 2 |
| `tests/test_job_posting.sql` | 2 |
| `tests/test_job_questionnaire.sql` | 2 |
| `tests/test_lifecycle.sql` | 2 |
| `tests/test_identifier_encryption.sql` | 2 |
| `tests/test_integration_structures.sql` | 2 |
| `tests/test_constraints.sql` | 2 |
| `tests/test_analytics.sql` | 2 |
| `tests/test_commercial.sql` | 1 |
| `tests/test_enumerations.sql` | 1 |
| `tests/test_benchmark_harness.py` | 1 |
| `tests/test_wallet_functions.sql` | 1 |
| `tests/test_column_definitions.sql` | 1 |
