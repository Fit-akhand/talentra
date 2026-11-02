# Talentra — Scope, Assumptions, Constraints & Open Questions

**Phase:** 1 — Discover
**Step:** 1 (companion to [`docs/phase-1-discover/01-requirements.md`](01-requirements.md))
**Status:** Sources located and reconciled ([`01-docket-reconciliation.md`](01-docket-reconciliation.md)). Items labelled `Proposed` still await a named approver.
**Authored:** 2026-10-21

> **Reading rule.** Every statement in this document is labelled by its epistemic status. Nothing here is an
> official requirement. Where an assumption carries a numeric value, that value is labelled `Proposed` and has
> a named approver — it is never presented as an approved target. See
> [`docs/source/README.md`](../source/README.md) §5.1.

---

## 1. In scope

| # | In-scope item | Evidence / source |
|:--|:--|:--|
| S-01 | The PostgreSQL 17 database design: 10 bounded schemas, 95 tables, constraints, triggers, functions, state machines | `db/migrations/001`–`019` (S-004-A) |
| S-02 | Candidate profile, document, skill, education, experience, language, project data | `db/migrations/005`, `006`, `010` |
| S-03 | Corporate organisation, recruiter–client mapping, job posting, questionnaire | `db/migrations/007`, `008`, `011`, `013` |
| S-04 | Candidate application and recruitment pipeline with status history | `db/migrations/009` |
| S-05 | Agency consultant sourcing: requests, submissions, outreach batches | `db/migrations/016` |
| S-06 | Gig marketplace: worker profile, request, application, assignment, rating | `db/migrations/014` |
| S-07 | Commercial: licences, device limits, subscriptions, invoices, wallet ledger, payment orders | `db/migrations/015`, `017` |
| S-08 | Messaging: notifications, delivery tracking, UI translations | `db/migrations/018` |
| S-09 | Audit ledger and its anti-tamper trigger | `db/migrations/012` |
| S-10 | Analytics marts and the refresh procedure | `db/migrations/019` |
| S-11 | Identity, session, consent, role/permission model structure | `db/migrations/002`, `012` |
| S-12 | The 12 defined workload queries and the benchmark harness | `db/queries/`, `scripts/run_benchmarks.py` |
| S-13 | The executable test suites (21 SQL + 2 Python) and runners | `tests/`, `scripts/run_all_tests.py`, `scripts/validate_data.py` |
| S-14 | Backup/restore runbook and containerised delivery | `scripts/backup_restore.sh`, `docker-compose.yml` |
| S-15 | The Phase 1 documentation set itself (this document set) | This phase |

---

## 2. Out of scope

| # | Out-of-scope item | Reason |
|:--|:--|:--|
| X-01 | Application code — UI, API layer, service layer | No application source exists in the repository; this is a database-design hackathon |
| X-02 | Authentication/authorisation service implementation | The database provides the structures and one session function; the identity provider is external |
| X-03 | Payment gateway integration | Represented by `gateway_order_id` / `gateway_refund_ref` columns only; no gateway client exists |
| X-04 | Email/SMS/push provider integration | Represented by `messaging.notification_delivery.external_provider_message_id` only |
| X-05 | Object storage for resumes and profile media | `profile.candidate_document` stores metadata + checksum, not file bytes |
| X-06 | Background-check provider integration | Column references exist in documentation but **no backing columns exist** (`docs/phase-4-platform/22-integration-boundaries.md:88` — Phase 2E D2) |
| X-07 | Deployment beyond a single containerised instance | `docker-compose.yml` defines one service (OPS-010) |
| X-08 | Migration of existing production data | Greenfield design; no source system in evidence |
| X-09 | Report and document generation (CV export, offer letters) | Not present in any schema |

### 2.1 Explicit hackathon exclusions (stated as exclusions, not as omissions)

These are recorded so they are not re-raised as gaps in a later phase:

| # | Exclusion |
|:--|:--|
| H-01 | Real personal data. All seeding uses generated data (`scripts/generate_data.py`); no production PII enters the repository. |
| H-02 | Production credentials. `.env` was never read; only `.env.example` is referenced. |
| H-03 | Third-party SaaS accounts or API keys for any external service. |
| H-04 | Benchmark data volume beyond the harness presets — a run at "large" scale was not executed in this phase (see §7, **OQ-005**). |

---

## 3. Constraints

Constraints are facts that bound the design. Unlike assumptions, they are not choices — they cannot be
negotiated within this phase.

| # | Constraint | Source |
|:--|:--|:--|
| C-01 | The target platform is PostgreSQL 17 | `docker-compose.yml`; `README.md:95-99` |
| C-02 | Database-First Modular Monolith: the schema is the deliverable | `docs/phase-2-model/09-architecture.md:31-45` |
| C-03 | 10 bounded schemas with strict ownership; cross-schema access via FK only | `db/migrations/001`; `docs/phase-2-model/09-architecture.md:47-60` |
| C-04 | Master reference data is read-only after seeding and carries no outbound FKs | `docs/phase-2-model/09-architecture.md:51`; RG5 (`docs/phase-2-model/11-rule-compliance.md:17`) |
| C-05 | `TIMESTAMPTZ` in UTC for instants; `DATE` for calendar dates | `docs/phase-2-model/09-architecture.md:148` |
| C-06 | No sentinel values for missing data; NULL only | `docs/phase-2-model/09-architecture.md:149`; RG5 |
| C-07 | Every operational table uses a surrogate `BIGINT GENERATED ALWAYS AS IDENTITY` key named `id` | RG2 |
| C-08 | Financial and audit ledgers are append-only, enforced by triggers | RG7 |
| C-09 | Gig worker calendars may not overlap, enforced by a GiST exclusion constraint | RG10 |
| C-10 | Migrations are ordered and must be applied 001 → 019 | `README.md:101-107` |
| C-11 | Single PostgreSQL service in the delivered environment | `docker-compose.yml` |
| C-12 | This phase may not modify migrations, schema, application code, tests, benchmark scripts, dependency files, or environment configuration | Phase 1 task constraint |
| C-13 | This phase may not run destructive SQL, apply migrations, load data, or reset a database | Phase 1 task constraint |
| C-14 | This phase may not install packages or dependencies | Phase 1 task constraint |
| C-15 | This phase may not commit, stash, switch branches, or rewrite Git history | Phase 1 task constraint |

---

## 4. Dependencies

| # | Dependency | Type | Status |
|:--|:--|:--|:--|
| D-01 | The hackathon docket (S-001) | Documentation | **PRESENT** — `docs/source/originals/Talentra-Database-Design-Hackathon-Docket.pdf`; requirement traceability pending |
| D-02 | The Talencia lifecycle playbook (S-002) | Documentation | **PRESENT** — `docs/source/originals/Talencia Global - Data-Driven Development Lifecycle - Detailed Playbook.pdf`; G1 criteria verified on pages 6 and 18 |
| D-03 | The twelve `db/queries/*.sql` workload queries | Implementation | Present |
| D-04 | `scripts/generate_data.py` dataset generator | Implementation | Present — required by every benchmark and test run |
| D-05 | `scripts/run_benchmarks.py` harness | Implementation | Present — the only latency measurement method in the repository |
| D-06 | `scripts/validate_data.py` validator | Implementation | Present — the only data-quality measurement method |
| D-07 | `scripts/backup_restore.sh` | Implementation | Present — the only RTO measurement method |
| D-08 | An external identity provider | Runtime | Out of scope (X-02) |
| D-09 | A payment gateway | Runtime | Out of scope (X-03) |
| D-10 | A messaging provider | Runtime | Out of scope (X-04) |
| D-11 | An object store for documents | Runtime | Out of scope (X-05) |
| D-12 | `pg_cron` (or equivalent) for scheduled mart refresh | Extension | **NOT INSTALLED** — `docs/phase-2-model/09-architecture.md:112` |

---

## 5. Assumptions

Each assumption states its owner, rationale, confidence, impact if wrong, and the condition under which it
must be revisited.

### A-001 — G1 conditions match the authoritative lifecycle playbook

| Field | Value |
|:--|:--|
| **Owner** | Talencia Global — lifecycle playbook author |
| **Evidence** | S-002, *Talencia Global — Data-Driven Development Lifecycle — Detailed Playbook*, Version 1.0, October 2026, pages 6 and 18. |
| **Finding** | The playbook explicitly defines G1 using the same three conditions recorded in the Phase 1 task instructions. |
| **Disposition** | **Confirmed; no longer an open assumption.** Retain this record as a traceability note, but exclude it from the active assumption count. |
| **Remaining work** | Evaluate the actual Phase 1 deliverables against all three G1 conditions. Source confirmation alone does not establish gate passage. |

### A-002 — The implemented schema represents the intended Talentra product scope

| Field | Value |
|:--|:--|
| **Owner** | Talentra product owner — approval not yet confirmed |
| **Rationale** | The implemented schema is evidence of the current design, but it does not independently establish the complete authorised product scope. The authoritative hackathon docket (S-001) is now available and must be used to assess scope coverage. |
| **Confidence** | **Under review** — the docket has been located, but a complete comparison between its requirements and the implemented schema has not yet been recorded. |
| **Impact if wrong** | Requirements or domains in the docket may be missing from the schema, or implementation features may exceed the authorised scope. |
| **Review condition** | Compare the docket's scope, required domains, business rules, integrations, scale targets, and deliverables against the existing requirements register and schema. Record gaps and decisions before retiring this assumption. |
| **Status** | Active — scope reconciliation pending |

### A-003 — The 12 benchmark queries represent the intended production workload

| Field | Value |
|:--|:--|
| **Owner** | Platform / DBA — **unavailable for confirmation** |
| **Rationale** | `db/queries/01`–`12` are the only defined workload in the repository, and `scripts/run_benchmarks.py` executes exactly those 12. They span search, feed, funnel, recruiter pipeline, sourcing outreach, gig matching, analytics, and admin views. |
| **Confidence** | **Medium-High** for the queries that ran; **Low** for the five that returned empty result sets (Q03, Q04, Q05, Q08, Q09) — an empty result may mean the query is wrong rather than that it is irrelevant. |
| **Impact if wrong** | Latency NFRs (NFR-001…NFR-004) are calibrated against the wrong workload and every measured number must be re-taken. |
| **Review condition** | **Revisit when the empty-result queries are diagnosed** (see [`docs/phase-1-discover/04-nfr-register.md`](04-nfr-register.md) §5 and **OQ-005**). |
| **Status** | Active |

### A-004 — The "medium" benchmark preset is representative of the intended production scale

| Field | Value |
|:--|:--|
| **Owner** | Platform / DBA — **unavailable for confirmation** |
| **Rationale** | `scripts/run_benchmarks.py` defines small/medium/large presets and the recorded artefacts correspond to the medium preset. However, the artefacts record **no dataset row counts**, so the actual scale behind the numbers cannot be confirmed from the artefacts alone (Phase 2E **U-05**). |
| **Confidence** | **Low-Medium** — the preset exists in code; the corpus behind the recorded run is unproven. |
| **Impact if wrong** | All latency numbers, and the concurrency extrapolation in `docs/phase-4-platform/28-performance-report.md`, are mis-scaled. |
| **Review condition** | **Revisit when a benchmark run records its row counts.** Recommended change to the harness (not made in this phase, per C-12): emit the dataset size alongside the timing JSON. |
| **Status** | Active |

### A-005 — The current engineering dossiers describe the system accurately enough to be used as requirement sources

| Field | Value |
|:--|:--|
| **Owner** | Documentation owner — **unavailable for confirmation** |
| **Rationale** | `docs/phase-2-model/09-architecture.md`, `docs/phase-2-model/12-threat-model.md`, `docs/phase-4-platform/22-integration-boundaries.md`, `docs/phase-2-model/10-data-dictionary.md` and `docs/phase-2-model/11-rule-compliance.md` are used as `Document-Derived` sources for several requirements (BR-005, BR-006, BR-009, DATA-002, DATA-004, DATA-007, and the whole SEC/NFR/OPS register). |
| **Confidence** | **Medium** — Phase 2C/2D/2E audited these documents and corrected 40+ findings, but 10 items (U-01…U-10) remain open, so the dossiers are *materially improved*, not fully trustworthy. Every requirement derived from a dossier is cross-checked against the migration DDL, and the dossier is cited only where the DDL corroborates it. |
| **Impact if wrong** | A small number of `Document-Derived` requirements would need their DDL cross-check reversed. The impact is bounded because no requirement was accepted on a dossier's word alone. |
| **Review condition** | **Revisit when Phase 2E's U-01…U-10 are closed.** |
| **Status** | Active |

### A-006 — The 9 seeded roles are the complete set of system roles

| Field | Value |
|:--|:--|
| **Owner** | Security / platform owner — **unavailable for confirmation** |
| **Rationale** | `db/migrations/012:9-20` seeds 9 roles: `super_admin`, `admin`, `account_admin`, `guest`, `candidate`, `employer`, `recruiter`, `consultant`, `placement_officer`. The personas in [`docs/phase-1-discover/02-personas.md`](02-personas.md) are derived from these. |
| **Confidence** | **Medium** — the roles are seeded but carry no permissions (`core.role_permission` is empty), so the role set's *meaning* is documented rather than enforced. |
| **Impact if wrong** | The persona register would need additional actor cards, and the role-permission reconciliation would need a new target row. |
| **Review condition** | **Revisit when `core.permission` and `core.role_permission` are populated** (this phase documents the desired state but must not seed them — task constraint). |
| **Status** | Active |

### A-007 — Accessibility conformance is out of scope for a database-design deliverable

| Field | Value |
|:--|:--|
| **Owner** | Product owner — **unavailable for confirmation** |
| **Rationale** | The deliverable is a database schema with no UI. Accessibility (WCAG) is a property of a user interface. A database can, at most, influence it through data constraints (e.g. not forcing gender or disability fields, supporting screen-reader-safe free text). No such constraint set exists. |
| **Confidence** | **Medium** — reasonable, but the docket might mandate a data-level accessibility contract. |
| **Impact if wrong** | NFR-019 becomes a live requirement needing a numeric conformance target and a test method, and a small set of schema-level data constraints. Bounded work. |
| **Review condition** | Review the available docket (S-001) for explicit data-level accessibility requirements; compare its scope with NFR-019 and record the finding. If the docket is silent or ambiguous, keep OQ-004 open pending product-owner confirmation. |
| **Status** | Active, pending **OQ-004** |

### A-008 — The two audit-write sites represent the intended audit scope

| Field | Value |
|:--|:--|
| **Owner** | Security / compliance owner — **unavailable for confirmation** |
| **Rationale** | `grep "INSERT INTO audit.audit_event" db/ scripts/` returns exactly **2** sites: `db/migrations/015:221` (`device.limit_exceeded`) and `db/migrations/015:317` (`session.revoked`). The threat model at `docs/phase-2-model/12-threat-model.md:85-94` describes a much wider audit scope. |
| **Confidence** | **Low** — the schema was built with a complete audit *table* but only two write paths. |
| **Impact if wrong** | The audit-event matrix identifies 12 sensitive actions with no audit coverage; if the intended scope really is only 2 events, the matrix shrinks to a confirmation. Either way the matrix must exist. |
| **Review condition** | Review the available docket (S-001) for required audit events and compare them with `docs/phase-1-discover/05-audit-event-matrix.md`. Keep OQ-006 open until the required audit scope is reconciled and a security/compliance owner confirms any remaining ambiguity. |
| **Status** | Active |

---

## 6. Ambiguities

Ambiguities are places where the available evidence admits more than one reading. They are recorded rather than
resolved, because resolving them requires an authority this phase does not have.

| # | Ambiguity | Readings | How it affects the deliverables |
|:--|:--|:--|:--|
| AMB-01 | Is the deliverable the **recruitment marketplace** (job posting, applications, sourcing) or the **gig marketplace** (projects, assignments) or both as one platform? | (a) Recruitment-led; (b) Gig-led; (c) Hybrid marketplace with two distinct verticals. | Determines whether FEAT-021…FEAT-025 are Must or Should. Currently both verticals carry Must-level *requirements* but the gig vertical's *features* are classified Should/Could — see [`docs/phase-1-discover/03-feature-inventory.md`](03-feature-inventory.md) §5. |
| AMB-02 | Is `commercial.wallet_ledger` a customer wallet, a platform commission ledger, or both? | (a) Client prepaid wallet for job-posting and profile-download fees; (b) Platform revenue ledger; (c) Both, distinguished by `reference_type`. | Affects NFR-012 (reconciliation), the audit-event matrix for financial actions, and the exception catalogue's payment-failure entries. Evidence (`db/migrations/017:332-341`) supports (c). |
| AMB-03 | Is `recruitment.candidate_application_partitioned` the future authoritative application table, or a scale-out experiment alongside the unpartitioned `recruitment.candidate_application`? | (a) Authoritative table to be migrated to; (b) Experiment only. | Affects OPS-009 and NFR-009. Evidence (`db/migrations/019:336-350`; `docs/phase-2-model/09-architecture.md:91`) supports (b) — no query targets it and no benchmark exercises it. |
| AMB-04 | Does `sourcing.consultant_sourcing_request` mean a consultant *asks to source for* a job (as implemented), or an employer *commissions* a consultant? | (a) Consultant-initiated request, employer accepts/declines (as implemented); (b) Employer-commissioned assignment. | Affects REQ-025/BR-018 and the WF-06 workflow narrative. The implementation and `docs/phase-4-platform/22-integration-boundaries.md` both support (a). |
| AMB-05 | Is `messaging.notification_delivery` the delivery record for one channel, or a per-channel attempt log within a multi-channel notification? | (a) One row per notification, with `external_provider_message_id`; (b) One row per channel attempt. | Affects REQ-028's downstream notification model and NFR-008's delivery window. The `delivery_status` CHECK (`queued/sent/delivered/failed/read`) supports (a). |
| AMB-06 | What does "three analytics marts" refer to: three logical reporting areas, three datasets, or another defined reporting structure? Do these represent the intended reporting product or an interim subset? | (a) The delivered reporting surface; (b) A subset. | Affects NFR-020, NFR-024 and OPS-005's staleness commitment. The refresh procedure currently refreshes the two materialized reporting views defined in this migration; the intended scope of the three marts remains unverified. |
---

## 7. Open questions

Each open question has a unique ID, an impact statement, a dependency, and a resolution path. Questions remain open until their stated evidence and resolution criteria are satisfied. The availability of S-001 and S-002 removes the source-access blocker for questions that depend on those documents, but does not itself resolve those questions. Items requiring business approval, external competitor evidence, or unresolved technical investigation remain open until their specific criteria are met.

#### OQ-001 — What KPI requirements does the analytics module need to satisfy?

| Field | Value |
|:--|:--|
| **Question** | `db/migrations/019_create_analytics_marts.sql:258` contains the comment `-- 8. Materialized Reporting Views for Core Hackathon KPIs (Section 8)`. The available docket (S-001) describes an analytics module that must provide dimensions, facts, and aggregates for the KPIs in Section 8, but the extracted 12-page docket does not provide that KPI list. What are the authoritative KPI requirements, and do the two implemented materialized views satisfy them? |
| **Impact** | **High.** Without the authoritative KPI list, analytics coverage cannot be fully reconciled. The implemented materialized views may not cover all required KPIs, and related requirements may need extension. |
| **Dependency** | D-01 (the docket) and an authoritative KPI list or clarification from the product owner. |
| **Resolution path** | Record the missing Section 8 KPI list as a source discrepancy. Request the complete or corrected docket, or written clarification from the product owner. Once authoritative KPI requirements are available, compare each requirement with the implemented marts in `db/migrations/019_create_analytics_marts.sql` and document matches and gaps. Until then, mark analytics coverage as **not verified against authoritative KPI requirements**. |
| **Owner** | Product owner |
| **Status** | Open — blocked on authoritative KPI requirements; the docket file is available, but its referenced KPI list has not been located in the supplied document. |

### OQ-002 — What are the approved NFR targets?

| Field | Value |
|:--|:--|
| **Question** | Every numeric target in [`docs/phase-1-discover/04-nfr-register.md`](04-nfr-register.md) is engineer-derived and labelled `Proposed`. Which values does the business actually require? |
| **Impact** | **High.** Directly determines whether Gate G1 Condition 2 can be reported as PASS. Under the provenance rule in `docs/source/README.md` §5.1, only an `Official` or `Approved Decision` target satisfies the condition; `Proposed` targets count as *measured but unapproved*. |
| **Dependency** | D-01 and D-03. |
| **Resolution path** | Circulate [`docs/phase-1-discover/04-nfr-register.md`](04-nfr-register.md) for business sign-off; record the approver and date per NFR, then promote the label from `Proposed` to `Approved Decision`. |
| **Owner** | Product owner + platform lead |
| **Status** | Open — **this is the single gating item for G1 Condition 2** |

### OQ-003 — What is the authoritative scope boundary between the recruitment and gig verticals?

| Field | Value |
|:--|:--|
| **Question** | See **AMB-01**. Which vertical is the core product promise, and which is an adjacent capability? |
| **Impact** | **Medium-High.** Determines feature classification (must-have vs should-have vs differentiator), which determines G1 Condition 3 coverage and the scope of Phase 2 implementation. |
| **Dependency** | D-01. |
| **Resolution path** | Resolve from the docket; absent the docket, obtain a written product-owner statement of the primary vertical and record it as an `Approved Decision`. |
| **Owner** | Product owner |
| **Status** | Open |

### OQ-004 — Is accessibility a Phase 1 requirement at all?

| Field | Value |
|:--|:--|
| **Question** | Does the docket require an accessibility conformance level for a database-design deliverable? |
| **Impact** | **Medium.** NFR-019 currently carries **no numeric target**, so if it is in scope it is a G1 Condition 2 failure; if it is out of scope it should be recorded as an explicit exclusion rather than a requirement without a target. |
| **Dependency** | D-01. |
| **Resolution path** | Confirm against the docket. If in scope, define a data-level conformance target and a measurement method; if out of scope, record the exclusion under §2.1 and remove NFR-019 from the register. |
| **Owner** | Product owner |
| **Status** | Open — assumption **A-007** covers it in the interim |

### OQ-005 — Why do five benchmark queries return empty result sets?

| Field | Value |
|:--|:--|
| **Question** | Q03 (`03_recruiter_pipeline_funnel.sql`), Q04, Q05, Q08 and Q09 returned zero rows in the recorded run. Is the cause (a) a generator gap — the seeded dataset does not populate the tables those queries read, (b) a query defect, or (c) a filter predicate that excludes all generated rows? |
| **Impact** | **High for NFRs, Medium for the product.** An empty result set produces a latency number with no work performed, so those measurements cannot serve as acceptance baselines for NFR-001…NFR-004. Depending on the cause, either the queries or the generator needs fixing before any latency claim is credible. |
| **Dependency** | D-03, D-04, D-05. |
| **Resolution path** | **Not diagnosable in this phase** — C-13 forbids loading data and running the generator, and the task forbids running expensive benchmarks or altering benchmark scripts. Requires one authorised diagnostic run: execute the five queries against the seeded dataset and compare row counts against the source tables. |
| **Owner** | Platform / DBA |
| **Status** | Open — **explicitly not resolved here**; flagged in [`docs/phase-1-discover/04-nfr-register.md`](04-nfr-register.md) §5 |

### OQ-006 — What is the intended audit-event coverage?

| Field | Value |
|:--|:--|
| **Question** | The audit table and its anti-tamper trigger are complete, but only two write paths exist. Which sensitive actions are in scope for audit logging? |
| **Impact** | **High.** Drives [`docs/phase-1-discover/05-audit-event-matrix.md`](05-audit-event-matrix.md) and SEC-003's acceptance criterion. At present 12 sensitive actions have no audit coverage — including all financial transactions, refunds, subscription changes, profile unlocks/downloads, and all permission changes. For a platform handling payments and PII, that is a material gap regardless of what the docket says. |
| **Dependency** | D-01, plus a security-requirements source. |
| **Resolution path** | Obtain a compliance requirement source (SOC 2 control set or an internal security policy). If none exists, treat the matrix's uncovered set as a Phase 2 implementation backlog with the severity column already ranked. |
| **Owner** | Security / compliance owner |
| **Status** | Open |

### OQ-007 — What are the RPO and RTO objectives?

| Field | Value |
|:--|:--|
| **Question** | `docs/phase-2-model/12-threat-model.md` §7 states RPO/RTO values, but no business source confirms them, and the delivered single-instance containerisation (`docker-compose.yml`) provides neither point-in-time recovery nor failover. |
| **Impact** | **High.** NFR-010 and NFR-011 currently carry `Proposed` targets that may be unachievable with the delivered topology. A target the platform cannot meet is worse than an absent target, because it looks like a commitment. |
| **Dependency** | D-01; a business continuity decision. |
| **Resolution path** | Obtain the confirmed objectives; then either (a) implement WAL archiving + point-in-time recovery + a standby, or (b) restate the targets as achievable for the delivered topology and record the gap explicitly as a known limitation with a review date. |
| **Owner** | Platform lead + business continuity owner |
| **Status** | Open |

### OQ-008 — Should `core.permission` and `core.role_permission` be seeded, and with what contents?

| Field | Value |
|:--|:--|
| **Question** | The tables exist (`db/migrations/012:23-79`) and 9 roles are seeded, but the permission catalogue is empty. Which permissions exist, and which role holds which? |
| **Impact** | **High.** SEC-001 is currently `Documented` only — the RBAC model has no content. It also blocks SEC-002's organisation-isolation guarantee, which today is application-layer only. |
| **Dependency** | A security-requirements source; D-01. |
| **Resolution path** | **This phase documents the desired state and the discrepancy; it must not seed the tables** (explicit task constraint). The desired contents are specified in [`docs/phase-1-discover/02-personas.md`](02-personas.md) §5. Seeding is Phase 2 work and needs a migration that the current phase may not create. |
| **Owner** | Security owner |
| **Status** | Open — desired state documented, implementation deferred to Phase 2 |

### OQ-009 — Are the twelve analytics marts' KPIs the reporting product?

| Field | Value |
|:--|:--|
| **Question** | See **AMB-06**. Related to OQ-001 but narrower — whether the two implemented materialized reporting views cover the full set of "core hackathon KPIs" referenced by the docket. |
| **Impact** | **Medium.** Affects NFR-020 (refresh staleness) and NFR-024 (documentation coverage of analytics). |
| **Dependency** | D-01. |
| **Resolution path** | Same as OQ-001. |
| **Owner** | Product owner |
| **Status** | Open |

### OQ-010 — Should the mart refresh be scheduled, and who owns it?

| Field | Value |
|:--|:--|
| **Question** | `analytics.refresh_reporting_marts` exists but no scheduler invokes it; `pg_cron` is not installed (`docs/phase-2-model/09-architecture.md:112`). Is the refresh on-demand only, or must it run on an interval — and if scheduled, which team owns the job and the failure alerting? |
| **Impact** | **Medium-High.** A must-run operation with no scheduler and no owner is an operational single point of failure. OPS-005 currently asserts the procedure works, which is true but not sufficient. |
| **Dependency** | D-01 for the interval; an infrastructure decision for the mechanism. |
| **Resolution path** | Decide the interval with the product owner; implement via `pg_cron`, an OS cron, or a container scheduler — noting the extension is not currently installed and adding it is an environment change this phase may not make. |
| **Owner** | Platform lead |
| **Status** | Open |

### OQ-011 — What is the required data retention and deletion schedule?

| Field | Value |
|:--|:--|
| **Question** | NFR-017 requires a retention period, but no schedule exists in the repository. No table carries a retention or purge marker, and `core.consent_record` records consent state without a withdrawal-driven deletion path. |
| **Impact** | **Medium-High.** A GDPR-aligned retention obligation is asserted in `docs/phase-2-model/12-threat-model.md` but has no mechanism, no schedule, and no test method. |
| **Dependency** | D-01; a legal/privacy decision. |
| **Resolution path** | Obtain the retention schedule; add a `retention_until`-style marker per in-scope table plus a documented purge procedure and a deletion-audit event. Phase 2 implementation. |
| **Owner** | Privacy / legal owner |
| **Status** | Open |

---

## 8. Decisions

Decisions taken in this phase. Each records what was decided, the rationale, the alternatives considered, and
what would reverse it.

| # | Decision | Rationale | Alternatives rejected | Reversal condition |
|:--|:--|:--|:--|:--|
| DEC-01 | Requirement provenance is `Implementation-Derived` / `Document-Derived` / `Dialect-Only` / `Proposed`, and **no requirement is labelled official without source traceability** | S-001 and S-002 are now available locally. Source availability alone does not establish that every requirement is official; each official classification must be supported by the relevant authoritative source and a traceable reference. | Treating the schema as the docket by implication; leaving requirements unlabelled; classifying a requirement as official without supporting source evidence | Each requirement has been reconciled against S-001 and, where applicable, S-002, with source references recorded; any required approval is documented |
| DEC-02 | Every NFR target carries an explicit provenance label and a named approver, and `Proposed` targets are reported as *measured but unapproved* | The task forbids passing an inference off as an official requirement, and forbids manipulating counts to obtain PASS | Reporting proposed targets as if approved; omitting numeric targets to hide the gap | Business sign-off recorded per NFR |
| DEC-03 | The G1 evaluation applies exactly the three restated conditions and no additional sub-criteria | S-002 is available locally, and its G1 conditions were verified on pages 6 and 18. Using those source-defined conditions avoids inventing a stricter or looser gate. | Inventing additional criteria; refusing to evaluate G1 against the documented conditions | The Phase 1 deliverables have been evaluated against all three G1 conditions and the evidence and outcome are recorded |
| DEC-04 | Competitor capability cells are recorded as `Unknown` and a research backlog is created, rather than filling them with plausible claims | External sources are inaccessible; unsourced competitor claims would be fabrication | Copying the pre-existing unverified third-party characterisations forward as fact; dropping the benchmark entirely | External access is restored, or an official competitor dossier is supplied |
| DEC-05 | The role-permission desired state is documented but **not seeded** | Explicit task constraint | Seeding the tables to make the reconciliation "pass" | Phase 2, with an approved migration |
| DEC-06 | Benchmarks were **not** re-run | Explicit task constraint; also a destructive-ish operation against a database this phase may not touch | Re-running to obtain fresh numbers | An authorised benchmark window |
| DEC-07 | The 5 empty-result benchmark queries are flagged as unusable acceptance baselines rather than being quietly excluded | Excluding them would reduce coverage in a way that looks like scope reduction | Reporting the 7 non-empty queries' numbers as if they covered all 12 | OQ-005 is diagnosed |
| DEC-08 | `docs/phase-1-discover/03-competitive-benchmark.md` is rebuilt as a **feature-level** matrix rather than a document-level one | The Phase 1 instruction requires feature-level comparison; the previous 8-row matrix compared documents, not capabilities | Leaving the document-level matrix as-is | — (the rebuild satisfies the instruction) |
| DEC-09 | The 10 unresolved Phase 2E items (U-01…U-10) are carried forward into the gap register rather than silently dropped | They are real open issues that Phase 2 must see; dropping them would lose the audit trail | Re-deriving them from scratch | U-01…U-10 are closed |
| DEC-10 | Requirement priority is assigned by product-coherence rule, not by "is it implemented" | A rule that made every implemented capability Must would make MoSCoW meaningless and would mask the fact that some implemented areas are not core | Implementation-driven priority; uniform priority | The docket's own priority scheme is supplied |

---

## 9. Validation performed in this phase

| Check | Method | Result |
|:--|:--|:--|
| Docket / playbook presence | Local source index and filesystem verification; historical search recorded in §2.1 of `docs/source/README.md` | Both sources are present locally. Historical search results are retained as historical evidence, not as current availability status. |
| Requirement ID uniqueness | Script over `docs/phase-1-discover/01-requirements.md` | 120 IDs, 0 duplicates, 0 numbering gaps |
| Requirement → actor coverage | Script over the `Actor(s)` columns | 120/120 = 100% |
| Requirement → workflow coverage | Script over the `WF` column and the workflows' `Requirements` attribute | 61/61 functional + business rules mapped; 10/14 security requirements referenced |
| NFR → target + method + provenance | Script over `docs/phase-1-discover/04-nfr-register.md` | 26/27 have a numeric target, a method, an acceptance criterion and an approver; 0/27 are `Official` |
| Must-have feature → workflow coverage | Script over `docs/phase-1-discover/03-feature-inventory.md` + `docs/phase-1-discover/05-workflows.md` | 23/23 = 100% |
| Feature ↔ workflow bidirectional consistency | Script over both registers | 42/42 features agree on their workflow set, in both directions |
| Exception catalogue ↔ workflow allocation | Script over `docs/phase-1-discover/05-exceptions.md` §3.4 and `docs/phase-1-discover/05-workflows.md` attribute 12 | 14/14 workflows allocate the same EXC IDs; 40/40 exceptions allocated; 0 orphans |
| Audit coverage tally | Script over `docs/phase-1-discover/05-audit-event-matrix.md` §3 | 2 Covered, 4 Partial, 8 Not covered — 2/14 fully covered |
| Cross-document link integrity | Script over all Phase 1 documents | All internal links resolve |
| Happy-path-only check | Manual review of every workflow and exception | Each workflow has ≥1 exception path; each exception names a trigger, an action, and a caller-visible outcome |
| Contradiction check | Manual cross-read of the Phase 1 set against `db/migrations/` | 10 conflicts recorded in `docs/phase-1-discover/01-requirements.md` §7.2; none found *within* the Phase 1 set |
| Database state | — | **Not touched.** No migration applied, no query executed, no data loaded |

---

## 10. Related documents

| Document | Contains |
|:--|:--|
| [`docs/phase-1-discover/01-requirements.md`](01-requirements.md) | The requirement register |
| [`docs/source/README.md`](../source/README.md) | Source index and provenance rules |
| [`docs/phase-1-discover/02-personas.md`](02-personas.md) | Actors, personas, role-permission reconciliation |
| [`docs/phase-1-discover/03-feature-inventory.md`](03-feature-inventory.md) | Feature register |
| [`docs/phase-1-discover/04-nfr-register.md`](04-nfr-register.md) | NFR register with targets and provenance |
| [`docs/phase-1-discover/05-workflows.md`](05-workflows.md) | Core business workflows |
| [`docs/phase-1-discover/05-exceptions.md`](05-exceptions.md) | Exception catalogue |
| [`docs/phase-6-specify/34-traceability-matrix.md`](../phase-6-specify/34-traceability-matrix.md) | Cross-register traceability |
| [`docs/phase-1-discover/05-audit-event-matrix.md`](05-audit-event-matrix.md) | Audit coverage |
| [`docs/phase-1-discover/phase-report.md`](phase-report.md) | Phase 1 report and G1 decision |
