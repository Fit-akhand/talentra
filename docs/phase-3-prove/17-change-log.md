# Talentra: Model Change Log (Step 17, Design-Based Refinement)

**Phase:** 3 Prove | **Step:** 17 Design-Based Refinement
**Rule:** every change to the baseline model (migrations 001-019) is a new migration, never an edit, so a database that has already applied 001-019 can reach the current model by applying the rest. The one exception, edits made to 020 and 021 while they were still unapplied anywhere, is noted below.

Each entry says what was wrong, how it was found, and which test now guards it. "Found by" is the check that exposed the gap, because a gap that no check exposes is found again later.

## Closed

| Migration | Change | Why (gap) | Found by | Guard |
|:--|:--|:--|:--|:--|
| 020 | Audit columns on every business table, one trigger to fill them, soft delete on 9 entities with `active_<table>` views, `audit.entity_lifecycle_policy`, `core.erase_user_account`, `core.find_inactive_accounts` | Docket Rule Group 4: only 2 of 92 tables had `created_by`/`updated_by`, none had `deleted_at`, no retention or erasure | Generated entity catalogue ([06](../phase-2-model/06-entity-catalogue.md)) | `test_lifecycle.sql` |
| 021 | Five database roles, grants, row-level security on 12 tables, masking view, hash-format and token-format `CHECK`s, 28 permissions mapped to 9 roles, `TRUNCATE` blocked on ledgers | Docket section 3 requires privileges enforced in the database; no roles, no RLS, empty permission tables, plaintext accepted as a password hash | Phase 3 verification report R-03, R-06; requirement register SEC-001, 006, 007, 014 | `test_access_control.sql` |
| 022 | Activity log, search history, courses and enrolments, resume templates; append-only guard on view/status/error history; "candidates register themselves" rule; 12 state machines as data | Docket Tier 2 domains missing (GAP-09, 12, 13); Rule Group 10 history not append-only; GAP-06 rule not enforced; no legal transitions anywhere | Docket reconciliation ([01](../phase-1-discover/01-docket-reconciliation.md)); generated state machine catalogue | `test_domains_and_transitions.sql` |
| 023 | `analytics.load_reporting_marts()`; `refresh_reporting_marts()` now loads before refreshing; idempotency keys on the facts; calendar extension | The star schema was loaded by nothing except the data generator; the calendar stopped at 2027-12-31 | KPI catalogue work ([29](../phase-5-insight/29-kpi-catalogue.md)) | `test_analytics.sql`, `test_golden_kpis.py` |
| 024 | `audit.column_classification`, `audit.sync_column_classification()`, retention for every table holding personal data | Docket Rule Group 6: 13 of 95 tables were classified | Requirement register SEC-012 | `test_classification.sql` |
| 025 | Written justification for the 216 nullable columns that follow an exact pattern | Docket Rule Group 5 | Generated attribute catalogue | counts in the catalogue |
| 026 | Currency beside three money columns; language of three user-entered text columns; `audit.refresh_active_views()` | Docket Rule Groups 3 and 7; the `active_` views had gone stale after migration 022 | Checking the live schema against the docket's rule groups; the stale-view check in `test_lifecycle.sql` found the view | `test_domains_and_transitions.sql`, `test_lifecycle.sql` |
| 027 | 25 job roles | `master.job_role` was empty, so every job had a NULL role | Seeding at medium scale and listing empty tables | the data generator |

Code and data fixes made alongside:

| Change | Why | Found by |
|:--|:--|:--|
| Query 10 rewritten | It averaged the time spent in the previous stage, not the time from application to joining, and took 71 ms | KPI-003 reconciliation against the golden dataset |
| `scripts/generate_data.py` rewritten | Seeding twice doubled the data; no random seed; every job `published`; every application had identical timestamps; history inconsistent with status; hard-coded database password | Verification run 2026-10-27 (V-02, V-04) |
| `tests/test_concurrency.py` runs in its own scratch database | It left rows that made the validator fail (V-03) | Verification run |
| `tests/test_benchmark_harness.py` and the report renderer | Two real test defects and one rendering defect (V-01) | Verification run |
| `scripts/backup_restore.sh` rewritten | It swallowed restore errors (`\|\| true`), counted only 7 tables, and included backup time in the recovery time | Reading the script |
| `scripts/run_all_tests.py` rewritten | It only worked through one named Docker container (V-05) | Verification run |

## Changes made in Phase 3 (2026-10-28)

| Change | Why | Found by |
|:--|:--|:--|
| Migration 036: `commercial.post_wallet_entry`, `commercial.download_candidate_profile`, `commercial.credit_price`; the application role loses direct write access to wallets and the ledger | The balance and the ledger were two writes the caller had to keep equal, and the download fee was computed nowhere (EXC-38 to EXC-40, ML-06). Prices are placeholders (DEC-29) | Workflow coverage review of WF-14 |
| Migration 037: trigger `trg_outreach_recipient_block` | BR-021 was a convention in a SELECT | Rule catalogue: rule enforced by query only |
| Workflows WF-15 to WF-21 added; WF-12, WF-13, WF-14 rewritten | 43 of 106 tables were reached by no workflow, and three workflows described a system that no longer existed | Step 16 generator |
| `docs/phase-3-prove/16-gap-owners.json`; the coverage generator now fails on a step with neither a backing artefact nor an owner | Playbook step 16: 100% or a logged gap with an owner | Step 16 |
| Rule catalogue extended from BR-001..027 to BR-001..040, with an owner per rule | Docket rules that the register did not carry (GAP-06 and others) | Step 18 |
| `tests/test_br_decision_and_outreach.sql` | Two rows of the BR-002 decision table, BR-005 and BR-021 had no test | Step 18 |
| Every test file carries a `Covers:` header, checked by `scripts/lifecycle/tag_tests.py --check` | Older tests named no requirement | Step 20 |
| `scripts/run_nfr_checks.py` runs as part of `run_all_tests.py` | The NFR targets had no executable check | Step 20 |
| Requirement register statuses brought up to date (SEC-002, SEC-003, SEC-013, OPS-005 and all 27 NFRs) | They described the schema before migrations 020 to 036 | Step 18 |
| Feature inventory: FEAT-017, 019 to 022, 031, 035 now Implemented; FEAT-043 and FEAT-044 added | The register described RLS, RBAC, roles and audit coverage as not implemented | Step 16 |

## Changes made in Phase 4 (2026-10-28)

| Change | Why | Found by |
|:--|:--|:--|
| Migration 038: identity verification, share events, review figures, place reference, and the legacy-sync tables | Four boundary promises had no table; the docket asks for a sync direction and conflict rule per field | Writing the boundary document from the database |
| Migration 039: 28 foreign-key indexes | Foreign keys that something looks up, or that a parent delete checks, led no index | The table scorecard |
| `22-integration-boundaries.md` generated from the database | The hand-written version described nine different boundaries and tables that do not exist | Reading it against the docket |
| `scripts/run_load_test.py`; wallet debits and logins under 1 to 64 clients | No concurrency measurement beyond 10 threads | Step 28 |
| Load test first version: every client debited one wallet and reused token hashes between levels | The hot wallet showed lock queuing (p95 162 ms at 64 callers); the token reuse was a defect in the test, not the database | Reading the first run's errors |
| Seed fills the integration tables | The scorecard flagged seven empty tables | The table scorecard |
| CI: weekly load-test job, tag check, documents generated from the medium seed | The documents depend on the seed size | Local rehearsal of the CI steps |

## Deferred, with the reason

| Item | Reason it was not done |
|:--|:--|
| A consuming application for the encrypted tax identifiers | None exists in this repository; `scripts/identifier_crypto.py` is the reference it must follow (DEC-25) |
| Human review of retention, classification and NFR targets | The owner delegated these to the assistant; they are recorded as Delegated Decisions and AI-reviewed, not signed off |
| Translations of enumeration display names beyond English | Needs a translator; English falls back for every language (DEC-27) |
| Recruiter saved searches, folders, last-active signal, keyword search | Competitor parity, not in the docket (DEC-26) |
| Real prices for downloads, outreach and postings | The commercial owner sets them; the seed amounts are placeholders (DEC-29) |
| Legacy-system sync direction and conflict rules | Docket asks for them; no legacy source exists to design against (ETL is out of scope) |
| Per-table launch / 1-year / 3-year row-count sheet (step 13) | Not written; the laptop dataset and the projection stand in |

## Note on editing migrations in place

Migrations 020 and 021 were revised several times during development (the audit trigger defaulting `updated_by` to the creator, the `SECURITY DEFINER` change that removed an infinite recursion, a device-table policy). They had not been applied to any shared database, so editing them was safe. One older edit predates this work: migration 008 had a constraint renamed in place (`ck_job_skill_requirement_proficiency` to `..._proficiency_level`), so a database built from the original 008 keeps the old name. From the first shared deployment on, every change must be a new migration.
