# Talentra — Feature Inventory

**Phase:** 1 — Discover
**Step:** 3 — Feature Inventory & Classification
**Status:** **Reconciled against the docket** on 2026-10-23 ([`01-docket-reconciliation.md`](01-docket-reconciliation.md)); originally written before the docket was available. Competitor coverage (Naukri, Monster, LinkedIn) is still from general knowledge, not official sources, and is unverified.
**Authored:** 2026-10-21

---

## 1. How to read this document

Each feature carries three independent classifications, because conflating them is the most common way a
feature register becomes useless:

| Classification | Axis | Question it answers |
|:--|:--|:--|
| **MoSCoW priority** | Necessaryness | Can the product ship without it? |
| **Feature class** | Market position | Is it table stakes, or a differentiator? |
| **Implementation status** | Delivery reality | Does it work today? |

A feature can be a **Must-have table stake that is not implemented** (SEC-001's RBAC content, for example),
or a **Could-have differentiator that is fully implemented**. Priority is never inferred from status.

**Feature class definitions**

| Class | Definition |
|:--|:--|
| **Must-have** | The category requires it to be considered viable. Its absence disqualifies the product. |
| **Should-have** | Expected by buyers; absence is noticed and penalised but does not disqualify. |
| **Differentiator** | A capability a competitor structurally lacks; its presence is a reason to choose Talentra. |
| **Optional** | Genuinely discretionary — a bonus that changes no buying decision. |

**Implementation status vocabulary**

| Status | Meaning |
|:--|:--|
| **Implemented** | A verifiable database object enforces it (DDL constraint, trigger, function, or query). |
| **Partial** | Some of the behaviour is enforced; a named part is missing. |
| **Documented only** | Described in prose; no enforcing object exists. |
| **Planned** | Identified as needed; not designed or built. |

**ID scheme:** `FEAT-NNN`. 25 features.

---

## 2. Feature register

### 2.1 Identity, access and platform governance

| ID | Feature | Requirements | Actors | Workflows | MoSCoW | Class | Status | Evidence | Acceptance criterion |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| FEAT-001 | Unified talent identity (one account, candidate profile + gig profile + applications) | REQ-001, REQ-002, REQ-003, REQ-008 | ACT-01, ACT-03 | WF-01, WF-02 | Must | Must-have | **Implemented** | `db/migrations/002:8-56`; `005`; `014`; `012:79-100` | One `core.user_account` can be referenced by both a candidate profile and a gig worker profile without duplication |
| FEAT-002 | Device-limited concurrent sessions with licence-derived entitlement | REQ-004, REQ-005 | ACT-01…ACT-08 | WF-01, WF-09 | Must | Must-have | **Implemented** | `db/migrations/015:134-240` (`core.user_device`, `core.create_session_with_device_limit` with `FOR UPDATE`) | A login on a device beyond the entitlement is refused; the refusal writes a `device.limit_exceeded` audit event |
| FEAT-003 | Session revocation with audit trail | REQ-006 | ACT-01, ACT-08 | WF-10 | Must | Must-have | **Implemented** | `db/migrations/012:295-330` (`core.revoke_user_session`) | Revocation terminates the session and writes a `session.revoked` audit event |
| FEAT-004 | Consent records and per-category privacy preferences | REQ-007 | ACT-01, ACT-03, ACT-08 | WF-11 | Should | Should-have | **Implemented** | `db/migrations/012` §5; `018:121-190` | A consent row exists per subject and category with a state and a timestamp |
| FEAT-005 | Dual-vertical identity (recruitment + gig under one login) | REQ-008 | ACT-01, ACT-03 | WF-02, WF-07 | Must | **Differentiator** | **Implemented** | `db/migrations/005`; `014:20-60` — both FK to `core.user_account` | A single account holds both profiles and appears in both verticals' searches |
| FEAT-006 | Canonical reference taxonomies shared across all domains | REQ-009 | ACT-01, ACT-02, ACT-07, ACT-08 | WF-01, WF-02, WF-03 | Must | Must-have | **Implemented** | `db/migrations/003`, `004` — 10 master tables seeded | All 10 master tables are populated and referenced by at least one operational schema |
| FEAT-019 | Role-based access control with granular permissions | SEC-001, SEC-002 | ACT-01…ACT-08 | WF-03, WF-08, WF-10 | Must | Must-have | **Implemented** | `db/migrations/021` — 29 permissions and 107 role-permission rows seeded; `tests/test_access_control.sql` | Roles grant permissions; the database roles and row-level security enforce them |
| FEAT-020 | Row-level multi-tenant isolation | SEC-002 | ACT-02, ACT-04, ACT-05 | WF-03, WF-05, WF-06, WF-08 | Must | **Differentiator** | **Implemented** | `db/migrations/021`, `030` — 60 row-level-security policies; `tests/test_access_control.sql`, `tests/test_candidate_privacy.sql` | A recruiter cannot read another organisation's job postings or wallets at the database layer |
| FEAT-021 | Least-privilege database roles (application / reporting / admin) | SEC-014 | ACT-08 | WF-08, WF-12, WF-13 | Should | **Differentiator** | **Implemented** | `db/migrations/021` — roles `talentra_app`, `_readonly`, `_auditor`, `_analyst`, `_support`; grants and `REVOKE`s; `tests/test_access_control.sql` | The application role holds no UPDATE/DELETE on the ledgers; since migration 036 it cannot write wallets or ledger rows directly |
| FEAT-022 | Append-only, tamper-evident audit ledger | SEC-003, SEC-005 | ACT-01, ACT-02, ACT-04, ACT-05, ACT-06, ACT-08 | WF-08, WF-10, WF-14 | Must | **Differentiator** | **Implemented** | `db/migrations/012`, `029` — append-only audit trail; 21 action codes in 14 classes; `tests/test_audit_coverage.sql` | Every sensitive action is audited and the audit rows cannot be altered. Coverage is 14 of 14 classes — see [`05-audit-event-matrix.md`](05-audit-event-matrix.md) |
| FEAT-023 | Relational user/organisation block list with XOR target semantics | SEC-010 | ACT-01, ACT-02, ACT-04 | WF-04, WF-11, WF-14 | Must | **Differentiator** | **Implemented** | `db/migrations/012` §6 (`core.user_block`, `ck_user_block_target_xor`, `ck_user_block_not_self`) | A candidate blocks a user or an organisation (never both, never neither); visibility flips false for the blocked party |

### 2.2 Candidate and gig talent

| ID | Feature | Requirements | Actors | Workflows | MoSCoW | Class | Status | Evidence | Acceptance criterion |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| FEAT-007 | Candidate profile with skills, education, experience, languages and projects | REQ-010, REQ-013 | ACT-01, ACT-03 | WF-02 | Must | Must-have | **Implemented** | `db/migrations/005`, `010` | Profile row with status, visibility and experience years; all child tables FK to it |
| FEAT-008 | Profile completeness scoring | REQ-011 | ACT-01, ACT-03 | WF-02 | Should | Should-have | **Implemented** | `db/migrations/010:245-271` | One completion row per profile; score bounded 0.00–100.00 |
| FEAT-009 | Resume/document management with checksums | REQ-012 | ACT-01, ACT-03 | WF-02 | Must | Must-have | **Implemented** | `db/migrations/006` | One primary resume per candidate; MIME and size constrained; SHA-256 checksum stored |
| FEAT-010 | Recruiter-side multicriteria candidate search | REQ-014 | ACT-02, ACT-04, ACT-05 | WF-04, WF-14 | Must | Must-have | **Implemented** | `db/queries/01_candidate_multicriteria_search.sql` | Returns matching candidates by skill, experience, city and visibility, honouring block rules |
| FEAT-016 | Job-feed matching (role, city, arrangement, salary bounds) | REQ-023 | ACT-01, ACT-03 | WF-04 | Must | Must-have | **Implemented** | `db/queries/02_job_feed_matching.sql` | A candidate sees published jobs matching their profile and salary expectations |
| FEAT-025 | Gig worker profile, availability and verification state | REQ-029 | ACT-01, ACT-03 | WF-07 | Should | Should-have | **Implemented** | `db/migrations/014:20-60` | Profile references `core.user_account`; rating bounded 1.00–5.00; verification state constrained |
| FEAT-026 | Gig request, application, assignment lifecycle | REQ-030, REQ-031, REQ-033 | ACT-03, ACT-04 | WF-07 | Should | Should-have | **Implemented** | `db/migrations/014:130-330` | Request, application and assignment each carry a constrained status; `decided_at` present iff decided |
| FEAT-027 | Double-booking prevention via exclusion constraint | REQ-032 | ACT-03, ACT-04 | WF-07 | Must | **Differentiator** | **Implemented** | `db/migrations/014:316-321` (`ex_gig_assignment_no_overlap`, `btree_gist`) | An overlapping active assignment raises `ExclusionViolation` (23P01) before commit |
| FEAT-028 | Two-sided gig ratings | REQ-034 | ACT-03, ACT-04 | WF-07 | Could | Optional | **Implemented** | `db/migrations/014:380-410` | Ratings scored 1–5 on quality and communication |

### 2.3 Recruitment pipeline

| ID | Feature | Requirements | Actors | Workflows | MoSCoW | Class | Status | Evidence | Acceptance criterion |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| FEAT-011 | Corporate organisation, hierarchy, locations and members | REQ-015, REQ-016 | ACT-02, ACT-04, ACT-06 | WF-03, WF-06, WF-08 | Must | Must-have | **Implemented** | `db/migrations/007`, `013` | Organisation with unique slug, own locations, identifiers, hierarchy and members |
| FEAT-012 | Job posting with salary bounds, vacancies and arrangement | REQ-017 | ACT-02, ACT-04 | WF-03 | Must | Must-have | **Implemented** | `db/migrations/008` | Salary fields are all-or-none; status constrained; `published_at` set on publish |
| FEAT-013 | Structured job questionnaire and per-application answers | REQ-018 | ACT-01, ACT-02 | WF-03, WF-04 | Should | Should-have | **Implemented** | `db/migrations/011`; `recruitment.application_question_response` | One questionnaire per job; responses reference application and question; a filled position requires an answer |
| FEAT-014 | Candidate application with source and cover letter | REQ-019, REQ-020 | ACT-01, ACT-02, ACT-07 | WF-04, WF-05 | Must | Must-have | **Implemented** | `db/migrations/009:1-80` | One application per (candidate, job); source constrained to five values |
| FEAT-015 | Application stage history (auditable pipeline transitions) | REQ-021, REQ-022 | ACT-02, ACT-04 | WF-05 | Must | **Differentiator** | **Implemented** | `db/migrations/009:82-210` (`trg_candidate_application_status_history`) | Every stage change writes a history row with actor, previous value, new value and reason |
| FEAT-017 | Recruiter pipeline funnel analytics | REQ-024 | ACT-02, ACT-04 | WF-05 | Should | Should-have | **Implemented** | `db/queries/03_recruiter_pipeline_funnel.sql` — returns a 6-stage funnel on 50,009 applications to one job in p95 7.7 ms (`scripts/run_nfr_checks.py`) | Query returns a non-empty funnel by stage; the earlier empty result was a data-generator defect, fixed |
| FEAT-029 | Recruitment analytics marts (funnel conversion, time-to-hire) | REQ-024 | ACT-02, ACT-08 | WF-05, WF-13 | Could | Optional | **Implemented** | `db/migrations/019`; `db/queries/10_analytics_time_to_hire_kpi.sql` (valid, non-empty) | KPI mart is queryable and refreshable. Refresh is **on-demand only** — no scheduler exists (**OQ-010**) |

### 2.4 Sourcing and commercial

| ID | Feature | Requirements | Actors | Workflows | MoSCoW | Class | Status | Evidence | Acceptance criterion |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| FEAT-018 | Agency consultant sourcing (request → submission → hired) | REQ-025, REQ-026, REQ-027 | ACT-04, ACT-05 | WF-06 | Should | **Differentiator** | **Implemented** | `db/migrations/016:45-203`; `trg_enforce_consultant_openness` | A consultant may submit only to jobs open to consultants and already accepted — enforced by trigger, not by application code |
| FEAT-024 | Blocked-candidate-aware bulk outreach | REQ-028 | ACT-02, ACT-05 | WF-06 | Should | Should-have | **Implemented** | `db/migrations/016:205-300`; `db/queries/06_sourcing_outreach_unblocked.sql` (valid) | Outreach recipients exclude any candidate who has blocked the sender |
| FEAT-030 | Licensed entitlements: seats, device limits, subscriptions | REQ-004, REQ-005 | ACT-01…ACT-08 | WF-09 | Must | Must-have | **Implemented** | `db/migrations/015:9-132` (`trg_enforce_licence_max_users`) | Allocated seats never exceed `max_users`; device entitlement derives from the active licence |
| FEAT-031 | Wallet, ledger and pay-as-you-go profile downloads | REQ-017 | ACT-02, ACT-06, ACT-08 | WF-04, WF-09, WF-14 | Should | **Differentiator** | **Implemented** | `db/migrations/017`, `036` — append-only ledger; `commercial.post_wallet_entry`; `commercial.download_candidate_profile`; `tests/test_wallet_functions.sql`, `tests/test_concurrency.py` test 4 | The ledger is immutable and a download atomically checks visibility, prices, debits and records. Prices are placeholders (DEC-29) |
| FEAT-032 | Invoicing, refunds and payment order tracking | — | ACT-06, ACT-08 | WF-09, WF-14 | Should | Should-have | **Implemented** | `db/migrations/017:113-247`; `gateway_order_id`/`gateway_refund_ref` unique | Orders and refunds carry constrained statuses; gateway references are unique; refunds are recorded as new rows |
| FEAT-033 | Notification delivery tracking across channels | REQ-007 | ACT-01, ACT-03 | WF-11 | Should | Should-have | **Implemented** | `db/migrations/018:246-290` | Delivery rows carry channel, status, provider message id and sent/delivered/read timestamps |
| FEAT-034 | Multilingual UI translation with dynamic fallback | — | ACT-01, ACT-03, ACT-08 | WF-11 | Should | **Differentiator** | **Implemented** | `db/migrations/018:9-95`; `messaging.get_ui_translation`; `db/queries/12_multilingual_ui_translation_lookup.sql` (valid) | A missing key in the requested language falls back to English at query time — no redeployment needed |

### 2.5 Analytics, platform and operations

| ID | Feature | Requirements | Actors | Workflows | MoSCoW | Class | Status | Evidence | Acceptance criterion |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| FEAT-035 | Analytical reporting marts and on-demand refresh | OPS-005 | ACT-08 | WF-13 | Could | Optional | **Implemented** | `db/migrations/019`, `023`, `031` — `analytics.refresh_reporting_marts`; `core.run_maintenance`; `maintenance` service in `docker-compose.yml` | The procedure loads and refreshes all marts and is scheduled by the maintenance service |
| FEAT-036 | Declarative range partitioning for applications | OPS-009 | ACT-08 | WF-13 | Could | **Differentiator** | **Partial** | `db/migrations/019:336-350` (`candidate_application_partitioned`) | The partitioned table exists with annual partitions. **No query targets it** and the authoritative table remains unpartitioned — see **AMB-03** |
| FEAT-037 | Automated data-quality validation harness | OPS-007 | ACT-08 | WF-12 | Should | Must-have | **Implemented** | `scripts/validate_data.py`; `docs/phase-2-model/11-rule-compliance.md` | 15 checks across RG1–RG10 pass on the seeded dataset. **Not invoked by `scripts/run_all_tests.py`**, so it is not re-verified by the main runner |
| FEAT-038 | Executable regression test suite | OPS-008 | ACT-08 | WF-12 | Must | Must-have | **Implemented** | `tests/` — 21 SQL + 2 Python suites | The suite runs green against a seeded database. **Not executed in this phase** (DB access forbidden) — no pass rate is claimed |
| FEAT-039 | Benchmark harness with latency percentiles | OPS-006 | ACT-08 | WF-12 | Should | Should-have | **Implemented** | `scripts/run_benchmarks.py`; `benchmarks/results/benchmark_results.json` | 12 queries measured with p50/p95/p99 and a result-validity marker. **5 of 12 returned empty result sets** — the harness reports them, which is why the gap is visible |
| FEAT-040 | Backup and restore-and-verify runbook | OPS-004 | ACT-08 | WF-12 | Must | Must-have | **Implemented** | `scripts/backup_restore.sh`, `.ps1` | Backup → restore into a recovery database → row-count parity → drop. **Script present; not executed in this phase** |
| FEAT-041 | Containerised, reproducible single-node deployment | OPS-001, OPS-002, OPS-010 | ACT-08 | WF-12 | Must | Must-have | **Implemented** | `docker-compose.yml` | `docker-compose up -d` yields a PostgreSQL 17 instance with all 10 schemas |
| FEAT-042 | Community posts, reactions, support tickets, referrals, FAQs | — | ACT-01, ACT-03, ACT-08 | WF-11 | Could | Optional | **Implemented** | `db/migrations/018:292-440` | Tables exist with constrained statuses. **No requirement and no test covers them** — the messaging schema extends beyond the evidenced product scope |
| FEAT-043 | Integration outbox with idempotency, retry with backoff and dead letter | NFR-027 | ACT-08 | WF-15 | Should | Should-have | **Implemented** | `db/migrations/031`, `tests/test_integration_maintenance.sql` | Added 2026-10-28; the docket's nine boundaries are rows in `messaging.integration_boundary` |
| FEAT-044 | Scheduled maintenance: retention purge, inactive-account erasure, mart refresh | NFR-017, NFR-020 | ACT-08 | WF-16 | Should | Should-have | **Implemented** | `db/migrations/020`, `031`, `docker-compose.yml` | Added 2026-10-28; retention periods are the assistant's (DEC-23) |

---

## 3. Feature counts by classification

### 3.1 By MoSCoW

| Priority | Count | FEAT IDs |
|:--|--:|:--|
| **Must** | 22 | 001, 002, 003, 005, 006, 007, 009, 010, 011, 012, 014, 015, 016, 019, 020, 022, 023, 027, 030, 038, 040, 041 |
| **Should** | 17 | 004, 008, 013, 017, 018, 021, 024, 025, 026, 031, 032, 033, 034, 037, 039, 043, 044 |
| **Could** | 5 | 028, 029, 035, 036, 042 |
| **Won't** | 0 | — |

### 3.2 By feature class

| Class | Count | FEAT IDs |
|:--|--:|:--|
| Must-have | 17 | 001, 002, 003, 006, 007, 009, 010, 011, 012, 014, 016, 019, 030, 037, 038, 040, 041 |
| Should-have | 12 | 004, 008, 013, 017, 024, 025, 026, 032, 033, 039, 043, 044 |
| Differentiator | 11 | 005, 015, 018, 020, 021, 022, 023, 027, 031, 034, 036 |
| Optional | 4 | 028, 029, 035, 042 |
| *(features with no class)* | 0 | — |

### 3.3 By implementation status

| Status | Count | FEAT IDs |
|:--|--:|:--|
| Implemented | 43 | All others |
| Partial | 1 | 036 |
| Documented only | 0 | — |
| Planned | 0 | — |

> **Note.** These three tables are computed from the register rows in §2, and each row's `MoSCoW`, `Class`
> and `Status` columns are the source of truth. If a summary here ever disagrees with a row, the row wins
> and this table is the defect — the same rule the Phase 2C/2D/2E audits applied to the engineering dossiers.

---

## 4. Must-have features and their workflow coverage

Gate G1 Condition 3 requires every must-have feature to appear in at least one workflow. Full detail in
[`docs/phase-1-discover/05-workflows.md`](05-workflows.md) §3.

| FEAT | Feature | Class | MoSCoW | Appears in |
|:--|:--|:--|:--|:--|
| FEAT-001 | Unified talent identity | Must-have | Must | WF-01, WF-02 |
| FEAT-002 | Device-limited sessions | Must-have | Must | WF-01, WF-09 |
| FEAT-003 | Session revocation | Must-have | Must | WF-10 |
| FEAT-005 | Dual-vertical identity | Differentiator | Must | WF-02, WF-07 |
| FEAT-006 | Reference taxonomies | Must-have | Must | WF-01, WF-02, WF-03 |
| FEAT-007 | Candidate profile | Must-have | Must | WF-02 |
| FEAT-009 | Document management | Must-have | Must | WF-02 |
| FEAT-010 | Candidate search | Must-have | Must | WF-04, WF-14 |
| FEAT-011 | Organisation | Must-have | Must | WF-03, WF-06, WF-08 |
| FEAT-012 | Job posting | Must-have | Must | WF-03 |
| FEAT-014 | Application | Must-have | Must | WF-04, WF-05 |
| FEAT-015 | Stage history | Differentiator | Must | WF-05 |
| FEAT-016 | Job-feed matching | Must-have | Must | WF-04 |
| FEAT-019 | RBAC | Must-have | Must | WF-03, WF-08, WF-10 |
| FEAT-020 | RLS tenant isolation | Differentiator | Must | WF-03, WF-05, WF-06, WF-08 |
| FEAT-022 | Audit ledger | Differentiator | Must | WF-08, WF-10, WF-14 |
| FEAT-023 | Block list | Differentiator | Must | WF-04, WF-11, WF-14 |
| FEAT-027 | Double-booking prevention | Differentiator | Must | WF-07 |
| FEAT-030 | Licensed entitlements | Must-have | Must | WF-09 |
| FEAT-037 | Data-quality validation harness | Must-have | Should | WF-12 |
| FEAT-038 | Regression test suite | Must-have | Must | WF-12 |
| FEAT-040 | Backup and restore | Must-have | Must | WF-12 |
| FEAT-041 | Containerised deployment | Must-have | Must | WF-12 |

**Coverage — both readings of "must-have":**

| Reading of "must-have" | Set | Covered by ≥1 workflow |
|:--|:--|:--|
| **MoSCoW priority `Must`** | 22 features (§3.1) | **22 / 22 = 100%** |
| **Feature class `Must-have`** | 17 features (§3.2) | **17 / 17 = 100%** |
| **Union** (the conservative set G1 should be scored against) | **23** features | **23 / 23 = 100%** |

The union is the set scored for Gate G1 Condition 3, because FEAT-037 is class `Must-have` while its MoSCoW
priority is `Should` — the two vocabularies are not nested, and taking only one of them would understate the
obligation. **Every one of the 23 features appears in at least one workflow, and no workflow exists without a
feature.**

**Reconciliation rule.** A feature is listed under a workflow if and only if that workflow's main flow or its
data-objects list touches the feature. The mapping is maintained in **two** places — the `Workflows` column of
§2 and attribute 14 of each workflow in [`docs/phase-1-discover/05-workflows.md`](05-workflows.md) §4 — and the two are checked against
each other in both directions. A feature row and a workflow that disagree is a defect, not a variant: the
disagreement is resolved by re-reading the workflow's main flow, not by preferring one document. The current
state is **44/44 features in exact two-way agreement, 0 discrepancies** (see
[`docs/phase-1-discover/phase-report.md`](phase-report.md) §7.2).

---

## 5. Feature class rationale

### 5.1 Differentiators (11)

Each is a capability whose absence in a competitor would be a structural gap, not a missing feature.

| FEAT | Why it differentiates |
|:--|:--|
| FEAT-005 | Dual-vertical identity is rare. Most marketplaces force a candidate to maintain two accounts; here both profiles hang off one `core.user_account`. |
| FEAT-015 | Stage history is captured by a trigger on every transition, so the pipeline audit trail cannot be bypassed by a bug in application code. |
| FEAT-018 | Consultant sourcing with a **storage-layer** openness rule (`trg_enforce_consultant_openness`) is enforced before commit — an application-layer check would race. |
| FEAT-020 | RLS tenant isolation moves the security boundary into the database. **Implemented (migrations 021 and 030).** No competitor page read describes tenant isolation either way. |
| FEAT-021 | Least-privilege database roles separating app / reporting / admin access. **Implemented (migration 021).** |
| FEAT-022 | An append-only, trigger-protected audit ledger that rejects `UPDATE`/`DELETE` at the storage layer is stronger than application-logged audit trails. |
| FEAT-023 | A relational block list with XOR target semantics and unique indexes — a first-class privacy control, not a boolean flag. |
| FEAT-027 | GiST exclusion constraints make double-booking *impossible* rather than unlikely. |
| FEAT-031 | An append-only wallet ledger with self-referencing correction rows gives a genuine financial audit trail, not a mutable balance. **Fee calculation and the atomic debit are implemented (migration 036); prices are placeholders.** |
| FEAT-034 | Database-level translation resolution with dynamic English fallback needs no redeployment to add a locale. |
| FEAT-036 | Declarative range partitioning on the application table is a prepared scale-out path. **Not on the critical path today.** |

### 5.2 Optional (4)

FEAT-028 (two-sided ratings), FEAT-029 (recruitment KPI marts), FEAT-035 (analytics marts and refresh), FEAT-042
(community, tickets, referrals, FAQs). Each is a bonus that changes no buying decision.

### 5.3 Status of the security features (updated 2026-10-28)

FEAT-019 (RBAC), FEAT-020 (RLS) and FEAT-021 (least-privilege roles) were described but not implemented when this register was first written. They are implemented now (migrations 021 and 030) and tested; D-07 and D-08 in [`02-personas.md`](02-personas.md) §5.2 are closed. What remains true is that no application exists to set `app.current_user_id`, so the policies have been exercised by tests only.

---

## 6. Feature-to-requirement coverage

| Requirement | Feature(s) |
|:--|:--|
| REQ-001, REQ-002, REQ-003 | FEAT-001 |
| REQ-004, REQ-005 | FEAT-002, FEAT-030 |
| REQ-006 | FEAT-003 |
| REQ-007 | FEAT-004, FEAT-033 |
| REQ-008 | FEAT-005 |
| REQ-009 | FEAT-006 |
| REQ-010, REQ-013 | FEAT-007 |
| REQ-011 | FEAT-008 |
| REQ-012 | FEAT-009 |
| REQ-014 | FEAT-010 |
| REQ-015, REQ-016 | FEAT-011 |
| REQ-017 | FEAT-012, FEAT-031 |
| REQ-018 | FEAT-013 |
| REQ-019, REQ-020 | FEAT-014 |
| REQ-021, REQ-022 | FEAT-015 |
| REQ-023 | FEAT-016 |
| REQ-024 | FEAT-017, FEAT-029 |
| REQ-025, REQ-026, REQ-027 | FEAT-018 |
| REQ-028 | FEAT-024 |
| REQ-029 | FEAT-025 |
| REQ-030, REQ-031, REQ-033 | FEAT-026 |
| REQ-032 | FEAT-027 |
| REQ-034 | FEAT-028 |
| SEC-001, SEC-002 | FEAT-019, FEAT-020 |
| SEC-003, SEC-005 | FEAT-022 |
| SEC-010 | FEAT-023 |
| SEC-014 | FEAT-021 |
| OPS-005 | FEAT-035 |
| OPS-007 | FEAT-037 |
| OPS-008 | FEAT-038 |
| OPS-006 | FEAT-039 |
| OPS-004 | FEAT-040 |
| OPS-001, OPS-002, OPS-010 | FEAT-041 |
| OPS-009 | FEAT-036 |

**Coverage: every one of the 34 functional requirements and 14 security requirements maps to at least one
feature. The 18 business rules and all DATA/OPS/NFR requirements are constraints on features rather than
features in their own right** — they are mapped in [`docs/phase-6-specify/34-traceability-matrix.md`](../phase-6-specify/34-traceability-matrix.md).

---

## 7. Competitor research backlog

**Update 2026-10-28.** Competitor research was carried out from the vendors' own pages; see [`03-competitive-benchmark.md`](03-competitive-benchmark.md) §5 for the outcome of each item below (RB-01, 07 answered; RB-02 to 05 not published by any competitor; RB-06 and RB-08 not researched). The original text of this section, which records that the tools were unavailable on 2026-10-21, is superseded.

| # | Research question | Why it matters | Method when access is restored | Priority |
|:--|:--|:--|:--|:--|
| RB-01 | Which of the 9 Talentra differentiators does a named competitor actually implement? | The current benchmark's third-party columns are architectural characterisations, not verified claims | Official product documentation and pricing pages, per competitor, with an access date | **High** |
| RB-02 | Do incumbent job boards offer unified full-time + gig identities? | Tests FEAT-005's differentiator claim | Product documentation per platform | **High** |
| RB-03 | Do any competitors enforce calendar non-overlap at the database layer? | Tests FEAT-027's differentiator claim | Public engineering write-ups or documentation | Medium |
| RB-04 | Do competitors provide append-only financial ledgers for recruitment credits? | Tests FEAT-031's claim | Product documentation and API reference | Medium |
| RB-05 | Do competitors offer database-driven translation with dynamic fallback? | Tests FEAT-034's claim | Product documentation | Low |
| RB-06 | What is the standard compliance posture (PCI-DSS, GDPR, SOC 2) of each competitor? | Needed before any comparative compliance claim | Trust centres and attestation pages | Medium |
| RB-07 | Which competitor features exist in Talentra only as a table with no workflow? | Would extend the "gap" analysis beyond the current feature list | Feature-by-feature product teardown | Medium |
| RB-08 | What is the market's expected price point for profile-access credits? | Contextualises FEAT-031's commercial model | Public pricing pages | Low |

**Access date convention.** Every competitor cell that is later filled must record the source URL, the source
title, the access date, and a confidence rating, in the format established in
[`docs/phase-1-discover/03-competitive-benchmark.md`](03-competitive-benchmark.md) §2.

---

## 8. Validation

| Check | Method | Result |
|:--|:--|:--|
| FEAT ID uniqueness | Manual + scripted scan of the register | 44 IDs, 0 duplicates |
| Every feature links ≥1 requirement | Scan of the `Requirements` column | 44/44 |
| Every feature links ≥1 actor | Scan of the `Actors` column | 44/44 |
| Every feature links ≥1 workflow | Scan of the `Workflows` column | 44/44 |
| Must-have → workflow coverage | Cross-check against [`docs/phase-1-discover/05-workflows.md`](05-workflows.md) §3 | 22/22 = 100% |
| Every requirement → ≥1 feature | Scan of §6 | 48/48 (34 REQ + 14 SEC) |
| Status assigned to every feature | Scan of the `Status` column | 44/44 |
| Classification assigned to every feature | Scan of the `Class` column | 44/44 |
| Implementation-status honesty | Every non-`Implemented` feature cites the specific missing object | 1/1 |

**Verification note.** The 44 unique `FEAT-NNN` identifiers in §2 are the source of truth; the summary
tables in §3.1–§3.3 are derived from them and were recomputed to agree. A reader reconciling a count
against the register and finding a disagreement should treat the register row as correct and the summary as
the defect — the same rule the Phase 2C/2D/2E audits applied to the engineering dossiers.

---

## 9. Related documents

| Document | Contains |
|:--|:--|
| [`docs/phase-1-discover/01-requirements.md`](01-requirements.md) | The requirement register |
| [`docs/phase-1-discover/02-personas.md`](02-personas.md) | Actors and role-permission reconciliation |
| [`docs/phase-1-discover/03-competitive-benchmark.md`](03-competitive-benchmark.md) | Feature-level competitive matrix |
| [`docs/phase-1-discover/05-workflows.md`](05-workflows.md) | The 14 core workflows |
| [`docs/phase-1-discover/04-nfr-register.md`](04-nfr-register.md) | NFR register |
| [`docs/phase-1-discover/05-exceptions.md`](05-exceptions.md) | Exception catalogue |
| [`docs/phase-6-specify/34-traceability-matrix.md`](../phase-6-specify/34-traceability-matrix.md) | Cross-register traceability |
| [`docs/phase-1-discover/phase-report.md`](phase-report.md) | Phase 1 report and G1 decision |
