# Talentra — Actor Persona Register

**Phase:** 1 — Discover
**Step:** 2 — Actor Identification & Persona Definition
**Status:** **Reconciled against the docket** on 2026-10-23 ([`01-docket-reconciliation.md`](01-docket-reconciliation.md)); originally written before the docket was available. The docket's ninth actor (Guest) exists as a seeded role holding only `job.search` but is not yet a persona (GAP-05).
**Authored:** 2026-10-21

> **Reading rule.** Personas are derived from two evidence sources only: the seeded role catalogue in
> `db/migrations/012_create_administration_security.sql:9-20`, and the permission matrix in
> `docs/phase-2-model/12-threat-model.md:85-94`. Neither is an authoritative requirement source, so every persona is
> labelled `Implementation-Derived`. **No persona here is docket-mandated.** Where the implementation and the
> threat model disagree, the disagreement is recorded rather than smoothed over.

---

## 1. Actor inventory

Eight actors. Five are human roles, two are system roles, one is an external party.

| ID | Actor | Type | Seeded role | Requirements touched | Priority as an actor |
|:--|:--|:--|:--|--:|:--|
| `ACT-01` | Candidate / Job Seeker | Human | `candidate` | 31 | Must |
| `ACT-02` | Recruiter | Human | `recruiter` | 22 | Must |
| `ACT-03` | Gig Worker | Human | `candidate` | 16 | Must |
| `ACT-04` | Employer / Hiring Manager | Human | `employer` | 15 | Must |
| `ACT-05` | Agency Sourcing Consultant | Human | `consultant` | 8 | Should |
| `ACT-06` | Organisation Administrator | Human | `account_admin` | 9 | Should |
| `ACT-07` | Placement Officer (TPO) | Human | `placement_officer` | 4 | Could |
| `ACT-08` | Platform Operations | System | `super_admin`, `admin` | 46 | Must |
| `ACT-09` | Payment Gateway | External | — | 0 (boundary only) | Could |

### 1.1 Cast decisions and their reasons

| Decision | Reason |
|:--|:--|
| **Candidate and Gig Worker are separate actors** (`ACT-01`, `ACT-03`) although both map to the seeded `candidate` role | The schema supports one account holding both profiles simultaneously (REQ-008, both FKs target `core.user_account`), but their data, permissions and workflows differ sharply: `profile.candidate_profile` vs `gig.gig_worker_profile`; job applications vs gig assignments. Merging them would hide a real dual-identity requirement. |
| **Recruiter and Employer are separate actors** (`ACT-02`, `ACT-04`) although both can be organisation members | `recruitment.organization_member.organization_role` admits six roles (`owner`, `admin`, `recruiter`, `hiring_manager`, `billing_manager`, `consultant` — `db/migrations/007:137-147`). A recruiter *serves* client organisations (via `recruitment.recruiter_client_mapping`); an employer *is* the hiring client. Their permitted actions differ in the threat-model matrix. |
| **Agency Consultant is `ACT-05`, not `ACT-02`** | The threat model separates "Recruiter" and "Agency Consultant" as distinct columns (`docs/phase-2-model/12-threat-model.md:85-94`), and the schema enforces a consultant-specific rule that no recruiter is subject to (`sourcing.enforce_consultant_openness`). |
| **Organisation Administrator is `ACT-06`, distinct from Employer** | `account_admin` is a seeded role; the threat model's column is "Organization Admin" with its own wallet-management and audit-inspection rights that the hiring manager does not have. |
| **Platform Operations is `ACT-08` and covers both `super_admin` and `admin`** | The threat model treats "Platform Superadmin" as a column, but `admin` is a separate seeded role. They share a persona because their database-visible difference (global scope vs operational scope) is not expressed anywhere in the schema — no `role_permission` row distinguishes them. That missing distinction is recorded as a discrepancy in §5. |
| **Guest is not a separate actor** | `guest` is seeded (`012:14`) but appears in no other table, function, query or test anywhere in the repository — `grep` for it returns exactly one hit, the seed itself. There is no guest data, no guest workflow, and no guest requirement. It is recorded in §5 as a seeded-but-unused role. |
| **Payment Gateway is `ACT-09` but carries no requirement** | It is a boundary, not a stakeholder. Its requirements are integration contracts, which belong to the boundary documentation, not to the requirement register. It appears here so the cast is complete. |

### 1.2 Seeded roles with no actor

| Seeded role | Status |
|:--|:--|
| `guest` | Seeded at `012:14`. Referenced nowhere else in `db/`, `tests/`, `scripts/` or `db/queries/`. No persona, no requirement, no workflow. **Discrepancy recorded** — §5. |
| `admin` | Folded into `ACT-08`. |
| `super_admin` | Folded into `ACT-08`. |

---

## 2. Persona cards

### ACT-01 — Candidate / Job Seeker

| Field | Value |
|:--|:--|
| **ID / Name** | `ACT-01` — Candidate / Job Seeker |
| **Type** | Human |
| **Seeded role** | `candidate` (`012:18`) |
| **Goals** | Be discoverable by recruiters without oversharing; apply to jobs efficiently; keep control over who sees their profile and data; monetise expertise via gig work |
| **Responsibilities** | Maintain a complete profile and resume; declare skills and experience honestly; apply to relevant jobs; answer questionnaires; manage consent and privacy preferences; block unwanted recruiters or organisations; accept or decline gig assignments |
| **Data owned** | `profile.candidate_profile` (and children: skills, education, work experience, languages, projects, completion score), `profile.candidate_document`, `core.consent_record` (as subject), `core.user_block` (as blocker), `gig.gig_worker_profile` (if also working gigs) |
| **Permitted actions** | Edit own profile and documents; set profile visibility (`private`/`recruiters`/`public`); search published jobs; apply once per job; respond to job questionnaires; register as a gig worker; apply to gig requests; block users and organisations; revoke consent; request account deletion |
| **Prohibited actions** | Apply to the same job twice (BR-014); accept two overlapping gig assignments (BR-025); view another candidate's profile; view or modify a recruiter's pipeline; see an employer's private job; see another gig worker's assignment calendar; exceed the concurrent-device entitlement (BR-002) |
| **Frequency of use** | High — daily during an active job search; moderately for gig work; rarely for administrative settings |
| **Critical workflows** | WF-01 (sign in), WF-02 (build profile), WF-04 (discover and apply), WF-05 (application pipeline), WF-07 (gig work), WF-11 (consent and privacy), WF-10 (session and device management) |
| **Data sensitivity** | **Highest** — this actor's data is the platform's principal PII surface: contact details, work history, salary expectations, documents. Classified `[SENSITIVE]` and `[PERSONAL]` in `docs/phase-2-model/10-data-dictionary.md` |
| **Account ownership / stewardship** | The candidate is the data subject. `core.user_account` is the identity of record; `core.user_credential` holds the secret separately. GDPR-style rights (access, portability, erasure) attach here — none of which have a implemented mechanism (see OQ-011) |
| **Evidence** | `db/migrations/005`, `006`, `010`; `profile.candidate_profile` visibility CHECK (`005:32-33`); `core.user_block` (`012:170-215` region); `core.consent_record`; `recruitment.candidate_application` (`009`); `gig.gig_assignment` (`014`) |
| **Open questions** | **OQ-011** (retention and erasure), **OQ-003** (is gig work core or adjacent for this actor?) |

### ACT-02 — Recruiter

| Field | Value |
|:--|:--|
| **ID / Name** | `ACT-02` — Recruiter |
| **Type** | Human |
| **Seeded role** | `recruiter` (`012:17`) |
| **Goals** | Fill client vacancies quickly; find qualified candidates efficiently; manage a pipeline; avoid spending credits on unsuitable profiles |
| **Responsibilities** | Search and shortlist candidates; post and manage job requirements; review and advance applications; manage questionnaires; source candidates for clients; request profile downloads and spend credits; record pipeline outcomes |
| **Data owned** | `recruitment.job_posting` (where they are the poster), `recruitment.application_status_history` entries, `sourcing.outreach_batch` / `outreach_recipient`, `commercial.candidate_profile_download_history` rows, `recruitment.recruiter_client_mapping` |
| **Permitted actions** | Create and publish job postings for their own organisation or mapped client; search candidates within visibility and block rules (BR-010); advance applications through the pipeline (REQ-021); download unlocked candidate profiles against wallet credit; create outreach batches; record a funnel view; view their own organisation's data |
| **Prohibited actions** | View another organisation's job postings or applications (SEC-002 — **application-layer only today**); view a candidate who has blocked them; advance an application without writing a status-history row (BR-016); submit a candidate to a job that is not open to consultants (BR-019 — enforced for consultants, not for recruiters); exceed the device entitlement; see the platform-wide audit log (own organisation only, per the threat model) |
| **Frequency of use** | High — daily, often many hours per day |
| **Critical workflows** | WF-03 (post a job), WF-04 (search and shortlist), WF-05 (pipeline), WF-06 (client sourcing), WF-10 (session) |
| **Data sensitivity** | **High** — handles candidate PII including paid-for profile downloads |
| **Account ownership** | `recruitment.organization_member` with `organization_role` of `recruiter` (or `owner`/`admin`) for the serving organisation. Agency recruiters map to client organisations via `recruitment.recruiter_client_mapping` |
| **Evidence** | `db/migrations/008` (job posting), `009` (applications), `013` (recruiter-client mapping), `016` (outreach), `017:381-440` (download history); `docs/phase-2-model/12-threat-model.md:85-94` matrix columns "Recruiter" and "Download Unlocked Profiles / Deduct Credits" |
| **Open questions** | **OQ-002** (latency targets for search — the recruiter's most latency-sensitive action), **OQ-006** (audit coverage for credit deductions) |

### ACT-03 — Gig Worker

| Field | Value |
|:--|:--|
| **ID / Name** | `ACT-03` — Gig Worker |
| **Type** | Human |
| **Seeded role** | `candidate` (`012:18`) — the schema does **not** define a distinct gig-worker role |
| **Goals** | Find short-term project work; keep a calendar that prevents double-booking; build a reputation through ratings; get paid reliably |
| **Responsibilities** | Publish a gig-worker profile with services and rates; declare availability; apply to gig requests; honour assignment dates; accept or decline client requests; rate completed work |
| **Data owned** | `gig.gig_worker_profile`, `gig.gig_worker_availability`, `gig.gig_application`, `gig.gig_assignment` (as assignee), `gig.gig_rating` (as reviewer) |
| **Permitted actions** | Maintain gig profile, rates and verification state; apply to gig requests; accept assignments; decline overlapping work at the database level; rate completed assignments |
| **Prohibited actions** | Hold two active assignments with overlapping date ranges (BR-025, enforced by GiST exclusion); apply to a gig request twice; be assigned to an assignment that would overlap an existing one; accept an assignment in a currency or pricing basis inconsistent with the request |
| **Frequency of use** | Medium — episodic, clustered around project boundaries |
| **Critical workflows** | WF-07 (gig work end to end), WF-10 (session) |
| **Data sensitivity** | Medium — commercial rather than deeply personal, though contact and identity data overlap with `ACT-01` |
| **Account ownership** | Same `core.user_account` as `ACT-01` where the person is also a job seeker (REQ-008) |
| **Evidence** | `db/migrations/014:20-60` (profile), `014:130-195` (request), `014:197-260` (application), `014:265-330` (assignment), `014:316-321` (exclusion constraint), `014:380-410` (ratings) |
| **Open questions** | **OQ-003** (is the gig vertical core?), **AMB-05** (does `notification_delivery` model one notification or one channel attempt?) |

### ACT-04 — Employer / Hiring Manager

| Field | Value |
|:--|:--|
| **ID / Name** | `ACT-04` — Employer / Hiring Manager |
| **Type** | Human |
| **Seeded role** | `employer` (`012:16`) |
| **Goals** | Fill a vacancy with the right hire; control who may source for their roles; keep hiring spend within budget |
| **Responsibilities** | Define and publish vacancies; define the questionnaire; review shortlists; make offers; accept or decline consultant sourcing requests; raise gig requests for the business; pay for postings and profile access |
| **Data owned** | `recruitment.organization`, `recruitment.job_posting`, `recruitment.job_questionnaire`, `sourcing.consultant_sourcing_request` (as decision-maker), `gig.gig_request`, `recruitment.organization_member` |
| **Permitted actions** | Post jobs for their own organisation; publish and pause job status; answer a consultant sourcing request; accept or reject candidate submissions that a consultant made; raise a gig request; accept or reject a gig application |
| **Prohibited actions** | Access another organisation's data; accept a candidate submission from a consultant for a job not open to consultants; post a job with a partially-populated salary block (BR-012) |
| **Frequency of use** | Medium — per vacancy, rather than daily |
| **Critical workflows** | WF-03 (post a job), WF-05 (pipeline), WF-06 (agency sourcing), WF-07 (gig request) |
| **Data sensitivity** | High — sees candidate PII at shortlist stage and controls consent-adjacent decisions |
| **Account ownership** | `recruitment.organization_member` with `organization_role` = `owner` / `admin` / `hiring_manager` (`007:137-147`) |
| **Evidence** | `db/migrations/007`, `008`, `011`; `016:45-108` (sourcing request decision); `014:130-195` (gig request) |
| **Open questions** | **OQ-006** (audit coverage for hiring decisions), **AMB-04** (direction of the consultant sourcing relationship) |

### ACT-05 — Agency Sourcing Consultant

| Field | Value |
|:--|:--|
| **ID / Name** | `ACT-05` — Agency Sourcing Consultant |
| **Type** | Human |
| **Seeded role** | `consultant` (`012:18`) |
| **Goals** | Get access to jobs worth sourcing for; submit candidates who get hired; be paid for placements |
| **Responsibilities** | Request access to source for a job; submit candidates to an accepted job; run outreach campaigns; track submission outcomes to hired |
| **Data owned** | `sourcing.consultant_sourcing_request`, `sourcing.sourcing_submission`, `sourcing.outreach_batch`, `sourcing.outreach_recipient` |
| **Permitted actions** | Request to source for a job; submit candidates to jobs that are open to consultants and that the employer has accepted; batch outreach to candidates who have not blocked them (BR-021); advance a submission to `hired` |
| **Prohibited actions** | Submit to a job that is not open to consultants (BR-019 — **enforced by trigger** `trg_enforce_consultant_openness`); submit the same candidate to the same job twice (BR-020); source for a job whose request was not accepted; reach a blocked candidate |
| **Frequency of use** | Medium — campaign-driven |
| **Critical workflows** | WF-06 (agency sourcing), WF-10 (session) |
| **Data sensitivity** | High — handles candidate PII through submitted profiles and outreach |
| **Account ownership** | `recruitment.organization_member` with `organization_role` = `consultant`, or an independent consultant user associated with a `recruitment_agency` / `consultancy` organisation |
| **Evidence** | `db/migrations/016:45-108` (request), `016:110-133` (openness trigger — the only business rule in the schema enforced at the storage layer against a role), `016:136-203` (submission), `016:205-300` (outreach); `db/queries/06_sourcing_outreach_unblocked.sql`; `docs/phase-2-model/12-threat-model.md:92` — "Source for Private Jobs / **Denied (Trigger)**" |
| **Open questions** | **AMB-04** (request direction), **OQ-008** (which permissions a consultant holds) |

### ACT-06 — Organisation Administrator

| Field | Value |
|:--|:--|
| **ID / Name** | `ACT-06` — Organisation Administrator |
| **Type** | Human |
| **Seeded role** | `account_admin` (`012:13`) |
| **Goals** | Keep the organisation's account in good standing; control who within the organisation has access; manage spend; stay compliant |
| **Responsibilities** | Manage organisation members and their roles; manage licence seats and device entitlements; manage the organisation wallet and recharges; manage invoices and subscriptions; own the organisation's audit visibility; set consultant openness on postings |
| **Data owned** | `recruitment.organization`, `recruitment.organization_member`, `recruitment.organization_location`, `recruitment.organization_identifier`, `commercial.subscription_licence`, `commercial.licence_seat_allocation`, `commercial.wallet`, `commercial.subscription`, `commercial.invoice` |
| **Permitted actions** | Add and remove members; assign organisation roles; allocate licence seats within `max_users` (enforced by trigger `trg_enforce_licence_max_users`); recharge the wallet; issue invoices; view the organisation's audit events; set a posting's consultant-openness policy |
| **Prohibited actions** | Allocate more seats than `max_users` (BR — enforced by trigger); inspect another organisation's audit log; alter a wallet ledger row after the fact (SEC-005 — append-only); exceed `max_devices_per_user` indirectly by provisioning members beyond the licence |
| **Frequency of use** | Low — periodic administration |
| **Critical workflows** | WF-08 (organisation administration), WF-09 (licensing and entitlements), WF-10 (session) |
| **Data sensitivity** | High — controls financial records and the organisation's access grants |
| **Account ownership** | `recruitment.organization_member` with `organization_role` = `owner` or `admin` |
| **Evidence** | `db/migrations/007`, `013`; `015:52-132` (seat allocation + `trg_enforce_licence_max_users`); `017:248-340` (wallet, ledger); `017:167-216` (invoice); `docs/phase-2-model/12-threat-model.md:93` — "Manage Wallet & Recharge / **Full**"; `docs/phase-2-model/12-threat-model.md:94` — "Inspect Append-Only Audit Logs / Own Org Only" |
| **Open questions** | **OQ-006** (audit coverage for wallet operations and role grants), **AMB-02** (wallet semantics) |

### ACT-07 — Placement Officer (Training and Placement Officer)

| Field | Value |
|:--|:--|
| **ID / Name** | `ACT-07` — Placement Officer (TPO) |
| **Type** | Human |
| **Seeded role** | `placement_officer` (`012:19`) |
| **Goals** | Place students from an educational institution into roles; track campus placement outcomes |
| **Responsibilities** | Manage campus job postings and applications; represent the educational institution |
| **Data owned** | `recruitment.job_posting` (institution's postings), `recruitment.candidate_application` where `application_source = 'campus'` |
| **Permitted actions** | Post campus roles on behalf of an `educational_institution` organisation; review applications with `application_source = 'campus'` |
| **Prohibited actions** | Act outside the institution's scope; access non-campus applications for placement purposes |
| **Frequency of use** | Low — seasonal, aligned to placement cycles |
| **Critical workflows** | WF-03 (post a campus job), WF-05 (campus application pipeline) |
| **Data sensitivity** | High — student data is a regulated category in most jurisdictions |
| **Account ownership** | `recruitment.organization_member` in an `educational_institution` organisation (`007:41-47`) |
| **Evidence** | `db/migrations/012:19` (seed only); `db/migrations/009:64-72` (`application_source` CHECK includes `'campus'`); `db/migrations/007:41-47` (`organization_type` includes `'educational_institution'`) |
| **Open questions** | **OQ-001** — this role is the single strongest hint that the missing docket described a campus/education vertical, which the repository implements only partially (no `education.enrollment`, no placement-outcome table) |

### ACT-08 — Platform Operations

| Field | Value |
|:--|:--|
| **ID / Name** | `ACT-08` — Platform Operations (Super Admin / Admin) |
| **Type** | System (with human operators) |
| **Seeded role** | `super_admin` (`012:11`), `admin` (`012:12`) |
| **Goals** | Keep the platform available and correct; protect data integrity; support tenants; meet audit and compliance obligations |
| **Responsibilities** | Run migrations; seed reference data; generate and validate test data; run the benchmark suite; back up and restore; administer organisations, licences and subscriptions out of band; inspect the platform-wide audit log; refresh analytical marts |
| **Data owned** | `audit.audit_event` (reader, not writer), `analytics.*` marts, `master.*` reference data (writer at seed time only), `commercial.subscription_plan` |
| **Permitted actions** | Apply migrations; run the validator and benchmark harness; perform a restore into `talentra_recovery_test`; read any table; read the full audit log; refresh marts; provision licences and seats |
| **Prohibited actions** | Modify or delete a wallet ledger row, an audit event, or a download-history row (SEC-005 — append-only triggers); alter the schema outside a migration |
| **Frequency of use** | Low-to-medium — episodic operational and release activity |
| **Critical workflows** | WF-08 (organisation administration), WF-09 (licensing), WF-10 (session), WF-12 (backup and restore), WF-13 (mart refresh) |
| **Data sensitivity** | Highest — full-database read access to PII and financial records |
| **Account ownership** | `core.user_account` with the `super_admin` or `admin` role; the threat model's `CREATE ROLE talentra_admin ... SUPERUSER` is a **proposed** database role (`docs/phase-2-model/12-threat-model.md:80`), not a deployed one |
| **Evidence** | `db/migrations/001`–`019`; `scripts/validate_data.py`, `scripts/run_benchmarks.py`, `scripts/run_all_tests.py`, `scripts/backup_restore.sh`; `019:308-315` (`analytics.refresh_reporting_marts`); `docs/phase-2-model/12-threat-model.md:80,94` |
| **Open questions** | **OQ-010** (who owns the mart-refresh job), **OQ-007** (RPO/RTO versus the single-instance topology), **OQ-011** (retention) |

### ACT-09 — Payment Gateway (external)

| Field | Value |
|:--|:--|
| **ID / Name** | `ACT-09` — Payment Gateway |
| **Type** | External system |
| **Seeded role** | — |
| **Goals** | Authorise, capture and refund payments on the platform's behalf |
| **Responsibilities** | Return a `gateway_order_id` for an authorisation; return a `gateway_refund_ref` for a refund; report settlement status |
| **Data owned** | Nothing inside Talentra — only the identifiers returned to it |
| **Permitted actions** | Nothing directly. The database stores `commercial.payment_order.gateway_order_id` and `commercial.payment_refund.gateway_refund_ref` as opaque references |
| **Prohibited actions** | — (boundary) |
| **Frequency of use** | Per transaction |
| **Critical workflows** | WF-09 (licensing and entitlements) — the commercial path |
| **Data sensitivity** | High — handles card data that never enters this database (the PCI scope boundary) |
| **Account ownership** | Not an account. Represented only by foreign-key-free identifier columns |
| **Evidence** | `db/migrations/017:126` (`gateway_order_id` unique), `017:228` (`gateway_refund_ref` unique), `017:146-156` (payment order status machine); `docs/phase-4-platform/22-integration-boundaries.md` §Payment Gateway boundary |
| **Open questions** | **OQ-002** (payment confirmation SLA), and the Phase 2E finding that `docs/phase-4-platform/22-integration-boundaries.md` still describes PCI-DSS "zero-storage compliance" without an SAQ (CF-05) |

---

## 3. Actor → requirement coverage

| Actor | Requirements | Business rules | Security | Requirements most associated |
|:--|--:|--:|--:|:--|
| `ACT-01` Candidate | 31 | 14 | 8 | REQ-008…REQ-014, REQ-019, REQ-020, REQ-022, REQ-029, REQ-032, REQ-033 |
| `ACT-02` Recruiter | 22 | 12 | 5 | REQ-014, REQ-017, REQ-021, REQ-023, REQ-024, REQ-028, REQ-030 |
| `ACT-03` Gig Worker | 16 | 8 | 4 | REQ-008, REQ-029, REQ-031, REQ-032, REQ-033, REQ-034 |
| `ACT-04` Employer | 15 | 9 | 5 | REQ-015, REQ-017, REQ-025, REQ-027, REQ-030, REQ-031 |
| `ACT-05` Agency Consultant | 8 | 5 | 3 | REQ-025, REQ-026, REQ-027, REQ-028 |
| `ACT-06` Org Administrator | 9 | 5 | 6 | REQ-015, REQ-016, REQ-004, REQ-005, REQ-030 |
| `ACT-07` Placement Officer | 4 | 2 | 1 | REQ-009, REQ-020, REQ-022 |
| `ACT-08` Platform Operations | 46 | 18 | 14 | All OPS-*, DATA-*, NFR-*; SEC-003, SEC-005, SEC-014 |

**Every requirement has at least one actor.** Coverage is computed from the `Actor(s)` columns in
[`docs/phase-1-discover/01-requirements.md`](01-requirements.md) §1–§6. See that document §8.2.

### 3.1 Actors with no exclusive requirement

No actor is redundant. However, three actors have **no requirement that they alone satisfy** — a fact worth
recording because it suggests their scope may be narrower than their role definition:

| Actor | Observation |
|:--|:--|
| `ACT-07` Placement Officer | Appears only through `application_source = 'campus'` and `organization_type = 'educational_institution'`. There is no placement-outcome, enrolment, or campus-specific workflow in the schema. The role is seeded; the vertical is a stub. |
| `ACT-09` Payment Gateway | By design — a boundary, not a requirement owner. |
| `ACT-06` Organisation Administrator | Every requirement it touches (`REQ-015`, `REQ-016`, `REQ-004`, `REQ-005`) is also owned by another actor. Its distinct power — licence seats, wallet, invoices — is enforced by triggers and constraints rather than by a requirement of its own. |

---

## 4. Role ↔ actor reconciliation

| Seeded role (`core.role`) | Description in the seed | Maps to actor | Reconciled? |
|:--|:--|:--|:--|
| `super_admin` | System Super Administrator with full global rights | `ACT-08` | Partially — global rights are described but not enforced; no permission rows exist |
| `admin` | Platform Administrator for operational support | `ACT-08` | Partially — no schema-level distinction from `super_admin` |
| `account_admin` | Organization Account Administrator | `ACT-06` | Partially — see §5 D-04 |
| `guest` | Unauthenticated or pending guest user | *(none)* | **No** — see §5 D-01 |
| `candidate` | Registered job seeker or gig worker | `ACT-01`, `ACT-03` | **Partially** — the role conflates two actors; no distinct gig-worker role exists (§5 D-02) |
| `employer` | Direct employer hiring manager or admin | `ACT-04` | Partially — the role conflates the hiring manager with the organisation admin |
| `recruiter` | Corporate or agency recruiter | `ACT-02` | Partially — the role conflates corporate and agency recruiters, which the schema distinguishes via `recruitment.recruiter_client_mapping` |
| `consultant` | Freelance sourcing consultant | `ACT-05` | Yes — one actor, one role, and the only role with a storage-layer rule attached to it |
| `placement_officer` | Training and Placement Officer (TPO) for campus | `ACT-07` | Partially — the role exists; the vertical does not |

**Coverage:** 9 seeded roles → 8 actors, 1 unused (`guest`). 8 of 9 roles map to at least one actor.

---

## 5. Role-permission reconciliation — the central discrepancy

### 5.1 The facts

| Fact | Evidence |
|:--|:--|
| `core.role` is defined and **seeded with 9 rows** | `db/migrations/012:9-20` |
| `core.permission` is defined | `db/migrations/012:24-40` |
| `core.role_permission` is defined | `db/migrations/012:46-66` |
| **`core.permission` contains 0 rows** — `grep "INSERT INTO core.permission" db/ scripts/` returns **0 matches** | verified |
| **`core.role_permission` contains 0 rows** — `grep "INSERT INTO core.role_permission" db/ scripts/` returns **0 matches** | verified |
| `core.user_role` associates users to roles and **is** populated by the data generator | `db/migrations/002:106-130`; `scripts/generate_data.py` |
| `core.permission.code` has a format CHECK: `^[a-z][a-z0-9_.]+[a-z0-9]$` — i.e. `module.verb` | `012:34-35` |

**Consequence:** the RBAC model is **structurally complete but semantically empty**. There is a role
catalogue, a permission catalogue with a well-designed naming convention, a mapping table, and a user-role
assignment table — and the middle two contain nothing. `core.user_role` assigns roles that grant no
permissions, because no permission exists to grant.

### 5.2 Recorded discrepancies

| # | Discrepancy | Severity | Evidence | Impact |
|:--|:--|:--|:--|:--|
| D-01 | `guest` role is seeded but referenced nowhere else in the entire repository | Low | `grep -rn "guest" db/ tests/ scripts/` → 1 hit, the seed itself | Dead catalogue entry. Either a role for a workflow that was never built, or a leftover. Cannot be resolved without the docket (**OQ-001**) |
| D-02 | No `gig_worker` role exists; gig workers use `candidate` | Medium | `012:18`; `db/migrations/014` has no role reference | A gig worker and a job seeker share one role, so a permission scheme cannot grant "accept gig assignment" without also granting "apply to job". The persona split in §1.1 cannot be expressed in the RBAC model |
| D-03 | `recruiter` conflates corporate and agency recruiters | Medium | `012:17`; contrast `recruitment.recruiter_client_mapping` (`013:193`) and `organization_type = 'recruitment_agency'` (`007:41-47`) | A permission that should be agency-only (e.g. "submit candidate submission") would leak to corporate recruiters |
| D-04 | `employer` and `account_admin` overlap | Low | `012:13,16`; `organization_role` allows both `admin` and `hiring_manager` (`007:137-147`) | Over-grant risk: an organisation admin would inherit hiring-manager permissions. Resolvable by scoping permissions per `organization_role` as well as per role |
| D-05 | `super_admin` and `admin` are indistinguishable in the schema | Medium | `012:11-12`; `core.role` has only `name`, `description`, `is_system_role` — no scope column | Global scope is asserted in prose only. A least-privilege scheme cannot distinguish "operational support" from "full global rights" without a scope attribute |
| D-06 | `core.permission` module vocabulary is undefined | Medium | `012:29` (`module VARCHAR(50)`) — no seed, no enumeration | The `module.action` code convention is unconstrained, so permission codes could sprawl into a dozen inconsistent module names with nothing to reconcile against |
| D-07 | `docs/phase-2-model/12-threat-model.md` presents a permission matrix as if it were enforced | **High** | `docs/phase-2-model/12-threat-model.md:85-94` — "Application-Level Permissions Matrix" | The matrix is the de facto specification of what each role may do. It is not implemented. Reading it as enforcement is the single most likely misreading of this repository |
| D-08 | The proposed least-privilege database roles are not deployed | **High** | `docs/phase-2-model/12-threat-model.md:80` — `CREATE ROLE talentra_admin WITH LOGIN SUPERUSER PASSWORD '...'` is inside a *proposed* section; no `CREATE ROLE` or `GRANT` exists in `db/migrations/` | Even with permissions seeded, nothing in the database prevents `talentra_app` from writing to `commercial.wallet_ledger` |

### 5.3 Desired state — `core.permission` catalogue (specified, NOT seeded)

> **This phase must not seed these tables** (explicit task constraint). The contents below are the
> *specified desired state* for the Phase 2 implementation, expressed in the schema's own
> `module.verb` convention (derived from `012:34-35`).

| Permission code | Module | Permission name | Description | Roles that would hold it |
|:--|:--|:--|:--|:--|
| `profile.view.own` | profile | View own profile | Read the signed-in user's own candidate profile | `candidate`, `admin`, `super_admin` |
| `profile.edit.own` | profile | Edit own profile | Modify the signed-in user's own candidate profile and documents | `candidate`, `admin`, `super_admin` |
| `profile.view.search` | profile | Search candidate profiles | Query the candidate search index within visibility and block rules | `recruiter`, `employer`, `consultant`, `admin`, `super_admin` |
| `profile.download.unlocked` | profile | Download unlocked profile | Retrieve a full candidate profile, deducting wallet credit | `recruiter`, `employer`, `consultant`, `admin`, `super_admin` |
| `job.view.published` | job | View published jobs | Read job postings in `published` state | all roles |
| `job.manage.own_org` | job | Manage own organisation's jobs | Create, edit, publish, pause and close job postings for the actor's organisation | `recruiter`, `employer`, `account_admin`, `admin`, `super_admin` |
| `application.submit` | application | Submit job application | Create a job application as a candidate | `candidate`, `admin`, `super_admin` |
| `application.manage` | application | Manage application pipeline | Advance, reject or withdraw applications, and record stage history | `recruiter`, `employer`, `account_admin`, `admin`, `super_admin` |
| `sourcing.request.create` | sourcing | Request to source for a job | Raise a consultant sourcing request | `consultant`, `recruiter`, `admin`, `super_admin` |
| `sourcing.request.decide` | sourcing | Decide sourcing request | Accept or decline a consultant sourcing request | `employer`, `account_admin`, `admin`, `super_admin` |
| `sourcing.submission.create` | sourcing | Submit candidate to a job | Create a consultant sourcing submission | `consultant`, `admin`, `super_admin` |
| `sourcing.outreach.dispatch` | sourcing | Dispatch outreach batch | Create and dispatch an outreach batch to unblocked candidates | `consultant`, `recruiter`, `admin`, `super_admin` |
| `gig.profile.manage` | gig | Manage gig worker profile | Maintain gig profile, services, rates and availability | `candidate`, `admin`, `super_admin` |
| `gig.request.manage` | gig | Manage gig request | Raise, edit and close a gig request | `recruiter`, `employer`, `admin`, `super_admin` |
| `gig.assignment.manage` | gig | Manage gig assignment | Award, schedule, complete and terminate assignments | `recruiter`, `employer`, `admin`, `super_admin` |
| `organization.manage` | organization | Manage organisation | Edit organisation details, locations, identifiers and hierarchy | `account_admin`, `admin`, `super_admin` |
| `organization.member.manage` | organization | Manage organisation members | Add, remove and re-role organisation members | `account_admin`, `admin`, `super_admin` |
| `wallet.view.own_org` | wallet | View own organisation's wallet | Read the wallet balance and ledger for the actor's organisation | `account_admin`, `admin`, `super_admin` |
| `wallet.manage.own_org` | wallet | Manage own organisation's wallet | Recharge the wallet and record payments | `account_admin`, `admin`, `super_admin` |
| `subscription.manage` | subscription | Manage subscription | Change subscription, invoice and licence state | `account_admin`, `admin`, `super_admin` |
| `licence.seat.manage` | licence | Manage licence seats | Allocate and release licence seats | `account_admin`, `admin`, `super_admin` |
| `consent.manage.own` | consent | Manage own consent and privacy | Grant, withdraw and review personal consent and notification preferences | `candidate`, `admin`, `super_admin` |
| `block.manage.own` | block | Manage own block list | Block and unblock users and organisations | `candidate`, `admin`, `super_admin` |
| `session.manage.own` | session | Manage own sessions | List and revoke the actor's own sessions and devices | all roles |
| `audit.view.own_org` | audit | View own organisation's audit events | Read audit events scoped to the actor's organisation | `account_admin`, `admin`, `super_admin` |
| `audit.view.all` | audit | View all audit events | Read the platform-wide audit log | `admin`, `super_admin` |
| `platform.administer` | platform | Administer the platform | Apply migrations, seed reference data, run validation and benchmarks, restore backups | `super_admin` |
| `analytics.view` | analytics | View analytical marts | Query the reporting marts | `account_admin`, `admin`, `super_admin` |
| `mart.refresh` | analytics | Refresh reporting marts | Execute `analytics.refresh_reporting_marts` | `admin`, `super_admin` |

**29 proposed permissions across 9 modules.** Every code satisfies the schema's own
`^[a-z][a-z0-9_.]+[a-z0-9]$` CHECK. The proposed module vocabulary is:
`profile`, `job`, `application`, `sourcing`, `gig`, `organization`, `wallet`, `subscription`, `licence`,
`consent`, `block`, `session`, `audit`, `platform`, `analytics` — 15 modules, closing D-06 by fixing the
vocabulary in the same document that fixes it.

### 5.4 Desired state — `core.role_permission` assignments (specified, NOT seeded)

Counting from §5.3:

| Role | # permissions | Notable holdings |
|:--|--:|:--|
| `candidate` | 7 | Own-profile, consent, block, session, gig profile, job applications |
| `recruiter` | 10 | Search, download, own-org job management, pipeline, outreach, gig request/assignment, published jobs, session |
| `employer` | 9 | Search, download, own-org job management, pipeline, sourcing decision, gig request/assignment, published jobs, session |
| `consultant` | 8 | Search, download, sourcing request/submission/outreach, own-org job management, published jobs, session |
| `account_admin` | 12 | Organisation, member, wallet, subscription, licence seat, own-org audit, analytics, pipeline, session |
| `admin` | 21 | Everything except `platform.administer` and `audit.view.all` |
| `super_admin` | 29 | All permissions |
| `guest` | 1 | `job.view.published` — the only permission that makes sense for an unauthenticated visitor, and the minimum needed to justify keeping the role |
| *unassigned* | 0 | Every proposed permission is held by at least one role |

**Note on the `guest` row.** This is the one place where the proposed state gives `guest` a purpose, and it
is a proposal, not a finding. If the docket shows guest access was never intended, the correct fix is to
remove the seeded role — not to leave a dead role behind.

### 5.5 Threat-model matrix reconciliation

The threat model at `docs/phase-2-model/12-threat-model.md:85-94` is the closest thing to a permission specification that
exists. Reconciling it against the schema:

| Threat-model row | Column | Schema support | Reconciled? |
|:--|:--|:--|:--|
| Manage Own Profile / CV | Candidate **Full**, others None, Superadmin Read | `profile.candidate_profile.user_account_id` FK; no permission gating | **Partially** — ownership is structural (a FK), but "none" for others is not enforced by any check; it is enforced only if the query filters on `user_account_id` |
| Search Published Jobs | All roles Read | `job_posting.job_status` CHECK | **Partially** — the status is enforced; the role is not |
| Post Job Requirements | Recruiter/OrgAdmin Full (Own Org), Superadmin Full | `job_posting.organization_id` FK; `organization_member` | **Partially** — "Own Org" is application-layer only (SEC-002) |
| Review Candidate Applications | Candidate Own Only, Recruiter/OrgAdmin Full (Own Org), Consultant Submissions Only | `candidate_application` FKs; `sourcing_submission` | **Partially** — "Consultant Submissions Only" is the one row with storage-layer support (`trg_enforce_consultant_openness`), and even that governs *submission*, not *review* |
| Download Unlocked Profiles | Recruiter/Consultant/OrgAdmin Deduct Credits, Superadmin Full | `commercial.candidate_profile_download_history` + `credit_deduction_amount` + `wallet_ledger_id` | **No** — the history table records a deduction, but nothing computes the fee, checks the balance, or performs the deduction. The fee logic is in the application layer, which does not exist here |
| Source for Private Jobs | Consultant **Denied (Trigger)**, others Assigned Only | `trg_enforce_consultant_openness` (`016:110-133`) | **Yes** — the only fully reconciled row |
| Manage Wallet & Recharge | Recruiter View Balance, OrgAdmin Full, Superadmin Full | `commercial.wallet`, `wallet_ledger` (append-only) | **Partially** — balances are stored; the permission split is not enforced |
| Inspect Append-Only Audit Logs | OrgAdmin Own Org Only, Superadmin Full | `audit.audit_event` (no `organization_id` column) | **No** — the audit table has no organisation scope column, so "Own Org Only" is not expressible as a query on this schema |

**Reconciliation summary: 1 of 8 matrix rows is fully enforced at the storage layer.**

---

## 6. Open questions arising from persona work

| # | Question | Owner | Impact |
|:--|:--|:--|:--|
| **PQ-01** | Is the gig-worker persona (`ACT-03`) a distinct product actor or an extension of the candidate persona (`ACT-01`)? | Product owner | Determines whether a `gig_worker` role is added (D-02) and whether the gig vertical is core (**OQ-003**) |
| **PQ-02** | Does `guest` represent a real anonymous-visitor capability, and if so what can a guest see? | Product owner | Determines whether the role is removed or given `job.view.published` (§5.4). Currently dead (D-01) |
| **PQ-03** | Is the campus/education vertical (`ACT-07`) part of the product? | Product owner | The role and two enum values exist; the vertical does not. **OQ-001** is likely to answer this |
| **PQ-04** | Should the audit log carry an `organization_id` scope column so "Own Org Only" becomes enforceable? | Security owner | Without it, one of the eight threat-model matrix rows is unimplementable as written |
| **PQ-05** | Where does the profile-download fee calculation live? | Product + platform | `candidate_profile_download_history.credit_deduction_amount` records the outcome; nothing computes it. If it belongs in the database, it is a missing function; if it belongs in the application, it is out of scope (X-01) |
| **PQ-06** | Should `super_admin` and `admin` differ at the database level? | Security owner | D-05 — needs either a scope attribute on `core.role` or a separate permission set |
| **PQ-07** | Is `recruitment.organization_member.organization_role` the intended second dimension of authorisation, alongside `core.role`? | Security owner | D-04. The matrix's "Own Org" column implies organisation scope is separate from role |

---

## 7. Evidence index

| Evidence | Path / line | Supports |
|:--|:--|:--|
| Seeded role catalogue (9 roles) | `db/migrations/012:9-20` | §4, §5 |
| `core.permission` DDL + code CHECK | `db/migrations/012:24-40` | §5.1, §5.3 |
| `core.role_permission` DDL | `db/migrations/012:46-66` | §5.1 |
| `core.user_role` DDL | `db/migrations/002:106-130` | §5.1 |
| `core.user_credential` DDL | `db/migrations/012:79-100` | ACT-01 (credential separation) |
| `core.consent_record` | `db/migrations/012` §5 | ACT-01, ACT-03 |
| `core.user_block` (target XOR + self-block CHECK) | `db/migrations/012` §6 | ACT-01, SEC-010 |
| `audit.audit_event` DDL | `db/migrations/012` §7 | SEC-003, D-04 |
| Permission matrix | `docs/phase-2-model/12-threat-model.md:85-94` | §5.5 |
| RLS proposals (not implemented) | `docs/phase-2-model/12-threat-model.md:98-149` | SEC-002 |
| Least-privilege role proposal (not implemented) | `docs/phase-2-model/12-threat-model.md:55-81` | SEC-014, D-08 |
| Scope and limitations table | `docs/phase-2-model/12-threat-model.md:243-256` | D-07, D-08, SEC-013 |
| `organization_type` enum | `db/migrations/007:39-47` | ACT-04, ACT-07 |
| `organization_member.organization_role` enum | `db/migrations/007:137-147` | ACT-02, ACT-04, ACT-06, D-04 |
| `application_source` enum | `db/migrations/009:64-72` | ACT-07 |
| Profile visibility enum | `db/migrations/005:32-33` | ACT-01 |
| Consultant openness trigger | `db/migrations/016:110-133` | ACT-05, §5.5 |
| Licence seat trigger | `db/migrations/015:97-132` | ACT-06 |
| Gig overlap exclusion constraint | `db/migrations/014:316-321` | ACT-03, ACT-04 |
| `candidate_profile_download_history` | `db/migrations/017:381-440` | ACT-02, ACT-06, PQ-05 |
| `gateway_order_id` / `gateway_refund_ref` | `db/migrations/017:126,228` | ACT-09 |
| Notification channels | `db/migrations/018:274-275` | ACT-01, AMB-05 |

---

## 8. Related documents

| Document | Contains |
|:--|:--|
| [`docs/phase-1-discover/01-requirements.md`](01-requirements.md) | The requirement register, with actor columns |
| [`docs/phase-1-discover/01-scope-assumptions.md`](01-scope-assumptions.md) | Assumptions A-001…A-008, open questions OQ-001…OQ-011 |
| [`docs/phase-1-discover/03-feature-inventory.md`](03-feature-inventory.md) | Feature register, actor links |
| [`docs/phase-1-discover/04-nfr-register.md`](04-nfr-register.md) | NFR register with actor links |
| [`docs/phase-1-discover/05-workflows.md`](05-workflows.md) | The 14 core workflows |
| [`docs/phase-1-discover/05-exceptions.md`](05-exceptions.md) | Exception catalogue |
| [`docs/phase-1-discover/05-audit-event-matrix.md`](05-audit-event-matrix.md) | Audit coverage per sensitive action |
| [`docs/source/README.md`](../source/README.md) | Source index and provenance rules |
