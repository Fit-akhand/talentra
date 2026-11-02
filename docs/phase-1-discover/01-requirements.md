# Talentra — Requirement Analysis Docket (Phase 1, Step 1)

**Phase:** 1 — Discover
**Step:** 1 — Requirement Analysis Docket
**Status:** **Reconciled against the docket** on 2026-10-23 ([`01-docket-reconciliation.md`](01-docket-reconciliation.md)); originally written before the docket was available. Requirement text and provenance are unchanged; the docket mapping in section 7.1 is now verifiable and was done in the reconciliation. Implementation status in the Status columns was refreshed on 2026-10-27.
**Authored:** 2026-10-21
**Canonical location for this register:** this file. All other Phase 1 documents link here; none restate it.

---

## 0. How to read this document

### 0.1 Provenance of every requirement

The authoritative hackathon docket (**S-001**) could not be located — it is not in the repository, not in any
commit in its history, and could not be found on the accessible filesystem (full search log:
[`docs/source/README.md`](../source/README.md) §2.1). **No requirement in this register may therefore be described
as an official docket requirement.**

Each requirement carries a `Source` cell naming the evidence it was derived from, and a `Provenance` cell:

| Provenance | Meaning | Docket-mandated? |
|:--|:--|:--|
| `Implementation-Derived` | The requirement describes behaviour that a verifiable database object in `db/migrations/` already enforces. | **No** — inferred from the implementation. |
| `Document-Derived` | The requirement restates a rule already formalised in an existing engineering dossier (Rule Groups RG1–RG10, STRIDE rows, integration-boundary contracts). | **No** — inferred from prior documentation. |
| `Dialect-Only` | The requirement is a PostgreSQL-specific implementation constraint, not a business rule. | No — technical constraint. |
| `Proposed` | A capability the implementation implies but that is not yet a stated requirement anywhere. | No — requires owner approval. |

**Consequence:** every requirement here is `Proposed` or `Confirmed-from-implementation` in status. None is
`Docket-Mandated`. See [`docs/phase-1-discover/01-scope-assumptions.md`](01-scope-assumptions.md) **A-002**.

### 0.2 ID scheme

One consistent convention, no duplicate IDs:

| Prefix | Type | Count |
|:--|:--|--:|
| `REQ-###` | Functional / general capability | 34 |
| `BR-###` | Business rule | 27 |
| `NFR-###` | Non-functional requirement | 27 |
| `SEC-###` | Security requirement | 14 |
| `DATA-###` | Data requirement | 8 |
| `OPS-###` | Operational requirement | 10 |

### 0.3 Priority

MoSCoW. **Must** = the product is not coherent without it. **Should** = important, degraded without it.
**Could** = valuable, safe to defer. **Won't** = explicitly excluded from this hackathon.

> **Rule applied:** an existing implementation does **not** confer Must priority. A capability is Must only
> when removing it would break a core product promise (identity, job posting, application, payment, gig
> fulfilment). This rule is why several implemented capabilities are Should or Could — see §5.

### 0.4 Status

`Confirmed` (enforced by a verifiable database object) · `Documented` (stated in prose only) ·
`Proposed` (neither) · `Unresolved` (cannot be settled without the docket or an owner decision).

---

## 1. Functional requirements — `REQ-###`

| ID | Requirement | Source | Provenance | Priority | Actor(s) | BR | FEAT | WF | NFR | Acceptance criterion | Verification | Status |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| REQ-001 | The system shall provide a single user identity record that all other domains reference | `db/migrations/002_create_identity.sql:8-56` (`core.user_account`) | Implementation-Derived | Must | ACT-01, ACT-02, ACT-03, ACT-04, ACT-05, ACT-06, ACT-07, ACT-08 | BR-001 | FEAT-001 | WF-01 | NFR-014 | A user account row exists with a unique lowercase email; no other schema defines an independent person table | `tests/test_identity.sql`; `information_schema` check | Confirmed |
| REQ-002 | The system shall record credentials separately from the account record, with an algorithm identifier | `db/migrations/012_create_administration_security.sql:81-100` (`core.user_credential`) | Implementation-Derived | Must | ACT-01, ACT-02, ACT-03, ACT-04, ACT-05, ACT-06, ACT-07, ACT-08 | BR-001 | FEAT-001 | WF-01 | NFR-014, NFR-015, SEC-006 | `core.user_credential.secret_hash` is non-empty and `algorithm` defaults to `argon2id` | `tests/test_identity.sql` | Confirmed |
| REQ-003 | The system shall authenticate a user by issuing a session record bound to a device identifier | `db/migrations/002_create_identity.sql:130-165`; `015:166-240` (`core.create_session_with_device_limit`) | Implementation-Derived | Must | ACT-01, ACT-02, ACT-03, ACT-04, ACT-05, ACT-06, ACT-07, ACT-08 | BR-002 | FEAT-001 | WF-01, WF-10 | NFR-002, SEC-002 | A session row is created with a token hash, device identifier, `started_at`; device-limit entitlement is evaluated | `tests/test_identity.sql`, `tests/test_licences.sql` | Confirmed |
| REQ-004 | The system shall enforce a maximum concurrent-device entitlement per user, rejecting logins above it | `db/migrations/015_create_licences_and_device_limits.sql:166-240` | Implementation-Derived | Must | ACT-01, ACT-02, ACT-03, ACT-04, ACT-05, ACT-06, ACT-07, ACT-08 | BR-002 | FEAT-002, FEAT-030 | WF-01, WF-09 | NFR-002, SEC-002 | A login on a new device beyond the entitlement is refused and the function returns NULL | `tests/test_licences.sql:134-144`; `tests/test_concurrency.py:33` | Confirmed |
| REQ-005 | The system shall maintain an explicit device registry per user | `db/migrations/015_create_licences_and_device_limits.sql:163` (`core.user_device`) | Implementation-Derived | Should | ACT-01 | BR-002 | FEAT-002 | WF-01 | NFR-015 | Device rows are keyed to the owning account and deletable independently of sessions | `tests/test_licences.sql` | Confirmed |
| REQ-006 | The system shall support revocation of an individual user session | `db/migrations/012_create_administration_security.sql:295-330` (`core.revoke_user_session`) | Implementation-Derived | Must | ACT-01, ACT-08 | BR-003 | FEAT-003 | WF-10 | SEC-003, OPS-003 | Revocation sets `revoked_at` and `ended_at` and writes a `session.revoked` audit event | `tests/test_licences.sql:161`; `tests/test_administration.sql` | Confirmed |
| REQ-007 | The system shall record the actor's consent state and privacy preferences | `db/migrations/012_create_administration_security.sql:170-215` (`core.consent_record`); `018` (`messaging.user_privacy_preference`) | Implementation-Derived | Should | ACT-01, ACT-03, ACT-08 | BR-004 | FEAT-004 | WF-11 | NFR-013, SEC-011 | Consent rows record the subject, category, state and timestamp | `tests/test_administration.sql`, `tests/test_audit_coverage.sql`, `tests/test_candidate_privacy.sql` | Confirmed |
| REQ-008 | The system shall maintain a single user identity capable of simultaneously holding a candidate profile and a gig-worker profile | `db/migrations/002:8`; `005`; `014` (both FK to `core.user_account`) | Implementation-Derived | Must | ACT-01, ACT-03 | BR-001 | FEAT-005 | WF-02, WF-07 | NFR-009 | One `core.user_account` may be referenced by both `profile.candidate_profile` and `gig.gig_worker_profile` | `tests/test_candidate_profile.sql`, `tests/test_gig.sql` | Confirmed |
| REQ-009 | The system shall maintain canonical reference taxonomies (skill, city, country, qualification, role, industry, employment type, work type, language) usable by all domains | `db/migrations/003_create_master_data.sql`, `004_seed_master_reference_data.sql` | Implementation-Derived | Must | ACT-01, ACT-02, ACT-07, ACT-08 | BR-005 | FEAT-006 | WF-01, WF-02, WF-03 | NFR-006 | All 10 master tables are populated by the seed and referenced by other schemas | `tests/test_master_data.sql`, `tests/test_seed_master_data.sql` | Confirmed |
| REQ-010 | The system shall maintain a candidate profile with headline, summary, experience, skills, education, locations, languages and projects | `db/migrations/005_create_candidate_profile.sql`; `010_create_candidate_extensions.sql` | Implementation-Derived | Must | ACT-01, ACT-03 | BR-006 | FEAT-007 | WF-02 | NFR-011, DATA-002 | Profile row exists with status, visibility, experience years; child tables carry FK to profile | `tests/test_candidate_profile.sql`, `tests/test_candidate_extensions.sql` | Confirmed |
| REQ-011 | The system shall compute and store a profile-completeness score for a candidate profile | `db/migrations/010_create_candidate_extensions.sql:245-271` | Implementation-Derived | Should | ACT-01, ACT-03 | BR-007 | FEAT-008 | WF-02 | NFR-011 | Exactly one completion row per profile; `total_score_percentage` between 0 and 100 | `tests/test_candidate_extensions.sql` | Confirmed |
| REQ-012 | The system shall store candidate documents (resumes) with type, MIME type, size, checksum and archival state | `db/migrations/006_create_candidate_document.sql` | Implementation-Derived | Must | ACT-01, ACT-03 | BR-008 | FEAT-009 | WF-02 | NFR-011, SEC-009 | One primary resume per candidate; MIME and size constraints enforced; SHA-256 checksum stored | `tests/test_candidate_document.sql:71-203` | Confirmed |
| REQ-013 | The system shall track candidate skill proficiency and years of experience per skill | `db/migrations/005_create_candidate_profile.sql` (`profile.candidate_skill`) | Implementation-Derived | Must | ACT-01, ACT-03 | BR-009 | FEAT-007 | WF-02 | NFR-002 | Skill rows reference `master.skill`; proficiency level is constrained; primary flag supported | `tests/test_candidate_profile.sql` | Confirmed |
| REQ-014 | The system shall support recruiter-side candidate search by skill, experience, location and visibility | `db/queries/01_candidate_multicriteria_search.sql` | Implementation-Derived | Must | ACT-02, ACT-04, ACT-05, ACT-06 | BR-010 | FEAT-010 | WF-04, WF-14 | NFR-002, NFR-005 | Query returns non-empty result on a representative dataset and meets the declared latency target | `tests/test_access_control.sql` | Confirmed |
| REQ-015 | The system shall maintain a corporate organisation with type, hierarchy, locations, identifiers and members | `db/migrations/007_create_organization.sql`; `013_create_organization_extensions.sql` | Implementation-Derived | Must | ACT-02, ACT-04, ACT-06 | BR-011 | FEAT-011 | WF-08 | NFR-012 | Organisation row with unique slug; hierarchy and members reference it | `tests/test_organization.sql`, `tests/test_organization_extensions.sql` | Confirmed |
| REQ-016 | The system shall record a recruiter-to-client organisation mapping | `db/migrations/013` (`recruitment.recruiter_client_mapping`) | Implementation-Derived | Could | ACT-02, ACT-04 | BR-011 | FEAT-011 | WF-08 | SEC-002 | Mapping rows associate one recruiter user with one client organisation | `tests/test_organization_extensions.sql` | Confirmed |
| REQ-017 | The system shall allow an authorised recruiter or organisation administrator to post a job requirement with salary bounds, vacancy count, location, arrangement and required skills | `db/migrations/008_create_job_posting.sql`; `010` (`job_skill_requirement`) | Implementation-Derived | Must | ACT-02, ACT-04 | BR-012 | FEAT-012 | WF-03 | NFR-003, NFR-012 | Job posting row with status and `published_at`; salary fields satisfy the all-or-none constraint | `tests/test_job_posting.sql` | Confirmed |
| REQ-018 | The system shall support a structured job questionnaire and per-application question responses | `db/migrations/011_create_job_questionnaire.sql`; `recruitment.application_question_response` | Implementation-Derived | Should | ACT-02, ACT-01 | BR-013 | FEAT-013 | WF-03, WF-04 | DATA-004 | One questionnaire per job; responses reference application and question | `tests/test_job_questionnaire.sql:128-217` | Confirmed |
| REQ-019 | The system shall allow a candidate to apply to a published job exactly once | `db/migrations/009_create_candidate_application.sql:48-50` (`uq_candidate_application_candidate_job`) | Implementation-Derived | Must | ACT-01, ACT-02 | BR-014 | FEAT-014 | WF-04 | NFR-002, NFR-009 | Duplicate application for the same (candidate, job) is rejected | `tests/test_candidate_application.sql` | Confirmed |
| REQ-020 | The system shall record an application with its source, cover letter, screening answers and recruitment stage | `db/migrations/009_create_candidate_application.sql:1-80` | Implementation-Derived | Must | ACT-01, ACT-02, ACT-07 | BR-015 | FEAT-014 | WF-04, WF-05 | NFR-009, DATA-001 | Application row references profile and job; stage constrained to the seven permitted values | `tests/test_candidate_application.sql` | Confirmed |
| REQ-021 | The system shall record every change to an application's recruitment stage, with actor, previous value, new value and reason | `db/migrations/009_create_candidate_application.sql:82-210` (`application_status_history` + `trg_candidate_application_status_history`) | Implementation-Derived | Must | ACT-02, ACT-04 | BR-016 | FEAT-015 | WF-05 | NFR-009, SEC-003 | Any change of `application_status` writes a history row; the trigger fires on insert and update | `tests/test_candidate_application.sql` | Confirmed |
| REQ-022 | The system shall maintain the recruitment pipeline stage set (`applied`, `shortlisted`, `interviewed`, `offered`, `joined`, `rejected`, `withdrawn`) | `db/migrations/009_create_candidate_application.sql:51-62` | Implementation-Derived | Must | ACT-01, ACT-02, ACT-04 | BR-015 | FEAT-015 | WF-05 | DATA-001 | `application_status` CHECK constraint accepts exactly these seven values | `tests/test_candidate_application.sql` | Confirmed |
| REQ-023 | The system shall support job-feed matching of candidates to published jobs by role, city, arrangement and salary bounds | `db/queries/02_job_feed_matching.sql` | Implementation-Derived | Must | ACT-01, ACT-03 | BR-017 | FEAT-016 | WF-04 | NFR-002 | Query returns non-empty result on a representative dataset | `scripts/run_benchmarks.py` | Confirmed |
| REQ-024 | The system shall support a recruiter pipeline funnel aggregation by application stage | `db/queries/03_recruiter_pipeline_funnel.sql` | Implementation-Derived | Should | ACT-02, ACT-04 | BR-017 | FEAT-017 | WF-05 | NFR-003 | Query returns non-empty result on a representative dataset | `tests/test_golden_kpis.py` | Confirmed |
| REQ-025 | The system shall support agency consultants requesting to source for a job, and the employer accepting or declining that request | `db/migrations/016_create_sourcing_and_consultants.sql:45-108` | Implementation-Derived | Should | ACT-05, ACT-04 | BR-018 | FEAT-018 | WF-06 | SEC-002 | Request row per (job, consultant); `decided_at` present iff accepted or declined | `tests/test_sourcing.sql` | Confirmed |
| REQ-026 | The system shall permit a consultant to submit candidates only for jobs explicitly open to consultants | `db/migrations/016:110-133` (`trg_enforce_consultant_openness`) | Implementation-Derived | Must | ACT-05 | BR-019 | FEAT-018 | WF-06 | SEC-002 | Submission to a closed job raises an exception | `tests/test_sourcing.sql`; `tests/test_business_rules.sql:57-60` | Confirmed |
| REQ-027 | The system shall record a consultant's candidate submission and its progression to hired | `db/migrations/016:136-203` (`sourcing_submission`) | Implementation-Derived | Should | ACT-05, ACT-04 | BR-020 | FEAT-018 | WF-06 | NFR-009 | Submission row references job, candidate and consultant request; status constrained to five values | `tests/test_sourcing.sql` | Confirmed |
| REQ-028 | The system shall support batched outreach to candidates with per-recipient delivery state | `db/migrations/016:205-300` (`outreach_batch`, `outreach_recipient`) | Implementation-Derived | Should | ACT-05, ACT-02 | BR-021 | FEAT-024 | WF-06 | NFR-008 | Batch and recipient rows exist; recipient references the candidate and batch | `tests/test_sourcing.sql`; `db/queries/06_sourcing_outreach_unblocked.sql` | Confirmed |
| REQ-029 | The system shall allow a candidate to publish a gig-worker profile with services, rates and verification state | `db/migrations/014_create_gig_marketplace.sql:20-60` | Implementation-Derived | Must | ACT-01, ACT-03 | BR-022 | FEAT-025 | WF-07 | NFR-011 | Profile row references `core.user_account`; rating constrained to 1.00–5.00 | `tests/test_gig.sql` | Confirmed |
| REQ-030 | The system shall allow a corporate client to raise a gig request with deliverables, budget, pricing type and date window | `db/migrations/014:130-195` (`gig.gig_request`) | Implementation-Derived | Must | ACT-02, ACT-04 | BR-023 | FEAT-026 | WF-07 | NFR-003 | Request row with status constrained to five values; budget positive; `end_date >= start_date` | `tests/test_gig.sql` | Confirmed |
| REQ-031 | The system shall allow a gig worker to apply to a gig request, and the client to accept or reject | `db/migrations/014:197-260` (`gig.gig_application`) | Implementation-Derived | Must | ACT-03, ACT-04 | BR-024 | FEAT-026 | WF-07 | NFR-009 | Application row; `decided_at` present iff accepted or rejected | `tests/test_gig.sql` | Confirmed |
| REQ-032 | The system shall prevent a gig worker from holding two active assignments with overlapping date ranges | `db/migrations/014:316-321` (`ex_gig_assignment_no_overlap`) | Implementation-Derived | Must | ACT-02, ACT-01, ACT-03 | BR-025 | FEAT-027 | WF-07 | NFR-002, SEC-004 | Overlapping active assignment raises `ExclusionViolation` (23P01) | `tests/test_concurrency.py:151-207`; `tests/test_business_rules.sql` | Confirmed |
| REQ-033 | The system shall schedule gig assignments with agreed amount, dates and status, and support termination | `db/migrations/014:265-330` (`gig.gig_assignment`) | Implementation-Derived | Must | ACT-02, ACT-01, ACT-03 | BR-026 | FEAT-026 | WF-07 | NFR-009 | Assignment row; `assignment_status` ∈ {active, completed, terminated}; dates ordered | `tests/test_gig.sql` | Confirmed |
| REQ-034 | The system shall record gig ratings across quality and communication dimensions | `db/migrations/014:380-410` (`gig.gig_rating`) | Implementation-Derived | Could | ACT-02, ACT-01, ACT-03 | BR-027 | FEAT-028 | WF-07 | NFR-011 | Rating row with scores constrained to 1–5 | `tests/test_gig.sql` | Confirmed |

---

## 2. Business rules — `BR-###`

| ID | Rule | Source | Provenance | Priority | Actor(s) | REQ | Status |
|:--|:--|:--|:--|:--|:--|:--|:--|
| BR-001 | Email addresses are unique across all user accounts and stored in lowercase | `db/migrations/002:23-26` (`uq_user_account_email`, `ck_user_account_email_lowercase`) | Implementation-Derived | Must | ACT-01 | REQ-001 | Confirmed |
| BR-002 | A user may hold no more concurrent active sessions than the device entitlement of their active licence; a personal account defaults to 2 | `db/migrations/015:180-240` | Implementation-Derived | Must | ACT-01..ACT-08 | REQ-003, REQ-004 | Confirmed |
| BR-003 | A revoked session is terminal and cannot be reused; revocation writes an audit event | `db/migrations/015:295-330` | Implementation-Derived | Must | ACT-01, ACT-08 | REQ-006 | Confirmed |
| BR-004 | Consent state is recorded per subject and category and is queryable for disclosure decisions | `db/migrations/012:170-215` | Implementation-Derived | Should | ACT-01, ACT-08 | REQ-007 | Confirmed |
| BR-005 | Master reference data is read-only after seeding and carries no outbound foreign keys | `docs/phase-2-model/09-architecture.md:51` | Document-Derived | Must | ACT-08 | REQ-009 | Confirmed |
| BR-006 | A candidate profile carries exactly one visibility state governing who may discover it | `db/migrations/005` (`visibility`); `docs/phase-2-model/10-data-dictionary.md:110` | Implementation-Derived | Must | ACT-01, ACT-02 | REQ-010 | Confirmed |
| BR-007 | Profile completeness is derived from the presence of headline, summary, skills, education, experience, resume and projects, and is bounded to 0–100% | `db/migrations/010:245-271` | Implementation-Derived | Should | ACT-01 | REQ-011 | Confirmed |
| BR-008 | A candidate may have at most one active primary resume; only a resume may be marked primary | `db/migrations/006` | Implementation-Derived | Must | ACT-01, ACT-03 | REQ-012 | Confirmed |
| BR-009 | A skill claim carries a proficiency level and optional per-skill experience in years | `db/migrations/005`; `docs/phase-2-model/10-data-dictionary.md:120-122` | Implementation-Derived | Must | ACT-01 | REQ-013 | Confirmed |
| BR-010 | Candidate search honours profile visibility and the block rules in BR-021 | `db/queries/01`; `core.is_candidate_visible_to` | Implementation-Derived | Must | ACT-02, ACT-04, ACT-06 | REQ-014 | Confirmed |
| BR-011 | An organisation has one type, may have a hierarchy, and holds its own locations and legal identifiers | `db/migrations/007`; `013` | Implementation-Derived | Must | ACT-02, ACT-04, ACT-06 | REQ-015 | Confirmed |
| BR-012 | Salary fields are all-or-none: either all salary and currency and period fields are populated, or none are | `db/migrations/008:113-134` (`ck_job_posting_salary_currency`) | Implementation-Derived | Must | ACT-02, ACT-04 | REQ-017 | Confirmed |
| BR-013 | A job carries at most one questionnaire; a filled position requires a candidate answer | `db/migrations/011`; `tests/test_job_questionnaire.sql:211-217` | Implementation-Derived | Should | ACT-02, ACT-01 | REQ-018 | Confirmed |
| BR-014 | A candidate may hold at most one application to a given job | `db/migrations/009:48-50` | Implementation-Derived | Must | ACT-01 | REQ-019 | Confirmed |
| BR-015 | An application stage is one of the seven permitted values | `db/migrations/009:51-62` | Implementation-Derived | Must | ACT-01, ACT-02 | REQ-020, REQ-022 | Confirmed |
| BR-016 | Every stage change is captured in `application_status_history` with previous and new values; a change to the same value is not recorded | `db/migrations/009:158-210` | Implementation-Derived | Must | ACT-02, ACT-04 | REQ-021 | Confirmed |
| BR-017 | Funnel and feed aggregations are derived from the authoritative application and job tables, not from denormalised copies | `db/queries/02`, `03` | Implementation-Derived | Should | ACT-02, ACT-04 | REQ-023, REQ-024 | Confirmed |
| BR-018 | A consultant sourcing request is unique per (job, consultant); a decision is recorded iff the request is accepted or declined | `db/migrations/016:60-98` | Implementation-Derived | Should | ACT-05, ACT-04 | REQ-025 | Confirmed |
| BR-019 | A consultant may act only on a job whose consultant policy is open | `db/migrations/016:110-133` | Implementation-Derived | Must | ACT-05 | REQ-026 | Confirmed |
| BR-020 | A consultant may submit a given candidate to a given job only once | `db/migrations/016:150-151` | Implementation-Derived | Should | ACT-05 | REQ-027 | Confirmed |
| BR-021 | Outreach recipients are filtered against candidate block state before dispatch | `db/queries/06_sourcing_outreach_unblocked.sql` | Implementation-Derived | Should | ACT-05, ACT-02 | REQ-028 | Confirmed |
| BR-022 | A gig worker's verification state is one of unverified, verified or suspended | `db/migrations/014:55` | Implementation-Derived | Should | ACT-01, ACT-03 | REQ-029 | Confirmed |
| BR-023 | A gig request has a positive budget, a single currency, an ordered date window, and one pricing type | `db/migrations/014:161-177` | Implementation-Derived | Must | ACT-02, ACT-04 | REQ-030 | Confirmed |
| BR-024 | A gig application is decided iff it is accepted or rejected; `decided_at` is otherwise null | `db/migrations/014:246-255` | Implementation-Derived | Must | ACT-01, ACT-02 | REQ-031 | Confirmed |
| BR-025 | A gig worker may hold no two active assignments with overlapping `daterange` windows | `db/migrations/014:316-321` | Implementation-Derived | Must | ACT-01, ACT-02 | REQ-032 | Confirmed |
| BR-026 | A gig assignment may be active, completed or terminated; only active assignments are constrained against overlap | `db/migrations/014:312-321` | Implementation-Derived | Must | ACT-01, ACT-02 | REQ-033 | Confirmed |
| BR-027 | Gig ratings are scored 1–5 on quality and communication dimensions | `db/migrations/014:393-399` | Implementation-Derived | Could | ACT-01, ACT-02 | REQ-034 | Confirmed |

---

## 3. Security requirements — `SEC-###`

| ID | Requirement | Source | Priority | Actor(s) | REQ / BR | Acceptance criterion | Verification | Status |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| SEC-001 | Access to data shall be governed by a role and permission model | `db/migrations/012:23-79` (`core.role`, `core.permission`, `core.role_permission`); `docs/phase-2-model/12-threat-model.md:85-94` | Must | ACT-01..ACT-08 | REQ-001 | Roles are assigned to users; permissions are assigned to roles; both are enforced on access | `tests/test_access_control.sql`, `tests/test_administration.sql` | **Confirmed** — 28 permissions and 99 role mappings are seeded (migration 021) and tested per role. Row access is enforced by RLS through `core.is_platform_admin()`; the fine-grained permission codes are checked by the application, not by the database. |
| SEC-002 | Tenant and consultant scope shall be enforced so a recruiter sees only their own organisation's data and a consultant only open jobs | `db/migrations/016:110-133`; `core.is_candidate_visible_to`; `docs/phase-2-model/12-threat-model.md:100-142` | Must | ACT-02, ACT-04, ACT-05 | REQ-015, REQ-025, REQ-026 | A recruiter cannot read another organisation's job; a consultant cannot submit to a closed job | `tests/test_access_control.sql`, `tests/test_sourcing.sql`, `tests/test_administration.sql:154-181`, `tests/test_candidate_privacy.sql` | **Confirmed** — the consultant rule is a trigger; organisation isolation is row-level security (60 policies, migrations 021, 022, 030) across organisation, commercial, candidate and messaging tables, tested as the application role. |
| SEC-003 | Security-relevant actions shall be written to an append-only audit log | `db/migrations/012:230-293` (`audit.audit_event` + anti-tamper trigger) | Must | ACT-01, ACT-02, ACT-04, ACT-05, ACT-06, ACT-08 | REQ-006, REQ-021 | `UPDATE`/`DELETE` on `audit.audit_event` raises an exception; the action is recorded | `tests/test_administration.sql:208-227`, `tests/test_lifecycle.sql`, `tests/test_domains_and_transitions.sql`, `tests/test_audit_coverage.sql` | **Confirmed** — all 14 sensitive action classes are evidenced (21 action codes, 13 audit triggers, 6 writing functions; migration 029); see [`05-audit-event-matrix.md`](05-audit-event-matrix.md) |
| SEC-004 | Concurrent conflicting writes to a gig calendar shall be rejected at the storage layer | `db/migrations/014:316-321` | Must | ACT-03, ACT-04 | REQ-032 | Overlap raises `ExclusionViolation` before commit | `tests/test_concurrency.py:151-207` | Confirmed |
| SEC-005 | Financial and download-history records shall be immutable after write | `db/migrations/017:374-377`, `017:443-446`, `012:290-293` | Must | ACT-06, ACT-08 | REQ-033 | `UPDATE`/`DELETE` raises; correction is a new self-referencing row | `tests/test_commercial.sql`, `tests/test_administration.sql:214-227` | Confirmed — **but `TRUNCATE` is not blocked** (`docs/phase-2-model/12-threat-model.md:228`) |
| SEC-006 | Passwords shall be stored as salted hashes and the algorithm recorded | `db/migrations/012:85` (`algorithm` DEFAULT `'argon2id'`); `002:56-60` | Must | ACT-01..ACT-08 | REQ-002 | Stored hash matches `^\$(argon2id\|2b\|2a)\$` | `tests/test_access_control.sql`, `scripts/validate_data.py` | **Confirmed** — `ck_user_credential_password_hash_format` and `ck_user_account_password_hash_format` (migration 021) reject any password hash that is not argon2id or bcrypt |
| SEC-007 | Session tokens shall be stored hashed | `db/migrations/002:139,157-158` | Must | ACT-01..ACT-08 | REQ-003 | `session_token_hash` is a hash, not a token | `tests/test_access_control.sql`, `tests/test_identity.sql` | **Confirmed** — `ck_user_session_token_hash_sha256` (migration 021) requires 64 lowercase hex characters |
| SEC-008 | Login attempts exceeding the device entitlement shall be refused and recorded | `db/migrations/015:220-240` | Must | ACT-01..ACT-08 | REQ-004 | Function returns NULL; a `device.limit_exceeded` audit event is written | `tests/test_licences.sql:134-144`; `tests/test_concurrency.py` | Confirmed |
| SEC-009 | Uploaded documents shall be size- and type-constrained and integrity-checked | `db/migrations/006` | Must | ACT-01, ACT-03 | REQ-012 | Oversized or unsupported MIME types are rejected; SHA-256 checksum stored | `tests/test_candidate_document.sql:121-147` | Confirmed |
| SEC-010 | Candidates shall be able to block, and be blocked by, users and organisations, and visibility checks shall honour that | `db/migrations/012:336-388` (`core.is_candidate_visible_to`) | Must | ACT-01, ACT-02, ACT-04 | REQ-010 | Visibility flips false on block and back on unblock; third parties unaffected | `tests/test_administration.sql:154-181` | Confirmed — **function-scoped**: applies only to callers of that function, not to every read path |
| SEC-011 | Consent and privacy preference state shall be queryable to support disclosure decisions | `db/migrations/012:170-215`; `018` | Should | ACT-01, ACT-03, ACT-08 | REQ-007 | Consent rows exist per category with state and timestamp | `tests/test_administration.sql`, `tests/test_audit_coverage.sql`, `tests/test_candidate_privacy.sql` | Confirmed |
| SEC-012 | PII columns shall carry a sensitivity classification | `docs/phase-2-model/10-data-dictionary.md:9-15`; `docs/phase-2-model/11-rule-compliance.md:18` | Should | ACT-08 | REQ-010, REQ-012 | Every documented column carries `[PUBLIC]`/`[INTERNAL]`/`[PERSONAL]`/`[SENSITIVE]` | `tests/test_classification.sql` | **Confirmed** — every column of every base table is classified in `audit.column_classification` (migration 024), and a test fails when a column is added without one. All rows are pattern-based; none is human-reviewed yet. |
| SEC-013 | Data access to sensitive candidate fields shall be masked for unauthorised viewers | `docs/phase-2-model/12-threat-model.md:47,254` | Should | ACT-01, ACT-02, ACT-04 | REQ-010 | An unauthorised viewer sees masked phone/email | `tests/test_access_control.sql` | **Confirmed for support staff** — `core.mask_email`, `core.mask_phone` and `core.support_user_account` mask contact data (migration 021). Recruiters are governed by visibility and row-level security (`core.can_view_candidate`), not by masking: a design choice (DEC-31). |
| SEC-014 | Least-privilege database roles and row-level security shall separate application, reporting and administration access | `docs/phase-2-model/12-threat-model.md:55-81,100` | Should | ACT-08 | REQ-001 | `talentra_app` holds no UPDATE/DELETE on ledgers; `talentra_reporting` cannot read `core`/`commercial` | `tests/test_access_control.sql` | **Confirmed** — five NOLOGIN roles with grants, RLS policies on twelve tables, append-only enforcement and TRUNCATE blocking (migrations 021, 022), each tested by acting as the role. The application's own login role is created per environment. |

---

## 4. Data requirements — `DATA-###`

| ID | Requirement | Source | Priority | Actor(s) | Acceptance criterion | Verification | Status |
|:--|:--|:--|:--|:--|:--|:--|:--|
| DATA-001 | Enumerated business states shall be stored as constrained codes, not free text | `db/migrations/009:51-62`; `008:84-89`; `014:178-186,238-244,312-313`; `016:84-89,183-192`; `002:43-50`; `017:93-94,146-156,205-206,314-322` | Must | ACT-08 | Every state column has a CHECK constraint listing its permitted values | `scripts/validate_data.py` (RG3); `tests/test_constraints.sql` | Confirmed |
| DATA-002 | Missing data shall be represented strictly as SQL NULL, with no sentinel strings or numbers | `docs/phase-2-model/11-rule-compliance.md:17,73-76`; `docs/phase-2-model/09-architecture.md:149` | Must | ACT-08 | No `'NA'`, `'NONE'`, `'NULL'`, `'UNKNOWN'`, `-1`, `0` or `9999` used as a missing-value sentinel | `scripts/validate_data.py` (RG5) | Confirmed |
| DATA-003 | All instant-valued timestamps shall be timezone-aware and normalised to UTC; calendar dates shall use `DATE` | `docs/phase-2-model/09-architecture.md:148`; `docs/phase-2-model/11-rule-compliance.md:16` | Must | ACT-08 | No timezone-naive `TIMESTAMP` column; no `TIMESTAMP WITHOUT TIME ZONE` in any DDL | `scripts/validate_data.py` (RG4) | Confirmed — 9 `DATE` columns are by design |
| DATA-004 | Free-text business payloads shall be length-bounded | `db/migrations/009:78-80` (cover letter ≤ 10 000); `012:99` (reason 2–500) | Should | ACT-08 | No unbounded user-supplied text column | `tests/test_constraints.sql` | Confirmed |
| DATA-005 | All operational tables shall use a surrogate identity primary key named `id` | `docs/phase-2-model/11-rule-compliance.md:14`; `docs/phase-2-model/09-architecture.md:146` | Must | ACT-08 | Every operational table's PK is `BIGINT GENERATED ALWAYS AS IDENTITY` named `id` | `scripts/validate_data.py` (RG2) | Confirmed — 4 `analytics.dim_*` use `*_key`; the partitioned table uses `(id, applied_at)` by design |
| DATA-006 | Referential integrity shall be enforced by foreign keys with explicit delete behaviour | `db/migrations/001`–`019` | Must | ACT-08 | Every relationship carries an FK with a stated `ON DELETE` rule | `scripts/validate_data.py` (RG1/RG2) | Confirmed |
| DATA-007 | Names and identifiers shall follow canonical formats (lowercase RFC email, E.164 phone, ISO 4217 currency, ISO 3166 country) | `db/migrations/002:31,41-46`; `008:113-134`; `docs/phase-2-model/11-rule-compliance.md:15` | Must | ACT-08 | Format CHECK constraints reject non-conforming values | `scripts/validate_data.py` (RG3) | Confirmed |
| DATA-008 | Sensitive personal data shall be classified in the data dictionary | `docs/phase-2-model/10-data-dictionary.md:9-15` | Should | ACT-08 | All 95 tables classified | `tests/test_classification.sql` | **Confirmed** — see SEC-012; the dictionary is generated from the database (`docs/phase-2-model/07-attribute-catalogue.md`) |

---

## 5. Operational requirements — `OPS-###`

| ID | Requirement | Source | Priority | Actor(s) | Acceptance criterion | Verification | Status |
|:--|:--|:--|:--|:--|:--|:--|:--|
| OPS-001 | The database shall be created and seeded by ordered, idempotent migration scripts | `db/migrations/001`–`019`; `README.md:101-107` | Must | ACT-08 | Applying 001→019 in order against an empty database succeeds | `.github/workflows/ci.yml` applies every migration to an empty PostgreSQL 17; applied clean on 16.15 on 2026-10-27 (25 of 25) | Confirmed |
| OPS-002 | The schema shall be delivered as a reproducible containerised environment | `docker-compose.yml` | Must | ACT-08 | `docker-compose up -d` yields a PostgreSQL 17 instance with all 10 schemas | `docker-compose.yml`, `README.md:95-99` | Confirmed |
| OPS-003 | Session revocation shall be invocable as a database function with an audit trail | `db/migrations/012:295-330` | Must | ACT-08 | Calling `core.revoke_user_session` ends the session and writes an audit event | `tests/test_licences.sql:161` | Confirmed |
| OPS-004 | The system shall provide a logical backup and restore-and-verify runbook | `scripts/backup_restore.sh` | Must | ACT-08 | Backup → restore into `talentra_recovery_test` → row-count parity → drop completes within the stated threshold | `scripts/backup_restore.sh` | Confirmed — executed 2026-10-27 on PostgreSQL 16.15 at medium scale: 102 tables compared with 0 mismatches, objects equal, restore 1 s |
| OPS-005 | Analytical marts shall be refreshable on demand | `db/migrations/019:308-315` (`analytics.refresh_reporting_marts`) | Should | ACT-08 | The procedure completes without error against a populated mart | `tests/test_analytics.sql`, `tests/test_golden_kpis.py`, `tests/test_integration_maintenance.sql` | **Confirmed** — `analytics.refresh_reporting_marts` loads the dimensions and facts and refreshes the views (migration 023); `core.run_maintenance()` calls it and the `maintenance` service in `docker-compose.yml` schedules it |
| OPS-006 | The system shall provide a repeatable benchmark harness producing latency percentiles and cache-hit ratios | `scripts/run_benchmarks.py`; `benchmarks/results/benchmark_results.json` | Should | ACT-08 | The harness runs 12 queries and emits p50/p95/p99 with a result-validity marker | `scripts/run_benchmarks.py`, `tests/test_benchmark_harness.py` | Confirmed — all 12 queries return valid non-empty results on the medium dataset (`benchmarks/results/benchmark_summary_v2.md`) |
| OPS-007 | The system shall provide an automated data-quality validator covering the ten rule groups | `scripts/validate_data.py`; `docs/phase-2-model/11-rule-compliance.md` | Should | ACT-08 | The validator reports 15/15 checks passing on the seeded dataset | `scripts/validate_data.py` | Confirmed — 15 of 15 pass on a freshly seeded database; CI runs it after seeding |
| OPS-008 | The schema shall be verified by an executable test suite covering identity, tenancy, commerce, gig, sourcing, messaging, analytics and concurrency | `tests/` (21 SQL + 2 Python) | Must | ACT-08 | The suite runs green against a seeded database | `scripts/run_all_tests.py` | Confirmed — executed 2026-10-27: all suites pass on PostgreSQL 16.15 |
| OPS-009 | High-volume application data shall have a declared scale-out path | `db/migrations/019:336-350` (`candidate_application_partitioned`, annual `RANGE (applied_at)`) | Should | ACT-08 | The partitioned table exists with one partition per calendar year and a compound PK | `tests/test_analytics.sql`; `scripts/validate_data.py` (RG10) | Confirmed — **but no benchmark query targets it** (`docs/phase-2-model/09-architecture.md:91`), and the authoritative table remains the unpartitioned `recruitment.candidate_application` |
| OPS-010 | The platform shall run on a single containerised PostgreSQL 17 service | `docker-compose.yml` | Must | ACT-08 | One service, one volume, no external dependencies | `docker-compose.yml` | Confirmed — **note**: single-service means no replication, no PITR, no failover (`docs/phase-2-model/12-threat-model.md:253`) |

---

## 6. Non-functional requirements — `NFR-###`

Full register with numeric targets, measurement methods, acceptance criteria, provenance and approval status:
**[`docs/phase-1-discover/04-nfr-register.md`](04-nfr-register.md)**. This file holds only the ID-to-requirement binding so that the
requirement register remains the single place a requirement is stated.

| ID | Requirement | Actor(s) | REQ / BR / SEC | Status |
|:--|:--|:--|:--|:--|
| NFR-001 | Candidate search shall return within the declared latency envelope at the declared workload | ACT-02, ACT-04, ACT-06 | REQ-014 | Delegated Decision; Met — evidence in [`04-nfr-register.md`](04-nfr-register.md) |
| NFR-002 | Authenticated reads shall complete within the declared latency envelope | ACT-01..ACT-08 | REQ-003, REQ-004, REQ-014, REQ-019, REQ-032 | Delegated Decision; Met — evidence in [`04-nfr-register.md`](04-nfr-register.md) |
| NFR-003 | Transactional writes shall complete within the declared latency envelope | ACT-02, ACT-04 | REQ-017, REQ-024, REQ-030 | Delegated Decision; Met — evidence in [`04-nfr-register.md`](04-nfr-register.md) |
| NFR-004 | Analytical queries shall complete within the declared latency envelope | ACT-02, ACT-08 | REQ-024 | Delegated Decision; Met — evidence in [`04-nfr-register.md`](04-nfr-register.md) |
| NFR-005 | The platform shall sustain a declared concurrent-user level | ACT-01..ACT-08 | REQ-014, NFR-002 | Delegated Decision; Met (500 sessions, at most 80 connections in flight) — evidence in [`04-nfr-register.md`](04-nfr-register.md) |
| NFR-006 | Reference-data reads shall complete within the declared latency envelope | ACT-01..ACT-08 | REQ-009 | Delegated Decision; Met — evidence in [`04-nfr-register.md`](04-nfr-register.md) |
| NFR-007 | The platform shall meet a declared availability objective | ACT-01..ACT-08 | OPS-002 | Delegated Decision; Database side met; needs an operator — evidence in [`04-nfr-register.md`](04-nfr-register.md) |
| NFR-008 | Outbound messaging shall be delivered within a declared window | ACT-01, ACT-02 | REQ-028 | Delegated Decision; Database side met; needs the sender — evidence in [`04-nfr-register.md`](04-nfr-register.md) |
| NFR-009 | Recruitment pipelines shall be queryable at the declared volume | ACT-02, ACT-04 | REQ-020, REQ-021, REQ-027, REQ-031, REQ-033 | Delegated Decision; Met — evidence in [`04-nfr-register.md`](04-nfr-register.md) |
| NFR-010 | The platform shall meet a declared recovery time objective | ACT-08 | OPS-004 | Delegated Decision; Met — evidence in [`04-nfr-register.md`](04-nfr-register.md) |
| NFR-011 | The platform shall meet a declared recovery point objective | ACT-08 | OPS-004 | Delegated Decision; Needs an operator to schedule backups — evidence in [`04-nfr-register.md`](04-nfr-register.md) |
| NFR-012 | Financial ledgers shall reconcile to the stored balance with zero discrepancy | ACT-06, ACT-08 | REQ-017, REQ-033, SEC-005 | Delegated Decision; Met — evidence in [`04-nfr-register.md`](04-nfr-register.md) |
| NFR-013 | Consent and block state shall be enforced on every read path that touches candidate PII | ACT-01, ACT-02 | REQ-007, SEC-010 | Delegated Decision; Met — evidence in [`04-nfr-register.md`](04-nfr-register.md) |
| NFR-014 | Credentials shall be stored using a cryptographically approved hash | ACT-01..ACT-08 | REQ-002, SEC-006 | Delegated Decision; Met — evidence in [`04-nfr-register.md`](04-nfr-register.md) |
| NFR-015 | Data quality shall meet a declared compliance rate | ACT-08 | DATA-001..DATA-008 | Delegated Decision; Met — evidence in [`04-nfr-register.md`](04-nfr-register.md) |
| NFR-016 | Sensitive actions shall be auditable at a declared coverage | ACT-08 | SEC-003 | Delegated Decision; Met (14 of 14 classes) — evidence in [`04-nfr-register.md`](04-nfr-register.md) |
| NFR-017 | Personal data shall be retained for a declared period and then removed | ACT-08 | REQ-007, SEC-011 | Delegated Decision; Met — evidence in [`04-nfr-register.md`](04-nfr-register.md) |
| NFR-018 | The platform shall meet a declared data-protection obligation | ACT-01, ACT-02, ACT-08 | SEC-006, SEC-010, SEC-011, SEC-012 | Delegated Decision; Met — evidence in [`04-nfr-register.md`](04-nfr-register.md) |
| NFR-019 | The platform shall meet a declared accessibility conformance level | ACT-01, ACT-02 | — | **Scope decision required** (see [`docs/phase-1-discover/01-scope-assumptions.md`](01-scope-assumptions.md) **OQ-004**) |
| NFR-020 | Analytical marts shall be refreshed within a declared staleness window | ACT-08 | OPS-005 | Delegated Decision; Met by construction — evidence in [`04-nfr-register.md`](04-nfr-register.md) |
| NFR-021 | The platform shall meet a declared regulatory obligation | ACT-08 | SEC-006, SEC-014, NFR-018 | Delegated Decision; Met — evidence in [`04-nfr-register.md`](04-nfr-register.md) |
| NFR-022 | The platform shall be reproducible from a clean checkout | ACT-08 | OPS-001, OPS-002, OPS-008 | Delegated Decision; Met locally; CI unrun — evidence in [`04-nfr-register.md`](04-nfr-register.md) |
| NFR-023 | The platform shall remain portable across supported PostgreSQL versions | ACT-08 | OPS-010 | Delegated Decision; Boundary — evidence in [`04-nfr-register.md`](04-nfr-register.md) |
| NFR-024 | The platform shall be maintainable, measured by a declared documentation-coverage ratio | ACT-08 | DATA-008, SEC-012 | Delegated Decision; Met — evidence in [`04-nfr-register.md`](04-nfr-register.md) |
| NFR-025 | The platform shall operate within a declared resource envelope | ACT-08 | OPS-002 | Delegated Decision; Boundary (measured to 1M candidates, projected beyond) — evidence in [`04-nfr-register.md`](04-nfr-register.md) |
| NFR-026 | The platform shall produce observable operational telemetry | ACT-08 | OPS-005, OPS-006, NFR-020 | Delegated Decision; Met by construction — evidence in [`04-nfr-register.md`](04-nfr-register.md) |
| NFR-027 | The platform shall detect and isolate a failing integration boundary | ACT-08 | SEC-008, OPS-003 | Delegated Decision; Met — evidence in [`04-nfr-register.md`](04-nfr-register.md) |

---

## 7. Source-to-requirement traceability

### 7.1 Docket sentence mapping — **NOT VERIFIABLE**

The completion rule for Step 1 requires every sentence of the brief to map to a requirement ID or an explicit
out-of-scope line. **The brief is unavailable**, so a sentence-level mapping table cannot be produced.
**This sub-deliverable is NOT VERIFIED** and is not counted as complete.

The nearest available substitute — and it is explicitly *not* a substitute — is the mapping from the
repository's own functional artifacts to requirement IDs:

| Source artifact | Mapped requirement IDs | Unmapped statements |
|:--|:--|:--|
| `core` schema + `create_session_with_device_limit` + `revoke_user_session` | REQ-001…REQ-008, BR-001…BR-004, SEC-001, SEC-002, SEC-003, SEC-006, SEC-007, SEC-008 | — |
| `master` schema + seed | REQ-009, BR-005 | — |
| `profile` schema (005, 006, 010) | REQ-010…REQ-013, BR-006…BR-009, DATA-002, DATA-004 | — |
| `recruitment` schema (007, 008, 009, 010, 011, 013) | REQ-015…REQ-024, BR-010…BR-017, DATA-001 | — |
| `sourcing` schema (016) | REQ-025…REQ-028, BR-018…BR-021 | — |
| `gig` schema (014) | REQ-029…REQ-034, BR-022…BR-027, SEC-004 | — |
| `commercial` schema (015, 017) | REQ-004, REQ-005, BR-002, BR-003, BR-012, SEC-005, SEC-008, NFR-010, NFR-011, NFR-012 | — |
| `messaging` schema (018) | REQ-007, SEC-011 | — |
| `audit` schema (012) | SEC-003, SEC-005, NFR-016 | — |
| `analytics` schema (019) | OPS-005, OPS-009, NFR-020, NFR-024 | — |
| 12 benchmark queries | REQ-014, REQ-023, REQ-024, REQ-028, NFR-001…NFR-004, NFR-009 | — |
| 21 SQL + 2 Python test suites | All REQ/BR/SEC above (test-as-acceptance) | — |

**Unmapped source statements: 0 within the repository's own artifacts.** The only unmapped external
statement is the brief itself (S-001), which is unavailable — recorded as **OQ-001**.

### 7.2 Conflicts between the brief (unavailable) and the implementation

Because the brief is unavailable, a conflict analysis is not possible. What **can** be stated is a conflict
analysis between the *implementation* and the *existing documentation*, which the Phase 1 brief requires
regardless. The material ones, carried forward from the Phase 2C/2D/2E audits, are:

| # | Conflict | Evidence | Carried in |
|:--|:--|:--|:--|
| CF-01 | Docs describe a cross-domain ACID guarantee "under 2 ms"; no benchmark measures it and no filled-headcount counter exists | `docs/phase-2-model/09-architecture.md:38`; `README.md:194` (corrected in Phase 2D/2E) | Phase 2D A1, D7 |
| CF-02 | Docs describe RLS and least-privilege roles as deployed; no `CREATE POLICY`/`CREATE ROLE` exists | `docs/phase-2-model/12-threat-model.md:55,100` | Phase 2D T2, T14 |
| CF-03 | Docs claim `core.user_block` "prevents" profile queries; enforcement is function-scoped | `docs/phase-2-model/12-threat-model.md:47` | Phase 2D T9 |
| CF-04 | Docs describe background-check storage columns that do not exist | `docs/phase-4-platform/22-integration-boundaries.md:88` | Phase 2E §3.4 |
| CF-05 | Docs claim "PCI-DSS zero-storage compliance"; no SAQ exists | `docs/phase-4-platform/22-integration-boundaries.md:46` | Phase 2E D3 |
| CF-06 | Docs claim partition pruning percentages; no measurement exists | `docs/phase-2-model/09-architecture.md:91`; `docs/phase-1-discover/03-competitive-benchmark.md:16` | Phase 2D A4, C4 |
| CF-07 | Benchmark artefact still labels its §2 "Targeted Index Optimization Impact" with a "Speedup Factor" column, contradicting the relabelled report | `benchmarks/results/*` vs `docs/phase-4-platform/28-performance-report.md` §2 | Phase 2E U-08 |
| CF-08 | Benchmark artefact records no dataset row counts, so the "medium preset" scale claim is uncorroborated | `benchmarks/results/benchmark_results.json` | Phase 2E U-05 |
| CF-09 | `docs/phase-2-model/09-er-diagram.md` was never audited for the column-level drift found in the data dictionary | — | Phase 2E U-07 |
| CF-10 | A benchmark-script docstring references a non-existent report filename | `scripts/run_benchmarks.py:12` | Phase 2E U-10 |

---

## 8. Coverage report

### 8.1 Requirement counts by type

| Type | Total | Confirmed | Documented | Partial | Proposed | Unresolved |
|:--|--:|--:|--:|--:|--:|--:|
| REQ (functional) | 34 | 34 | 0 | 0 | 0 | 0 |
| BR (business rules) | 27 | 27 | 0 | 0 | 0 | 0 |
| SEC (security) | 14 | 11 | 0 | 3 | 0 | 0 |
| DATA | 8 | 8 | 0 | 0 | 0 | 0 |
| OPS | 10 | 9 | 0 | 1 | 0 | 0 |
| NFR | 27 | 0 | 0 | 0 | 26 | 1 |
| **Total** | **120** | **89** | **0** | **4** | **26** | **1** |

> **Counting rule.** A row whose `Status` cell begins with a qualified form (`Confirmed — but …`,
> `Partial — …`, `Proposed, not implemented — …`) is counted under its **leading** status keyword, and the
> qualification is carried in the row itself rather than in a separate column. `Documented only` is counted
> under `Documented`; `Not implemented` is counted under `Proposed`, because it is a statement of intent with
> no implementation, not a `Documented` row. NFR-019 is the single `Unresolved` row: it cannot be settled
> until the scope decision in **OQ-004** is made.

**Note on the SEC/NFR "Proposed" count.** Security requirements that read "not implemented" or "proposed"
in `docs/phase-2-model/12-threat-model.md` are counted as **Proposed** because the *requirement* is a valid statement of
intent that lacks a verified implementation. The underlying gaps are catalogued in
[`docs/phase-1-discover/phase-report.md`](phase-report.md) §6 and in the audit-event matrix.

### 8.2 Requirement-to-actor coverage

| Measure | Value |
|:--|:--|
| Requirements with ≥1 actor | **120 / 120 = 100%** |
| Requirements with no actor | 0 |
| Distinct actors referenced | 8 (`ACT-01`…`ACT-08`) |

Computed from the `Actor(s)` columns in §1–§6 of this file. Every requirement row names at least one actor.
No requirement is actor-less; system-only behaviour is attributed to `ACT-08` (Platform Operations).
`ACT-09` (Payment Gateway) is deliberately **not** referenced by any requirement: it is an external
boundary, not a requirement owner — see [`docs/phase-1-discover/02-personas.md`](02-personas.md) §2.

### 8.3 Requirement-to-workflow coverage

| Measure | Value |
|:--|:--|
| Functional + business rules mapped to ≥1 workflow | 34 REQ + 27 BR = **61 / 61 = 100%** |
| Security requirements referenced by ≥1 workflow | **10 / 14** — SEC-009, SEC-012, SEC-013 and SEC-014 are referenced by no workflow (SEC-009 is enforced by CHECK constraints inside WF-02's document step and SEC-012/013/014 constrain the whole system rather than one flow) |
| Data / operational / quality requirements referenced | 4 DATA, 8 OPS, 13 NFR — see [`docs/phase-1-discover/05-workflows.md`](05-workflows.md) §5 |
| Requirements not workflow-mapped | 4 SEC, 4 DATA, 2 OPS, 14 NFR — quality, data and operational constraints that constrain workflows rather than constitute one |
| Must-have features mapped to ≥1 workflow | **23 / 23 = 100%** (union of MoSCoW `Must` and class `Must-have`; see [`docs/phase-1-discover/03-feature-inventory.md`](03-feature-inventory.md) §4 and [`docs/phase-1-discover/05-workflows.md`](05-workflows.md) §3) |

### 8.4 Unmapped source statements

| Source | Unmapped | Reason |
|:--|:--|:--|
| Repository implementation artefacts | **0** | Every schema domain, benchmark query and test suite is mapped in §7.1 |
| Hackathon docket (S-001) | **All** | Unavailable — **OQ-001** |
| Lifecycle playbook (S-002) | **All** | Unavailable — the gate definition is assumed (**A-001**) |

### 8.5 Requirement ID uniqueness

120 IDs across 6 prefixes, verified by script — see [`docs/phase-1-discover/phase-report.md`](phase-report.md) §7.2. **No duplicates, no gaps in numbering.**

---

## 9. Related documents

| Document | Contains |
|:--|:--|
| [`docs/phase-1-discover/01-scope-assumptions.md`](01-scope-assumptions.md) | Scope, exclusions, assumptions, ambiguities, open questions, decisions |
| [`docs/phase-1-discover/02-personas.md`](02-personas.md) | Actor inventory, persona cards, role-permission reconciliation |
| [`docs/phase-1-discover/03-feature-inventory.md`](03-feature-inventory.md) | Feature register with priorities and classification |
| [`docs/phase-1-discover/04-nfr-register.md`](04-nfr-register.md) | NFR register with numeric targets and test methods |
| [`docs/phase-1-discover/05-workflows.md`](05-workflows.md) | 14 core business workflows |
| [`docs/phase-1-discover/05-exceptions.md`](05-exceptions.md) | Exception catalogue |
| [`docs/phase-6-specify/34-traceability-matrix.md`](../phase-6-specify/34-traceability-matrix.md) | Cross-register traceability matrices |
| [`docs/phase-1-discover/05-audit-event-matrix.md`](05-audit-event-matrix.md) | Sensitive action → audit event coverage |
| [`docs/phase-1-discover/phase-report.md`](phase-report.md) | Phase 1 completion report and G1 decision |
| [`docs/source/README.md`](../source/README.md) | Source index and provenance rules |
