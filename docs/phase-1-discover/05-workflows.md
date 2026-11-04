# Talentra — Core Business Workflows

**Phase:** 1 — Discover, Step 5
**Status:** **Reconciled against the docket** on 2026-10-23 ([`01-docket-reconciliation.md`](01-docket-reconciliation.md)); originally written before the docket was available. Workflows are derived from the implemented schema and checked against it by `scripts/lifecycle/gen_workflow_coverage.py`.
**Authored:** 2026-10-21

---

## 1. Method

Twenty-one workflows (WF-15 to WF-21 added 2026-10-28 for parts of the system no earlier workflow covered). Each is described with the **14 mandated attributes**:

1. **ID and name**
2. **Trigger** — what starts it
3. **Actors** — who participates
4. **Preconditions** — what must already be true
5. **Triggering event**
6. **Main flow** — the ordered steps
7. **Alternative flows** — every branch other than the happy path
8. **Postconditions** — what is true when it ends
9. **Data objects affected**
10. **State machine / transitions**
11. **Business rules enforced**
12. **Exceptions** — linked to [`docs/phase-1-discover/05-exceptions.md`](05-exceptions.md)
13. **Requirements covered**
14. **Features covered** — linked to [`docs/phase-1-discover/03-feature-inventory.md`](03-feature-inventory.md)

**Derivation basis.** No workflow is described in prose anywhere in the repository. Each is reconstructed from
the schema: the tables it touches, the CHECK constraints that bound its states, the triggers that fire
mid-flow, and the functions it calls. Where a step would require application code that does not exist, it is
marked **[app-layer]** — an honest statement that the step is out of this repository's scope, not a claim
that the step works.

**Exception reference.** `EXC-NNN` identifiers refer to [`docs/phase-1-discover/05-exceptions.md`](05-exceptions.md). Every
workflow below has at least one exception path; no workflow is happy-path-only.

---

## 2. Workflow inventory

| ID | Workflow | Primary actor | State machine | Exceptions |
|:--|:--|:--|:--|:--|
| WF-01 | User registration and authentication | ACT-01 | `core.user_account.account_status` | EXC-01, EXC-02, EXC-03, EXC-04 |
| WF-02 | Candidate profile creation and completion | ACT-01 | `profile.candidate_profile.profile_status` | EXC-05, EXC-06, EXC-07 |
| WF-03 | Job posting creation and publication | ACT-02, ACT-04 | `recruitment.job_posting.job_status` | EXC-08, EXC-09, EXC-10, EXC-11 |
| WF-04 | Candidate discovery and job application | ACT-02, ACT-01 | `recruitment.candidate_application.application_status` | EXC-12, EXC-13, EXC-14 |
| WF-05 | Recruitment pipeline management | ACT-02 | `application_status` (7 states) | EXC-15, EXC-16, EXC-17 |
| WF-06 | Agency consultant sourcing | ACT-05 | `consultant_sourcing_request_status` + `sourcing_submission_status` | EXC-18, EXC-19, EXC-20 |
| WF-07 | Gig marketplace engagement | ACT-03, ACT-04 | `gig_request_status` + `gig_application_status` + `gig_assignment_status` | EXC-21, EXC-22, EXC-23, EXC-24 |
| WF-08 | Organisation and member administration | ACT-06 | `recruitment.organization.status` + `organization_member.status` | EXC-25, EXC-26 |
| WF-09 | Licensing, subscription and entitlements | ACT-06 | `subscription_status` + `licence_status` + `payment_order_status` | EXC-27, EXC-28, EXC-29 |
| WF-10 | Session management and revocation | ACT-01 | `core.user_session.ended_at` / `revoked_at` | EXC-30, EXC-31 |
| WF-11 | Notification, consent and privacy management | ACT-01 | `notification_delivery_status` | EXC-32, EXC-33 |
| WF-12 | Platform operations, validation and backup | ACT-08 | — (operational) | EXC-34, EXC-35, EXC-36 |
| WF-13 | Analytical mart refresh | ACT-08 | — (operational) | EXC-37 |
| WF-14 | Profile download and credit consumption | ACT-02 | `commercial.wallet.balance` | EXC-38, EXC-39, EXC-40 |
| WF-15 | Integration exchange with an external system | ACT-08 | `messaging.integration_event.event_status` | EXC-41 |
| WF-16 | Scheduled maintenance, retention and erasure | ACT-08 | — (operational) | EXC-37, EXC-42 |
| WF-17 | Administrative support and impersonation | ACT-08 | `messaging.support_ticket.ticket_status` | EXC-43 |
| WF-18 | Candidate development: courses, assessments and resume templates | ACT-01, ACT-03 | `course_enrolment.enrolment_status` | EXC-44 |
| WF-19 | Recruiter search, bookmarks and profile views | ACT-02 | — | EXC-12, EXC-39 |
| WF-20 | Community, support and referrals | ACT-01, ACT-03 | `support_ticket.ticket_status` | EXC-45 |
| WF-21 | Reference data and rule maintenance | ACT-08 | — (operational) | EXC-34 |

---

## 3. Gate G1 Condition 3 — must-have feature coverage

Every Must-have feature must appear in at least one workflow. The scored set is the **union** of the two
vocabularies used in [`docs/phase-1-discover/03-feature-inventory.md`](03-feature-inventory.md): the MoSCoW priority `Must` (22
features) and the feature class `Must-have` (17 features). The union is **23 features**, because FEAT-037 is
class `Must-have` while its MoSCoW priority is `Should` — the two sets are not nested.

| Must-have feature | Class | MoSCoW | Workflow(s) |
|:--|:--|:--|:--|
| FEAT-001 Unified talent identity | Must-have | Must | WF-01, WF-02 |
| FEAT-002 Device-limited sessions | Must-have | Must | WF-01, WF-09 |
| FEAT-003 Session revocation | Must-have | Must | WF-10 |
| FEAT-005 Dual-vertical identity | Differentiator | Must | WF-02, WF-07 |
| FEAT-006 Reference taxonomies | Must-have | Must | WF-01, WF-02, WF-03 |
| FEAT-007 Candidate profile | Must-have | Must | WF-02 |
| FEAT-009 Document management | Must-have | Must | WF-02 |
| FEAT-010 Candidate search | Must-have | Must | WF-04, WF-14 |
| FEAT-011 Organisation | Must-have | Must | WF-03, WF-06, WF-08 |
| FEAT-012 Job posting | Must-have | Must | WF-03 |
| FEAT-014 Application | Must-have | Must | WF-04, WF-05 |
| FEAT-015 Stage history | Differentiator | Must | WF-05 |
| FEAT-016 Job-feed matching | Must-have | Must | WF-04 |
| FEAT-019 RBAC | Must-have | Must | WF-03, WF-08, WF-10 |
| FEAT-020 RLS tenant isolation | Differentiator | Must | WF-03, WF-05, WF-06, WF-08 |
| FEAT-022 Audit ledger | Differentiator | Must | WF-08, WF-10, WF-14 |
| FEAT-023 Block list | Differentiator | Must | WF-04, WF-11, WF-14 |
| FEAT-027 Double-booking prevention | Differentiator | Must | WF-07 |
| FEAT-030 Licensed entitlements | Must-have | Must | WF-09 |
| FEAT-037 Data-quality validation harness | Must-have | Should | WF-12 |
| FEAT-038 Regression test suite | Must-have | Must | WF-12 |
| FEAT-040 Backup and restore | Must-have | Must | WF-12 |
| FEAT-041 Containerised deployment | Must-have | Must | WF-12 |

**Coverage: 23 / 23 = 100%.** Every must-have feature — under either vocabulary, and under their union —
appears in at least one workflow, and no workflow exists without a feature.

---

## 4. Workflows

### WF-01 — User registration and authentication

| # | Attribute | Content |
|:--|:--|:--|
| 1 | **ID / name** | WF-01 — User registration and authentication |
| 2 | **Trigger** | A person decides to use the platform |
| 3 | **Actors** | ACT-01 (as the prospective user); ACT-08 (platform operator) |
| 4 | **Preconditions** | The email is not already registered; `master.*` reference data is seeded |
| 5 | **Triggering event** | Registration form submitted **[app-layer]** |
| 6 | **Main flow** | (1) Create `core.user_account` — unique lowercase email, `account_status = 'pending'`; (2) create `core.user_credential` with `algorithm = 'argon2id'` and the secret hash; (3) assign `core.user_role` rows; (4) on activation set `account_status = 'active'`; (5) authenticate: call `core.create_session_with_device_limit(p_user_account_id, p_device_identifier, p_session_token_hash)`; (6) the function takes `SELECT ... FOR UPDATE` on the `core.user_account` row, reads the entitlement from `commercial.subscription_licence` (falling back to 2 devices), counts distinct active devices, and creates the `core.user_session` row; (7) register the device in `core.user_device` |
| 7 | **Alternative flows** | (a) The email is already registered → the insert fails on `uq_user_account_email`; (b) the account is `suspended` or `deactivated` → the function returns NULL; (c) the device count already meets the entitlement → the function returns NULL and writes a `device.limit_exceeded` audit event |
| 8 | **Postconditions** | A `core.user_account` in `active` status exists, with a credential, at least one role, and an active `core.user_session` bound to a device identifier |
| 9 | **Data objects affected** | `core.user_account`, `core.user_credential`, `core.user_role`, `core.user_device`, `core.user_session`, `audit.audit_event` ; `core.permission` and `core.role_permission` (what each role may do), `core.identity_verification` (outcome and opaque token of a national-identity check; never the number) |
| 10 | **State machine** | `account_status`: `pending` → `active` → `suspended` → `deactivated` (`db/migrations/002:43-50`) |
| 11 | **Business rules enforced** | BR-001 (unique lowercase email), BR-002 (device entitlement), SEC-006 (hash format — *checked at runtime, not by DDL*), SEC-008 (device-limit refusal) |
| 12 | **Exceptions** | EXC-01 (duplicate email), EXC-02 (device limit exceeded), EXC-03 (account not active), EXC-04 (credential hash format violation) |
| 13 | **Requirements** | REQ-001, REQ-002, REQ-003, REQ-004, REQ-005, REQ-009, BR-001, BR-002, SEC-006, SEC-007, SEC-008 |
| 14 | **Features** | FEAT-001, FEAT-002, FEAT-006 |

> **Note.** Step 5 is the only place where the device entitlement is evaluated, and it is evaluated **inside
> the database function** under a row lock — not by application code. This is what makes the limit
> enforceable under concurrency (`tests/test_concurrency.py` proves exactly 2 of 10 parallel logins succeed
> at a 2-device entitlement).

---

### WF-02 — Candidate profile creation and completion

| # | Attribute | Content |
|:--|:--|:--|
| 1 | **ID / name** | WF-02 — Candidate profile creation and completion |
| 2 | **Trigger** | A registered user chooses to build a candidate profile |
| 3 | **Actors** | ACT-01 (candidate); ACT-03 (if the same person also works gigs); ACT-08 |
| 4 | **Preconditions** | `core.user_account` exists and is active; `master.skill`, `master.city`, `master.country`, `master.qualification`, `master.language` are seeded |
| 5 | **Triggering event** | Profile creation initiated **[app-layer]** |
| 6 | **Main flow** | (1) Create `profile.candidate_profile` linked to the user account, with `visibility` defaulting to `recruiters`; (2) add `profile.candidate_skill` rows referencing `master.skill` with proficiency and years; (3) add `profile.candidate_work_experience` and `profile.candidate_education` with ordered date ranges; (4) add `profile.candidate_language` and `profile.candidate_project`; (5) upload a resume → `profile.candidate_document` with MIME type, size, SHA-256 checksum and `storage_key`; (6) add locations → `profile.candidate_location`; (7) compute completeness → `profile.candidate_profile_completion` with a `total_score_percentage` bounded 0–100; (8) optionally create `gig.gig_worker_profile` under the same `core.user_account` (the dual-vertical identity) |
| 7 | **Alternative flows** | (a) A document exceeds the size limit or carries an unsupported MIME type → rejected by CHECK constraints; (b) a second resume is marked primary → the partial unique index rejects it; (c) a date range is inverted (`end_date < start_date`) → rejected; (d) the same account already holds a gig profile → the second insert violates the FK-uniqueness |
| 8 | **Postconditions** | A complete candidate profile exists with a completeness score ≥ 0 and at most one primary resume |
| 9 | **Data objects affected** | `profile.candidate_profile`, `profile.candidate_skill`, `profile.candidate_work_experience`, `profile.candidate_education`, `profile.candidate_language`, `profile.candidate_project`, `profile.candidate_location`, `profile.candidate_document`, `profile.candidate_profile_completion`, `gig.gig_worker_profile` ; `master.state` (location hierarchy) |
| 10 | **State machine** | `profile_status` (active/draft/…); `visibility`: `private` ↔ `recruiters` ↔ `public` (`db/migrations/005:32-33`) |
| 11 | **Business rules enforced** | BR-005 (master data read-only), BR-006 (one visibility state), BR-007 (completeness derivation), BR-008 (one primary resume), BR-009 (skill claim shape) |
| 12 | **Exceptions** | EXC-05 (document rejected), EXC-06 (duplicate primary resume), EXC-07 (inverted date range) |
| 13 | **Requirements** | REQ-008, REQ-009, REQ-010, REQ-011, REQ-012, REQ-013, BR-005…BR-009, DATA-004, DATA-007 |
| 14 | **Features** | FEAT-001, FEAT-005, FEAT-006, FEAT-007, FEAT-008, FEAT-009 |

---

### WF-03 — Job posting creation and publication

| # | Attribute | Content |
|:--|:--|:--|
| 1 | **ID / name** | WF-03 — Job posting creation and publication |
| 2 | **Trigger** | An employer or recruiter needs to advertise a vacancy |
| 3 | **Actors** | ACT-02 (recruiter), ACT-04 (employer), ACT-06 (organisation administrator) |
| 4 | **Preconditions** | The actor belongs to an organisation (`recruitment.organization_member`); the organisation is active |
| 5 | **Triggering event** | Job requirement drafted **[app-layer]** |
| 6 | **Main flow** | (1) Create `recruitment.job_posting` with `organization_id`, `job_status = 'draft'`, title, description, vacancies, primary location, department (`master.department`), arrangement, salary bounds, and the `show_salary` and `has_variable_pay` flags; (2) add the other cities (`recruitment.job_posting_location`), the perks (`recruitment.job_posting_perk`) and the education asked for (`recruitment.job_qualification_requirement`); (3) add required skills via `recruitment.job_skill_requirement` referencing `master.skill`; (4) assign the recruiters who work on it (`recruitment.job_recruiter_assignment`; each must belong to the organisation or be mapped to it as a client); (5) optionally attach a questionnaire → `recruitment.job_questionnaire` with `recruitment.job_questionnaire_question`; (6) set the consultant openness policy — the field that `sourcing.enforce_consultant_openness` later reads; (7) transition `job_status` to `published` and set `published_at`; (8) publish triggers job-feed matching (Q02, which shows the salary only when `show_salary` is set) and alerts (`messaging.job_alert_preference`) **[app-layer]** |
| 7 | **Alternative flows** | (a) Salary fields are partially populated → `ck_job_posting_salary_currency` rejects the row (BR-012); `show_salary` on a job with no salary is rejected (BR-041); a recruiter who does not belong to the organisation cannot be assigned (BR-042); (b) the actor is not a member of the posting's organisation → rejected **[app-layer — SEC-002 is not enforced by RLS today]**; (c) the posting has no skills → the requirement is optional; (d) a job has more than one questionnaire → the one-questionnaire constraint rejects it |
| 8 | **Postconditions** | A published job posting exists, discoverable by the feed and by recruiter search |
| 9 | **Data objects affected** | `recruitment.job_posting`, `recruitment.job_skill_requirement`, `recruitment.job_questionnaire`, `recruitment.job_questionnaire_question`, `recruitment.organization`, `recruitment.organization_member` ; `recruitment.job_position` (individual vacancy slots), `master.job_role`, `master.industry`, `master.employment_type`, `master.work_type`, `master.department`, `master.job_perk`, `recruitment.job_posting_location`, `recruitment.job_posting_perk`, `recruitment.job_qualification_requirement`, `recruitment.job_recruiter_assignment` |
| 10 | **State machine** | `job_status`: `draft` → `published` → `paused` → `published` → `closed` → `filled` (`db/migrations/008:84-89`) |
| 11 | **Business rules enforced** | BR-011 (organisation structure), BR-012 (salary all-or-none), BR-013 (one questionnaire), DATA-001 (constrained codes), DATA-007 (currency format) |
| 12 | **Exceptions** | EXC-08 (partial salary block), EXC-09 (cross-organisation post), EXC-10 (duplicate questionnaire), EXC-11 (invalid status transition) |
| 13 | **Requirements** | REQ-009, REQ-015, REQ-017, REQ-018, BR-011, BR-012, BR-013, SEC-002 |
| 14 | **Features** | FEAT-006, FEAT-011, FEAT-012, FEAT-013, FEAT-019, FEAT-020 |

---

### WF-04 — Candidate discovery and job application

| # | Attribute | Content |
|:--|:--|:--|
| 1 | **ID / name** | WF-04 — Candidate discovery and job application |
| 2 | **Trigger** | A recruiter seeks candidates, or a candidate seeks jobs |
| 3 | **Actors** | ACT-02 (recruiter), ACT-04 (employer), ACT-05 (consultant), ACT-01 (candidate) |
| 4 | **Preconditions** | The job is published; the candidate profile is visible to the searching party |
| 5 | **Triggering event** | A search is executed, or a candidate clicks apply **[app-layer]** |
| 6 | **Main flow** | (1) Recruiter path: execute `db/queries/01_candidate_multicriteria_search.sql` — filter on `profile_status = 'active'`, `visibility IN ('recruiters','public')`, experience years and skill names; (2) apply `core.is_candidate_visible_to(viewer, candidate)` to exclude blocked pairs, and filter out candidates who blocked the searching organisation; (3) optionally download an unlocked profile → WF-14, which deducts credit; (4) candidate path: execute `db/queries/02_job_feed_matching.sql` for the job feed; (5) candidate creates `recruitment.candidate_application` with `application_source` and a cover letter; (6) attach questionnaire answers → `recruitment.application_question_response`; (7) the application starts at `application_status = 'applied'` |
| 7 | **Alternative flows** | (a) The candidate has already applied to the job → `uq_candidate_application_candidate_job` rejects the duplicate (BR-014); (b) the candidate blocked the recruiter, or the recruiter blocked the candidate → `core.is_candidate_visible_to` returns FALSE and the candidate is excluded (SEC-010); (c) the job has a questionnaire and a position is filled → an answer is required; (d) the candidate's profile visibility is `private` → the candidate does not appear in recruiter search results |
| 8 | **Postconditions** | An application exists in `applied` state, with source and cover letter; recruiter search returns only visible, unblocked, matching candidates |
| 9 | **Data objects affected** | `profile.candidate_profile`, `profile.candidate_skill`, `profile.candidate_location`, `master.skill`, `master.city`, `recruitment.job_posting`, `recruitment.candidate_application`, `recruitment.application_question_response`, `core.user_block` ; `recruitment.candidate_application_partitioned` (the range-partitioned reporting copy of applications), `profile.candidate_search_history` (a candidate's own job searches) |
| 10 | **State machine** | `application_status` begins at `applied`; the seven permitted values are listed in WF-05 |
| 11 | **Business rules enforced** | BR-010 (search honours visibility and blocks), BR-013 (questionnaire), BR-014 (one application per job), BR-015 (stage set), BR-021 (outreach block filter) |
| 12 | **Exceptions** | EXC-12 (duplicate application), EXC-13 (blocked candidate), EXC-14 (private profile) |
| 13 | **Requirements** | REQ-014, REQ-019, REQ-020, REQ-023, BR-010, BR-013, BR-014, BR-015, SEC-010, NFR-001, NFR-002 |
| 14 | **Features** | FEAT-010, FEAT-013, FEAT-014, FEAT-016, FEAT-023, FEAT-031 |

> **Caveat.** Step 2's block filtering is a **function-scoped** control: it protects only the read paths that
> call `core.is_candidate_visible_to`. `db/queries/01` filters on `visibility` but does not itself exclude
> blocked viewers — the exclusion is a caller obligation. This is NFR-013's gap (**NG-17**).

---

### WF-05 — Recruitment pipeline management

| # | Attribute | Content |
|:--|:--|:--|
| 1 | **ID / name** | WF-05 — Recruitment pipeline management |
| 2 | **Trigger** | An application exists and needs assessment |
| 3 | **Actors** | ACT-02 (recruiter), ACT-04 (employer), ACT-07 (placement officer, campus only) |
| 4 | **Preconditions** | The application exists in a non-terminal state |
| 5 | **Triggering event** | A recruiter decides to advance, reject or withdraw an application **[app-layer]** |
| 6 | **Main flow** | (1) Update `recruitment.candidate_application.application_status` to the next stage; (2) the trigger `trg_candidate_application_status_history` fires and inserts a `recruitment.application_status_history` row with `changed_by_user_account_id`, `previous_status`, `new_status` and a reason; (3) record the decision reason; (4) on reaching `joined`, update the headcount counter **[app-layer]**; (5) view the funnel via `db/queries/03_recruiter_pipeline_funnel.sql`; (6) a recruiter may first create the application in the `sourced` stage for a candidate who has not applied (`recruitment.candidate_application` with source `recruiter_sourced`; the sourcing recruiter becomes the candidate's recruiter), and it moves on to applied or shortlisted; (7) the recruiter's comment is stored with the move by `recruitment.change_application_status`, and the requirement page lists the candidates with `recruitment.job_candidate_pipeline` |
| 7 | **Alternative flows** | (a) The new status equals the current status → the trigger records nothing (BR-016); (b) the status is outside the eight permitted values (`sourced` plus the seven) → the CHECK constraint rejects it; `sourced` → `joined` is an illegal move (BR-045); (c) an application is withdrawn by the candidate → `withdrawn`, and it leaves the active funnel; (d) the recruiter belongs to a different organisation → **[app-layer — not enforced at the database layer]** |
| 8 | **Postconditions** | The application is in the new stage, and a history row exists recording who moved it, from what, to what and why |
| 9 | **Data objects affected** | `recruitment.candidate_application`, `recruitment.application_status_history` |
| 10 | **State machine** | `application_status`: `sourced` → `applied` or `shortlisted`; `applied` → `shortlisted` → `interviewed` → `offered` → `joined`; with `rejected` and `withdrawn` reachable from the non-terminal states (`db/migrations/009:53-61`, `042`) |
| 11 | **Business rules enforced** | BR-015 (seven permitted values), BR-016 (every change recorded), BR-017 (aggregations derived, not denormalised) |
| 12 | **Exceptions** | EXC-15 (invalid transition), EXC-16 (same-stage update not recorded), EXC-17 (cross-organisation pipeline access) |
| 13 | **Requirements** | REQ-020, REQ-021, REQ-022, REQ-024, BR-015, BR-016, BR-017, SEC-003, SEC-002 |
| 14 | **Features** | FEAT-014, FEAT-015, FEAT-017, FEAT-020, FEAT-029 |

> **Note.** The history row is written by a **trigger**, not by the calling code. A recruiter who updates the
> status by any route — API, script, manual SQL — produces a history row. This is why FEAT-015 is classified
> as a differentiator.

---

### WF-06 — Agency consultant sourcing

| # | Attribute | Content |
|:--|:--|:--|
| 1 | **ID / name** | WF-06 — Agency consultant sourcing |
| 2 | **Trigger** | A consultant wants access to source for a job |
| 3 | **Actors** | ACT-05 (consultant), ACT-04 (employer), ACT-02 (recruiter) |
| 4 | **Preconditions** | The job exists; the consultant user exists |
| 5 | **Triggering event** | The consultant raises a sourcing request **[app-layer]** |
| 6 | **Main flow** | (1) Consultant inserts `sourcing.consultant_sourcing_request` for the job with `consultant_sourcing_request_status = 'requested'`; (2) the employer accepts or declines → status becomes `accepted` or `declined`, and `decided_at` is set; (3) the consultant inserts `sourcing.sourcing_submission` for a candidate — the trigger `trg_enforce_consultant_openness` verifies the job's consultant-openness policy and raises if the job is closed to consultants; (4) the submission advances `submitted` → `shortlisted` → `accepted` → `hired` (or `rejected`); (5) run a batch outreach → `sourcing.outreach_batch` and `sourcing.outreach_recipient`, filtered by `db/queries/06_sourcing_outreach_unblocked.sql` to exclude candidates who blocked the sender |
| 7 | **Alternative flows** | (a) The job is not open to consultants → the submission insert raises an exception (BR-019); (b) the employer declines → the request is `declined` and no submission may follow; (c) the same consultant already submitted this candidate to this job → the unique constraint rejects it (BR-020); (d) a recipient has blocked the sender → filtered out of the outreach batch (BR-021); (e) the request is revoked after acceptance → `consultant_sourcing_request_status = 'revoked'` |
| 8 | **Postconditions** | A sourcing request in a decided state, zero or more submissions, and outreach batches that respect block state |
| 9 | **Data objects affected** | `sourcing.consultant_sourcing_request`, `sourcing.sourcing_submission`, `sourcing.outreach_batch`, `sourcing.outreach_recipient`, `recruitment.job_posting`, `core.user_block` ; `sourcing.job_consultant_policy` (how many consultants a job accepts, bounty and terms) |
| 10 | **State machine** | `consultant_sourcing_request_status`: `requested` → `accepted`/`declined`/`revoked` (`016:84-90`). `sourcing_submission_status`: `submitted` → `shortlisted` → `accepted` → `hired`; `rejected` from the pre-terminal states (`016:183-192`) |
| 11 | **Business rules enforced** | BR-018 (request uniqueness and decision semantics), BR-019 (consultant openness), BR-020 (one submission per candidate per job), BR-021 (block-filtered outreach) |
| 12 | **Exceptions** | EXC-18 (submission to a closed job), EXC-19 (duplicate submission), EXC-20 (request not accepted) |
| 13 | **Requirements** | REQ-015, REQ-025, REQ-026, REQ-027, REQ-028, BR-018…BR-021, SEC-002 |
| 14 | **Features** | FEAT-011, FEAT-018, FEAT-020, FEAT-024 |

---

### WF-07 — Gig marketplace engagement

| # | Attribute | Content |
|:--|:--|:--|
| 1 | **ID / name** | WF-07 — Gig marketplace engagement |
| 2 | **Trigger** | A client needs a project done, or a worker needs a project |
| 3 | **Actors** | ACT-03 (gig worker), ACT-04 (client), ACT-01 (when the same person is both) |
| 4 | **Preconditions** | The gig worker holds a `gig.gig_worker_profile`; the client belongs to an organisation |
| 5 | **Triggering event** | A client raises a gig request, or a worker applies to one **[app-layer]** |
| 6 | **Main flow** | (1) Client inserts `gig.gig_request` with deliverables, budget, currency, pricing type, date window and `gig_request_status = 'open'`; (2) worker inserts `gig.gig_application` (`gig_application_status = 'submitted'`); (3) client accepts or rejects → status becomes `accepted` or `rejected` and `decided_at` is set; (4) client creates `gig.gig_assignment` with `assigned_start_date`, `assigned_end_date`, agreed amount and `assignment_status = 'active'` — the GiST exclusion constraint `ex_gig_assignment_no_overlap` rejects any window overlapping the worker's other active assignments; (5) on completion → `assignment_status = 'completed'`; (6) both sides may leave a `gig.gig_rating` (1–5 on quality and communication) |
| 7 | **Alternative flows** | (a) The requested window overlaps an existing active assignment → `ExclusionViolation` (23P01) at commit (BR-025); (b) the assignment is terminated early → `assignment_status = 'terminated'` — note the exclusion constraint applies only to `active`, so a terminated assignment frees the window; (c) the budget is ≤ 0 or the dates are inverted → rejected by CHECK constraints (BR-023); (d) the request is cancelled → `gig_request_status = 'cancelled'`; (e) the worker withdraws an application → `gig_application_status = 'withdrawn'` |
| 8 | **Postconditions** | A completed or terminated assignment exists with a non-overlapping calendar, a consistent status, and ratings where both parties participated |
| 9 | **Data objects affected** | `gig.gig_worker_profile`, `gig.gig_worker_availability`, `gig.gig_request`, `gig.gig_application`, `gig.gig_assignment`, `gig.gig_rating`, `master.skill` ; `gig.gig_worker_service` (services a worker offers), `gig.gig_worker_preference` (favourite and blocked workers), `gig.gig_external_earnings` (earnings reported by the fulfilment system) |
| 10 | **State machine** | `gig_request_status`: `open` → `awarded` → `in_progress` → `completed`; `cancelled` from the pre-terminal states (`014:178-187`). `gig_application_status`: `submitted` → `accepted`/`rejected`/`withdrawn` (`014:238-247`). `gig_assignment_status`: `active` → `completed`/`terminated` (`014:312-313`) |
| 11 | **Business rules enforced** | BR-022 (verification state), BR-023 (budget and date window), BR-024 (decided_at semantics), BR-025 (no overlapping active assignments), BR-026 (assignment status set) |
| 12 | **Exceptions** | EXC-21 (overlapping assignment), EXC-22 (invalid request), EXC-23 (application decided inconsistently), EXC-24 (assignment termination) |
| 13 | **Requirements** | REQ-008, REQ-029, REQ-030, REQ-031, REQ-032, REQ-033, REQ-034, BR-022…BR-027, SEC-004 |
| 14 | **Features** | FEAT-005, FEAT-025, FEAT-026, FEAT-027, FEAT-028, FEAT-036 |

> **Note.** Step 4 is the one place in the system where a **business invariant is enforced by the storage
> engine** rather than by application logic: the GiST exclusion constraint refuses a double-booking at
> commit time, with no race window. `tests/test_concurrency.py` proves exactly 1 of 5 concurrent overlapping
> assignments succeeds.

---

### WF-08 — Organisation and member administration

| # | Attribute | Content |
|:--|:--|:--|
| 1 | **ID / name** | WF-08 — Organisation and member administration |
| 2 | **Trigger** | An organisation needs to be set up or changed |
| 3 | **Actors** | ACT-06 (organisation administrator), ACT-08 (platform operations) |
| 4 | **Preconditions** | An actor holds `account_admin` (or `super_admin`) |
| 5 | **Triggering event** | Onboarding or an administrative change **[app-layer]** |
| 6 | **Main flow** | (1) Create `recruitment.organization` with a unique slug and an `organization_type` (`employer`, `recruitment_agency`, `consultancy`, `educational_institution`, `other`); (2) add `recruitment.organization_location` rows; (3) add `recruitment.organization_identifier` rows (GSTIN, CIN, EIN, VAT, PAN) with a verification state; (4) add `recruitment.organization_member` rows with an `organization_role` (`owner`, `admin`, `recruiter`, `hiring_manager`, `billing_manager`, `consultant`); (5) establish `recruitment.organization_hierarchy` for a group structure; (6) map agency recruiters to clients via `recruitment.recruiter_client_mapping`; (7) allocate licence seats → WF-09 |
| 7 | **Alternative flows** | (a) The slug is already taken → `uq_organization_slug` rejects it; (b) the identifier type is invalid for the country → the CHECK constraint rejects it; (c) a member is removed → `organization_member.removed_at` is set and `status` changes; (d) **permission checks are application-layer only** — a member's actual capabilities are not derived from their organisation role anywhere in the schema (SEC-001) |
| 8 | **Postconditions** | An active organisation exists with members, locations, identifiers and, where relevant, a hierarchy and client mappings |
| 9 | **Data objects affected** | `recruitment.organization`, `recruitment.organization_location`, `recruitment.organization_identifier`, `recruitment.organization_member`, `recruitment.organization_hierarchy`, `recruitment.recruiter_client_mapping`, `core.role`, `core.user_role`, `recruitment.company_review_summary` (third-party review figures with source and refresh date) |
| 10 | **State machine** | `organization.status` (active/suspended/…); `organization_member.status` (active/inactive/…) with `removed_at` and `removed_status` |
| 11 | **Business rules enforced** | BR-011 (organisation structure), BR-001 (role assignment), DATA-001 (constrained codes), DATA-006 (referential integrity) |
| 12 | **Exceptions** | EXC-25 (duplicate slug), EXC-26 (invalid identifier type) |
| 13 | **Requirements** | REQ-015, REQ-016, SEC-001, SEC-002, BR-011 |
| 14 | **Features** | FEAT-011, FEAT-019, FEAT-020, FEAT-021, FEAT-022 |

> **Known gap.** `core.user_role` links a user to a platform role, and `recruitment.organization_member`
> links a user to an organisation — but **nothing links the two**, and `core.role_permission` is empty. The
> organisation role therefore has no effect on what a member can do. See [`docs/phase-1-discover/02-personas.md`](02-personas.md)
> §5.

---

### WF-09 — Licensing, subscription and entitlements

| # | Attribute | Content |
|:--|:--|:--|
| 1 | **ID / name** | WF-09 — Licensing, subscription and entitlements |
| 2 | **Trigger** | An organisation buys or renews a licence |
| 3 | **Actors** | ACT-06 (organisation administrator), ACT-08 (platform operations), ACT-09 (payment gateway) |
| 4 | **Preconditions** | The organisation exists |
| 5 | **Triggering event** | A plan is selected, or a payment webhook arrives **[app-layer]** |
| 6 | **Main flow** | (1) Create `commercial.subscription_licence` with `max_users`, `max_devices_per_user` and `licence_status = 'active'`; (2) create `commercial.subscription` referencing the plan, with `subscription_status = 'active'`; (3) allocate seats → `commercial.licence_seat_allocation`; the trigger `trg_enforce_licence_max_users` counts active seats and raises if the allocation would exceed `max_users`; (4) on payment, insert `commercial.payment_order` with a unique `gateway_order_id` and `payment_order_status = 'created'`; (5) the gateway confirms → status becomes `authorized` then `captured`; (6) credit the wallet → append a `commercial.wallet_ledger` row with `entry_type = 'credit'`, `reference_type = 'recharge'`; (7) issue `commercial.invoice` with a unique `invoice_number`; (8) on failure → `payment_order_status = 'failed'`; on cancellation → `cancelled`; on refund → insert `commercial.payment_refund` with a unique `gateway_refund_ref` and append a compensating ledger row |
| 7 | **Alternative flows** | (a) The seat allocation would exceed `max_users` → the trigger raises (BR / SEC-001); (b) the gateway declines → `payment_order_status = 'failed'`; (c) the payment is retried → **there is no idempotency key column on `commercial.wallet_ledger`**; uniqueness exists only on `gateway_order_id`, `invoice_number`, `gateway_refund_ref` and `wallet(org,currency)`, so a retried webhook can double-credit (ML-07); (d) a refund → `payment_order_status = 'refunded'` with a new ledger row, never an update (SEC-005) |
| 8 | **Postconditions** | An active licence with seats within entitlement, an active subscription, and a wallet whose balance equals the sum of its ledger entries |
| 9 | **Data objects affected** | `commercial.subscription_plan`, `commercial.subscription_licence`, `commercial.licence_seat_allocation`, `commercial.subscription`, `commercial.payment_order`, `commercial.payment_refund`, `commercial.invoice`, `commercial.wallet`, `commercial.wallet_ledger` |
| 10 | **State machine** | `subscription_status`: `active`/`cancelled`/`expired` (`017:93-94`). `payment_order_status`: `created` → `authorized` → `captured`; `failed`/`cancelled`/`refunded` (`017:146-156`). `licence_status`: `active`/`expired`/`suspended`/`cancelled` (`015:40-41`). `invoice_status`: `draft`/`issued`/`paid`/`void`/`uncollectible` (`017:205-206`) |
| 11 | **Business rules enforced** | BR-002 (device entitlement), BR-003 (revocation), BR-012 (salary/currency), SEC-005 (append-only ledger), SEC-008 (device limit), DATA-007 (ISO 4217) |
| 12 | **Exceptions** | EXC-27 (seat allocation exceeds entitlement), EXC-28 (payment failure), EXC-29 (duplicate webhook / double credit) |
| 13 | **Requirements** | REQ-004, REQ-005, REQ-017, REQ-033, SEC-005, SEC-008, NFR-010, NFR-011, NFR-012 |
| 14 | **Features** | FEAT-002, FEAT-030, FEAT-031, FEAT-032, FEAT-036 |

---

### WF-10 — Session management and revocation

| # | Attribute | Content |
|:--|:--|:--|
| 1 | **ID / name** | WF-10 — Session management and revocation |
| 2 | **Trigger** | A user or an administrator needs to end a session |
| 3 | **Actors** | ACT-01 (all authenticated roles), ACT-08 |
| 4 | **Preconditions** | A session exists |
| 5 | **Triggering event** | Logout, "sign out other devices", or an administrative revocation **[app-layer]** |
| 6 | **Main flow** | (1) Identify the target session in `core.user_session`; (2) call `core.revoke_user_session(p_session_id, p_revoked_by_user_account_id)`; (3) the function sets `revoked_at` and `ended_at`; (4) the function inserts an `audit.audit_event` with `event_type = 'session.revoked'`; (5) optionally remove the device from `core.user_device` |
| 7 | **Alternative flows** | (a) The session is already revoked → the function is idempotent or rejects the double revocation, depending on its internal guard; (b) a non-owner attempts to revoke → **[app-layer — no ownership check is enforced by the database]**; (c) an administrative bulk revocation → iterate the function per session, producing one audit event each |
| 8 | **Postconditions** | The session is terminal (`ended_at` and `revoked_at` set) and a `session.revoked` audit event exists |
| 9 | **Data objects affected** | `core.user_session`, `core.user_device`, `audit.audit_event` |
| 10 | **State machine** | Session lifecycle: `started_at` set → `ended_at` set (natural expiry or logout) → `revoked_at` set (administrative or explicit revocation). `core.is_candidate_visible_to` and `core.create_session_with_device_limit` both filter on `ended_at IS NULL AND revoked_at IS NULL` |
| 11 | **Business rules enforced** | BR-002 (device entitlement counts only live sessions), BR-003 (revocation is terminal), SEC-001 (permission to revoke), SEC-003 (audited) |
| 12 | **Exceptions** | EXC-30 (session not found), EXC-31 (unauthorised revocation) |
| 13 | **Requirements** | REQ-003, REQ-006, SEC-001, SEC-003, SEC-007 |
| 14 | **Features** | FEAT-003, FEAT-019, FEAT-022 |

---

### WF-11 — Notification, consent and privacy management

| # | Attribute | Content |
|:--|:--|:--|
| 1 | **ID / name** | WF-11 — Notification, consent and privacy management |
| 2 | **Trigger** | The platform must inform a user, or a user must exercise a privacy right |
| 3 | **Actors** | ACT-01, ACT-03 (the data subject), ACT-08 |
| 4 | **Preconditions** | The user exists; templates and translations are seeded |
| 5 | **Triggering event** | A domain event occurs, or the user changes a preference **[app-layer]** |
| 6 | **Main flow** | (1) Platform selects a template from `messaging.notification_template` for the category and channel; (2) render using `messaging.ui_translation` via `messaging.get_ui_translation(key, lang)` — which falls back to English when the key is missing in the requested language; (3) check `messaging.user_notification_preference` for the category/channel toggle **[app-layer — no dispatch path in the schema]**; (4) insert `messaging.notification_delivery` with `delivery_status = 'queued'`, the channel and the recipient; (5) dispatch to the provider and update the status to `sent` → `delivered` → `read`, recording `external_provider_message_id` and the timestamps; (6) on failure → `failed`, and the retry, backoff and dead-letter handling is WF-15 (`messaging.integration_event`); (7) consent path: the user grants or withdraws consent → `core.consent_record` records the subject, category, state and timestamp; (8) privacy path: the user blocks a recruiter or organisation → `core.user_block`, which then flips `core.is_candidate_visible_to` |
| 7 | **Alternative flows** | (a) The translation key is missing in the requested locale → the function returns the English fallback; (b) the user has opted out of the channel → no delivery row **[app-layer]**; (c) the provider rejects the message → `failed`; (d) the user blocks a party → the party loses visibility (SEC-010); (e) the user withdraws consent → the consent record's state changes — **but no deletion or suppression path consumes it** (ML-09, OQ-011) |
| 8 | **Postconditions** | A delivery row exists per dispatched notification with a terminal status; consent and block state are queryable |
| 9 | **Data objects affected** | `messaging.ui_translation`, `messaging.notification_template`, `messaging.user_notification_preference`, `messaging.user_privacy_preference`, `messaging.notification_delivery`, `core.consent_record`, `core.user_block`, `messaging.job_alert_preference` |
| 10 | **State machine** | `delivery_status`: `queued` → `sent` → `delivered` → `read`; `failed` from `sent` (`018:277-279`). The retry path `failed` → `retried` → `DLQ` exists only in the boundary diagram (`docs/phase-4-platform/22-integration-boundaries.md:99-107`), **not in the schema** |
| 11 | **Business rules enforced** | BR-004 (consent record), BR-021 (block-filtered outreach), SEC-010 (block enforcement), SEC-011 (consent queryable) |
| 12 | **Exceptions** | EXC-32 (delivery failure), EXC-33 (consent withdrawal not honoured) |
| 13 | **Requirements** | REQ-007, SEC-010, SEC-011, NFR-008, NFR-018 |
| 14 | **Features** | FEAT-004, FEAT-023, FEAT-033, FEAT-034, FEAT-042 |

---

### WF-12 — Platform operations, validation and backup

| # | Attribute | Content |
|:--|:--|:--|
| 1 | **ID / name** | WF-12 — Platform operations, validation and backup |
| 2 | **Trigger** | A release, a data refresh, or a scheduled backup |
| 3 | **Actors** | ACT-08 |
| 4 | **Preconditions** | A PostgreSQL 17 instance is available |
| 5 | **Triggering event** | Operator action or schedule |
| 6 | **Main flow** | (1) Build the environment: `docker-compose up -d` → a single PostgreSQL 17 service with a volume; (2) apply every migration in `db/migrations/` in order (`psql -v ON_ERROR_STOP=1`); (3) seed reference data (migration 004) and generate test data (`scripts/generate_data.py`); (4) run the test suite (`scripts/run_all_tests.py` → every suite in `tests/`, SQL and Python); (5) run the data-quality validator (`scripts/validate_data.py` → 15 checks across RG1–RG10); (6) run the benchmark harness (`scripts/run_benchmarks.py` → 12 queries with p50/p95/p99); (7) run the backup/restore runbook (`scripts/backup_restore.sh` → `pg_dump` → restore into a scratch database → exact row counts for every table and counts of functions, triggers, policies, indexes and constraints → drop), reporting elapsed time against the 900-second threshold |
| 7 | **Alternative flows** | (a) A migration fails → the transaction rolls back (`BEGIN`/`COMMIT` wraps each migration); (b) A validator check FAILS → the affected data is quarantined for correction **[app-layer]**; (c) The restore exceeds 900 s → the RTO is breached and reported; (d) Row-count parity fails → the restore is not accepted as verified |
| 8 | **Postconditions** | A verified database, a passing validation report, a benchmark artefact, and a verified backup with a measured restore duration |
| 9 | **Data objects affected** | All base tables; the scratch restore database (transient); `audit.maintenance_run` (the restore check is recorded there) |
| 10 | **State machine** | Operational only — no business state machine |
| 11 | **Business rules enforced** | OPS-001 (ordered idempotent migrations), OPS-002 (containerised delivery), OPS-004 (backup/restore), OPS-007 (validation), OPS-008 (test suite), OPS-010 (single service) |
| 12 | **Exceptions** | EXC-34 (migration failure), EXC-35 (validator failure), EXC-36 (RTO breach / parity failure) |
| 13 | **Requirements** | OPS-001…OPS-004, OPS-006…OPS-008, OPS-010, NFR-010, NFR-011, NFR-015, NFR-022 |
| 14 | **Features** | FEAT-021, FEAT-038, FEAT-039, FEAT-040, FEAT-041 |

> **Update 2026-10-28.** `scripts/run_nfr_checks.py` joins the operator's steps (write latency, 500-session concurrency, master lookup, 50,000-application pipeline). The backup schedule behind the 24-hour recovery-point objective is still the operator's to set (NFR-011, OQ-010).

---

### WF-13 — Analytical mart refresh

| # | Attribute | Content |
|:--|:--|:--|
| 1 | **ID / name** | WF-13 — Analytical mart refresh |
| 2 | **Trigger** | Reporting data is stale |
| 3 | **Actors** | ACT-08 |
| 4 | **Preconditions** | The marts exist; the source tables are populated |
| 5 | **Triggering event** | The scheduled maintenance run, or a manual call |
| 6 | **Main flow** | (1) `core.run_maintenance()` calls `analytics.refresh_reporting_marts()` (the `maintenance` service in `docker-compose.yml` does so on a loop); (2) the procedure first loads the star schema — `analytics.dim_date`, `analytics.dim_candidate`, `analytics.dim_organization`, `analytics.dim_job_posting`, `analytics.fact_application_event`, `analytics.fact_gig_performance`, `analytics.fact_wallet_transaction` — then refreshes the materialised views; (3) verify the refreshed output via `db/queries/10` and `11`; (4) confirm freshness |
| 7 | **Alternative flows** | (a) The procedure fails partway → the refresh is not atomic across views, and a partially refreshed set may be visible; (b) the mart is queried before its first refresh → empty or stale results; (c) **nothing invokes this procedure automatically** — `pg_cron` is not installed (`docs/phase-2-model/09-architecture.md:112`) and no owner is defined (**OQ-010**) |
| 8 | **Postconditions** | All three marts reflect the current source data, and the KPI queries return non-empty results |
| 9 | **Data objects affected** | `analytics.*` (dimension and fact tables), and by reference every operational table the marts read |
| 10 | **State machine** | Operational only — a freshness window, not a status column |
| 11 | **Business rules enforced** | OPS-005 (refreshable on demand), DATA-001 (constrained codes in the marts) |
| 12 | **Exceptions** | EXC-37 (partial refresh / staleness) |
| 13 | **Requirements** | OPS-005, NFR-020, NFR-024, NFR-026 |
| 14 | **Features** | FEAT-029, FEAT-035 |

---

### WF-14 — Profile download and credit consumption

| # | Attribute | Content |
|:--|:--|:--|
| 1 | **ID / name** | WF-14 — Profile download and credit consumption |
| 2 | **Trigger** | A recruiter wants full access to a candidate profile |
| 3 | **Actors** | ACT-02 (recruiter), ACT-04, ACT-05 (consultant), ACT-06 (billing) |
| 4 | **Preconditions** | The recruiter acts for an organisation (active membership); the organisation has a wallet in a currency that has a price in `commercial.credit_price` |
| 5 | **Triggering event** | The application calls `commercial.download_candidate_profile` (migration 036) |
| 6 | **Main flow** | (1) `commercial.download_candidate_profile(candidate_profile_id)` checks the candidate is visible to the acting user and organisation — `core.can_view_candidate`; (2) a repeat download by the same organisation is recorded at zero cost and the function returns; (3) otherwise it picks the cheapest priced `commercial.wallet` the organisation can afford, from `commercial.credit_price`; (4) `commercial.post_wallet_entry` locks the wallet, refuses an overdraft, appends a `commercial.wallet_ledger` debit with `reference_type = 'profile_download'` and sets `commercial.wallet.balance`, in one transaction; (5) the function inserts `commercial.candidate_profile_download_history` with the amount, currency and `wallet_ledger_id`; (6) the application delivers the document **[app-layer]** |
| 7 | **Alternative flows** | (a) The balance is insufficient → `check_violation`, nothing written (EXC-38); (b) the candidate is private, or blocked the requester → `insufficient_privilege` (EXC-39); (c) a correction is needed → a new `correction_credit`/`correction_debit` row referencing the original is posted with `post_wallet_entry`; the ledger is never edited (SEC-005); (d) no wallet in a priced currency → `check_violation`; (e) two simultaneous downloads race for the last credit → the wallet row lock lets exactly one win (`tests/test_concurrency.py`, test 4) |
| 8 | **Postconditions** | A debit ledger entry, a matching download-history row, and a wallet balance equal to the ledger sum, by construction. The application role cannot write `commercial.wallet` or `commercial.wallet_ledger` directly |
| 9 | **Data objects affected** | `commercial.wallet`, `commercial.wallet_ledger`, `commercial.credit_price`, `commercial.candidate_profile_download_history`, `core.can_view_candidate`, `commercial.post_wallet_entry`, `commercial.download_candidate_profile` |
| 10 | **State machine** | `wallet_ledger.entry_type`: `credit`, `debit`, `correction_credit`, `correction_debit`. `wallet_ledger.reference_type`: `recharge`, `profile_download`, `outreach_fee`, `job_posting_fee`, `gig_commission`, `correction`. Evidence class 11 and 13 of `audit.action_catalogue` |
| 11 | **Business rules enforced** | SEC-005 (append-only), SEC-010 (visibility before access), NFR-012 (reconciliation), DEC-29 (prices and repeat downloads) |
| 12 | **Exceptions** | EXC-38 (insufficient balance), EXC-39 (blocked candidate), EXC-40 (ledger/balance divergence — now prevented rather than detected) |
| 13 | **Requirements** | REQ-014, REQ-017, SEC-005, SEC-010, NFR-012, NFR-013 |
| 14 | **Features** | FEAT-010, FEAT-022, FEAT-023, FEAT-031, FEAT-032 |

---

### WF-15 — Integration exchange with an external system

| # | Attribute | Content |
|:--|:--|:--|
| 1 | **ID / name** | WF-15 — Integration exchange with an external system |
| 2 | **Trigger** | A change must be sent to, or received from, one of the nine docket boundaries |
| 3 | **Actors** | ACT-08, the external system |
| 4 | **Preconditions** | The boundary exists in `messaging.integration_boundary` with its retry policy |
| 5 | **Triggering event** | The application enqueues an exchange |
| 6 | **Main flow** | (1) `messaging.enqueue_integration_event` writes a `messaging.integration_event` with an idempotency key — a replay of the same key is a no-op; (2) a worker calls `messaging.claim_integration_events` and receives due events, each marked in progress; (3) the worker calls the external system **[app-layer]**; (4) success → `messaging.complete_integration_event` marks it `succeeded` and stores the external reference; (5) failure → `messaging.fail_integration_event` schedules the next attempt with exponential backoff from `messaging.integration_boundary.base_backoff_seconds`; (6) after the boundary's `max_attempts` the event becomes `dead_letter` and an `INTEGRATION_DEAD_LETTER` row is written to `audit.system_error_log`; (7) an operator reads `audit.ops_integration_health` and calls `messaging.requeue_dead_letter` once the cause is fixed |
| 7 | **Alternative flows** | (a) The external system is down → events accumulate and retry; the boundary's `failure_behaviour` says what the product does meanwhile; (b) the same message arrives twice → the idempotency key makes the second a no-op; (c) a payload carries personal data → the `payload_json` guidance is references, not copies (capped at 64 KB) |
| 8 | **Postconditions** | Every exchange is delivered once, or is in the dead letter with its error and attempt count |
| 9 | **Data objects affected** | `messaging.integration_boundary`, `messaging.integration_event`, `audit.system_error_log`, `audit.ops_integration_health`, `messaging.external_reference` (our row and the other system's id), `messaging.legacy_field_mapping` (direction and conflict rule per legacy field), `messaging.sync_conflict` (conflicts, as hashes) |
| 10 | **State machine** | `messaging.integration_event.event_status`: pending, in_progress, succeeded, failed (retry scheduled), dead_letter |
| 11 | **Business rules enforced** | NFR-027 (three attempts then dead letter), docket section 6 (nine boundaries) |
| 12 | **Exceptions** | EXC-41 (dead-lettered exchange) |
| 13 | **Requirements** | NFR-027, OPS-005 |
| 14 | **Features** | FEAT-043 |

---

### WF-16 — Scheduled maintenance, retention and erasure

| # | Attribute | Content |
|:--|:--|:--|
| 1 | **ID / name** | WF-16 — Scheduled maintenance, retention and erasure |
| 2 | **Trigger** | The maintenance schedule fires (daily) |
| 3 | **Actors** | ACT-08 |
| 4 | **Preconditions** | `audit.entity_lifecycle_policy` holds a retention period for each table that has one |
| 5 | **Triggering event** | A scheduler calls `core.run_maintenance()` |
| 6 | **Main flow** | (1) `core.run_maintenance()` runs each job and writes one `audit.maintenance_run` row per job (`refresh_marts`, `purge_expired_data`, `erase_inactive_accounts`); (2) `analytics.refresh_reporting_marts()` loads and refreshes the marts → WF-13; (3) `core.purge_expired_data()` removes or anonymises rows older than their retention in `audit.entity_lifecycle_policy` and records counts per table; (4) `core.find_inactive_accounts()` lists accounts idle past the period, and `core.erase_user_account` erases each, writing a `user.erased` event to `audit.audit_event`; (5) an operator reads `audit.ops_job_freshness` and `audit.ops_database` |
| 7 | **Alternative flows** | (a) A job fails → its row says `failed` with the error, the other jobs still run; (b) a table has no retention period → nothing is purged and the policy row shows it; (c) an account has legal hold **[no hold flag exists; erasure of that account must be stopped by the operator]** |
| 8 | **Postconditions** | Expired data is gone, inactive accounts are erased, the marts are fresh, and every run is on record |
| 9 | **Data objects affected** | `audit.maintenance_run`, `audit.entity_lifecycle_policy`, `audit.audit_event`, `audit.action_catalogue`, `audit.ops_job_freshness`, `audit.ops_database` |
| 10 | **State machine** | — |
| 11 | **Business rules enforced** | DATA-006 (retention), SEC-003 (erasure is audited) |
| 12 | **Exceptions** | EXC-37, EXC-42 (purge removed too much) |
| 13 | **Requirements** | NFR-017, NFR-020, NFR-026 |
| 14 | **Features** | FEAT-035, FEAT-044 |

---

### WF-17 — Administrative support and impersonation

| # | Attribute | Content |
|:--|:--|:--|
| 1 | **ID / name** | WF-17 — Administrative support and impersonation |
| 2 | **Trigger** | A user raises a support ticket that an administrator must investigate |
| 3 | **Actors** | ACT-08 (platform administrator), ACT-01 |
| 4 | **Preconditions** | The administrator holds a platform role; the user's ticket exists |
| 5 | **Triggering event** | The administrator opens the ticket |
| 6 | **Main flow** | (1) the administrator reads the ticket in `messaging.support_ticket`; (2) looks the user up through `core.support_user_account`, a view that masks email and phone with `core.mask_email` and `core.mask_phone`; (3) if the work needs the user's view, `core.begin_impersonation` records who is acting as whom (`admin.impersonation_started` in `audit.audit_event`); (4) every audited change made meanwhile carries the impersonator's id; (5) `core.end_impersonation` closes it; (6) the administrator updates the ticket |
| 7 | **Alternative flows** | (a) A non-administrator calls `core.begin_impersonation` → refused; (b) the session ends without `end_impersonation` → the start event stands and the open impersonation is visible in `audit.audit_event` |
| 8 | **Postconditions** | The issue is resolved or escalated, and the audit trail shows exactly who acted as whom and when |
| 9 | **Data objects affected** | `messaging.support_ticket`, `core.support_user_account`, `audit.audit_event`, `core.user_account` |
| 10 | **State machine** | `messaging.support_ticket.ticket_status`: open, in_progress, waiting_on_user, resolved, closed (governed) |
| 11 | **Business rules enforced** | SEC-003, SEC-012 (support sees masked data) |
| 12 | **Exceptions** | EXC-43 (unauthorised impersonation) |
| 13 | **Requirements** | SEC-003, NFR-016 |
| 14 | **Features** | FEAT-022, FEAT-042 |

---

### WF-18 — Candidate development: courses, assessments and resume templates

| # | Attribute | Content |
|:--|:--|:--|
| 1 | **ID / name** | WF-18 — Candidate development: courses, assessments and resume templates |
| 2 | **Trigger** | A candidate wants to build skills or a resume |
| 3 | **Actors** | ACT-01, ACT-03 |
| 4 | **Preconditions** | The candidate has a profile |
| 5 | **Triggering event** | The candidate opens the learning or resume tools |
| 6 | **Main flow** | (1) the candidate browses `profile.course` and enrols — `profile.course_enrolment` (enrolled, in_progress, completed, dropped; governed); (2) takes an assessment — `profile.candidate_assessment`, with the result in `profile.candidate_assessment_score`; (3) chooses a layout from `profile.resume_template`; (4) uploads the resulting document → WF-02; (5) the activity is written to `profile.candidate_activity_log` |
| 7 | **Alternative flows** | (a) The candidate withdraws from a course → status change recorded; (b) an assessment is retaken → a new score row, the old one is kept |
| 8 | **Postconditions** | The profile shows completed courses and scores |
| 9 | **Data objects affected** | `profile.course`, `profile.course_enrolment`, `profile.candidate_assessment`, `profile.candidate_assessment_score`, `profile.resume_template`, `profile.candidate_activity_log` |
| 10 | **State machine** | `profile.course_enrolment.enrolment_status`: enrolled, in_progress, completed, dropped (governed) |
| 11 | **Business rules enforced** | DATA-001 |
| 12 | **Exceptions** | EXC-44 (score outside range) |
| 13 | **Requirements** | REQ-010 |
| 14 | **Features** | FEAT-007, FEAT-042 |

---

### WF-19 — Recruiter search, bookmarks and profile views

| # | Attribute | Content |
|:--|:--|:--|
| 1 | **ID / name** | WF-19 — Recruiter search, bookmarks and profile views |
| 2 | **Trigger** | A recruiter looks for candidates |
| 3 | **Actors** | ACT-02, ACT-04, ACT-05 |
| 4 | **Preconditions** | The recruiter acts for an organisation |
| 5 | **Triggering event** | The recruiter runs a search |
| 6 | **Main flow** | (1) the recruiter searches with `profile.search_candidates`: keywords (comma-separated phrases, or boolean mode with OR, "phrases" and minus), exclusions, experience, cities, skills, education and study mode, department, notice period, current pay, recent activity; it returns only profiles the recruiter may see (`core.can_view_candidate`: not private, not blocked), pay only where the candidate revealed it (`profile.candidate_search_attributes_for`), and a match percentage; (2) the search is recorded with `profile.record_recruiter_search` in `profile.recruiter_search`: the latest 20 as "recently searched", named ones saved, optionally with an alert; (3) opening a profile writes `profile.profile_view_history`; (4) the recruiter saves a candidate with a note in `profile.recruiter_bookmark`; (5) a full download → WF-14; (6) the candidate sees the access in `profile.candidate_activity_log` |
| 7 | **Alternative flows** | (a) The candidate blocked the recruiter's organisation → the profile never appears; (b) the profile is private → it never appears; (c) the candidate did not reveal pay → the amounts are hidden and the candidate counts as undisclosed (BR-043); (d) gender is never shown and never a filter (BR-044) |
| 8 | **Postconditions** | The view and the search are on record; the bookmark is private to the recruiter |
| 9 | **Data objects affected** | `profile.candidate_search_history`, `profile.profile_view_history`, `profile.recruiter_bookmark`, `profile.candidate_activity_log`, `core.can_view_candidate`, `profile.recruiter_search`, `profile.candidate_search_document`, `profile.candidate_job_preference`, `profile.candidate_diversity_profile` (private, never searched), `profile.search_candidates` |
| 10 | **State machine** | — |
| 11 | **Business rules enforced** | SEC-010 |
| 12 | **Exceptions** | EXC-12, EXC-39 |
| 13 | **Requirements** | REQ-014, SEC-010 |
| 14 | **Features** | FEAT-010, FEAT-020 |

---

### WF-20 — Community, support and referrals

| # | Attribute | Content |
|:--|:--|:--|
| 1 | **ID / name** | WF-20 — Community, support and referrals |
| 2 | **Trigger** | A user posts, asks for help or invites a friend |
| 3 | **Actors** | ACT-01, ACT-03, ACT-08 |
| 4 | **Preconditions** | The user has an account |
| 5 | **Triggering event** | The user opens the community or help area |
| 6 | **Main flow** | (1) the user reads `messaging.faq`; (2) posts in `messaging.community_post` and others react in `messaging.post_reaction`; (3) a question needing a person becomes a `messaging.support_ticket` → WF-17; (4) an invitation is recorded in `messaging.referral_event` with a unique code; (5) when the invitee registers the event is completed and the reward is recorded **[reward payout is app-layer]** |
| 7 | **Alternative flows** | (a) A post is reported → moderation **[app-layer]**; (b) a referral code is reused → unique constraint refuses |
| 8 | **Postconditions** | Posts, tickets and referrals are on record |
| 9 | **Data objects affected** | `messaging.faq`, `messaging.community_post`, `messaging.post_reaction`, `messaging.support_ticket`, `messaging.referral_event`, `messaging.share_event` (a job shared through an outbound link) |
| 10 | **State machine** | `messaging.support_ticket.ticket_status` (governed) |
| 11 | **Business rules enforced** | — |
| 12 | **Exceptions** | EXC-45 (duplicate referral code) |
| 13 | **Requirements** | — |
| 14 | **Features** | FEAT-042 |

---

### WF-21 — Reference data and rule maintenance

| # | Attribute | Content |
|:--|:--|:--|
| 1 | **ID / name** | WF-21 — Reference data and rule maintenance |
| 2 | **Trigger** | A value, status rule, permission or audited action must change |
| 3 | **Actors** | ACT-08 |
| 4 | **Preconditions** | The change is reviewed and written as a migration |
| 5 | **Triggering event** | A migration is applied |
| 6 | **Main flow** | (1) a new allowed value is added to a CHECK constraint, and the same migration runs `master.sync_enumeration_values()` so `master.enumeration_value` and the English display name follow (the test fails otherwise); (2) a status rule changes in `master.status_transition`, or a status is exempted in `master.status_machine_exemption`; `master.enforce_status_transition` applies it; (3) a permission is added to `core.permission` and granted in `core.role_permission`; (4) a new audited action is added to `audit.action_catalogue`; (5) new columns are classified — `audit.sync_column_classification()` writes `audit.column_classification`; (6) master data such as `master.industry`, `master.job_role`, `master.state` is added by migration |
| 7 | **Alternative flows** | (a) A migration forgets one of these steps → `tests/test_enumerations.sql`, `test_state_machines.sql`, `test_classification.sql` or `test_audit_coverage.sql` fails |
| 8 | **Postconditions** | The rule, its documentation and its tests agree |
| 9 | **Data objects affected** | `master.enumeration_value`, `master.status_transition`, `master.status_machine_exemption`, `core.permission`, `core.role_permission`, `audit.action_catalogue`, `audit.column_classification`, `master.industry`, `master.job_role`, `master.state`, `master.employment_type`, `master.work_type` |
| 10 | **State machine** | — |
| 11 | **Business rules enforced** | OPS-001 |
| 12 | **Exceptions** | EXC-34 |
| 13 | **Requirements** | OPS-001, NFR-016 |
| 14 | **Features** | FEAT-006, FEAT-019 |

---

## 5. Coverage summary

| Measure | Value |
|:--|:--|
| Workflows defined | 21 |
| Must-have features covered by ≥1 workflow | **23 / 23 = 100%** (union of MoSCoW `Must` and class `Must-have`) |
| Requirements referenced by ≥1 workflow | 34 REQ + 27 BR + 10 SEC = **71** distinct IDs |
| Data / operational / quality requirements referenced | 4 DATA (DATA-001, 004, 006, 007), 8 OPS (OPS-001, 002, 004, 005, 006, 007, 008, 010), 13 NFR (NFR-001, 002, 008, 010, 011, 012, 013, 015, 018, 020, 022, 024, 026) |
| Requirements not workflow-mapped | 4 SEC (SEC-009, 012, 013, 014), 4 DATA, 2 OPS (OPS-003, 009), 14 NFR — quality, data and operational constraints that no single workflow owns |
| Workflows with at least one exception path | **21 / 21 = 100%** (EXC-41 to EXC-45 are named in the new workflows and still to be written up in `05-exceptions.md`) |
| Workflows that are happy-path-only | **0** |
| Workflows with a documented state machine | 11 (WF-12 and WF-13 are operational) |
| Workflows containing at least one **[app-layer]** step | **13** (all except WF-13, the mart refresh, which is purely a stored procedure) |

### 5.1 The `[app-layer]` marker

13 of the 14 workflows contain steps that require application code, worker queues or scheduled jobs that **do not
exist in this repository** — dispatching a notification, computing a download fee, updating a wallet balance,
honouring a notification opt-out, running an external webhook handler. Each is marked **[app-layer]** so a
reader can see exactly where the database stops and the application must begin. The exception is WF-13, whose
entire flow is a stored procedure the operator invokes by hand.

This is not a defect list; it is the boundary of a database-design deliverable. But it has one consequence
that must be stated: **several business rules in this register can only be enforced where the application
layer does not yet exist.** The clearest example is SEC-002 (tenant isolation) — the schema has the
structures and the trigger for the consultant rule, but the recruiter's organisation boundary is enforced
nowhere.

---

## 6. Related documents

| Document | Contains |
|:--|:--|
| [`docs/phase-1-discover/01-requirements.md`](01-requirements.md) | The requirement register |
| [`docs/phase-1-discover/05-exceptions.md`](05-exceptions.md) | The EXC-NNN exception catalogue |
| [`docs/phase-1-discover/03-feature-inventory.md`](03-feature-inventory.md) | The feature register |
| [`docs/phase-1-discover/02-personas.md`](02-personas.md) | Actor definitions |
| [`docs/phase-1-discover/05-audit-event-matrix.md`](05-audit-event-matrix.md) | Audit coverage per sensitive action |
| [`docs/phase-1-discover/phase-report.md`](phase-report.md) | Phase 1 report and G1 decision |
