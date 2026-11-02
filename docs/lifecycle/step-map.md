# Talentra: Lifecycle Step Map

Generated from [`steps.json`](steps.json) by `scripts/lifecycle/gen_lifecycle_report.py`. **Edit the JSON, not this file.**

**Structure:** the 8 phases and 46 steps of the Talencia Global Data-Driven Development Lifecycle. **Verified:** 2026-10-27.

> Migrations 001-028 applied to a clean PostgreSQL 16.15 instance; 28 test suites executed; the docket's laptop scale (1M candidates, 5M applications, 11 GB) loaded, validated, benchmarked, backed up and restored (see docs/lifecycle/verification-2026-10-27.md). PostgreSQL 17, the declared target, was not available locally; the CI workflow runs on 17 but has not run yet.

## Totals

| Status | Steps | Meaning |
|:--|--:|:--|
| done | 29 | Artifact exists and meets the step's Done-when test |
| partial | 4 | Artifact exists but a Done-when condition is unmet |
| MISSING | 1 | No artifact; in scope for this project |
| deferred | 12 | Outside the hackathon docket scope (UI, ETL, application code); recorded, not built |
| **all** | **46** | |

In-scope steps: **34**, of which **29** are done (85%).

## Gates

| Gate | Phase | Name | Verdict | Basis |
|:--|--:|:--|:--|:--|
| G1 | 1 | Problem understood | **conditional** | Conditions 1 and 3 hold (120/120 requirements have an actor; 23/23 must-haves are in a workflow). Condition 2 holds in form only: all 27 NFR targets are engineer-proposed and unapproved. See docs/phase-1-discover/phase-report.md. |
| G2 | 2 | Model defined | **open** | Open. The generated dictionary is complete in structure but only 253 of 1,144 columns have a written definition (mostly audit and lifecycle columns); 150 nullable columns lack a justification; classification is pattern-based and unreviewed; tax identifiers are unprotected (blocked on human decisions); retention periods are unapproved. Met: every rule has an enforcement point (step 18), every column is classified, every table holding personal data states a retention period. |
| G3 | 3 | Model proven | **open** | DDL runs cleanly (28/28) and all 28 suites pass on a clean PostgreSQL 16.15 database; the seed is reproducible and refuses a second run. Open: workflow coverage is 60 of 88 steps with no owners on the gaps (step 16); 2 decision-table cases are untested (step 18); older tests are not tagged with rule IDs (step 20); PostgreSQL 17 is untested locally. |
| G4 | 4 | Data platform ready | **open** | Open. Met at the docket's laptop scale: loaded and reconciled (4,999,836 applications), validated 15/15, backup and restore round-trip with 0 mismatches (restore 224 s against a 900 s objective), and three queries that missed their proposed targets were fixed and re-measured. Not met: no CI run yet; NFR targets are unapproved; concurrency is proven at 10 connections, not at the proposed 500; no automated stress test. |
| G5 | 5 | Insight validated | **open** | Condition 1 met: all 16 KPIs execute and reconcile with a golden dataset (known answers). Condition 2 not assessed: no dashboard exists, so no dashboard number can be reconciled to its source yet. |
| G6 | 6 | Specification signed off | **deferred** | Product specification is outside the docket (UI out of scope). Only the traceability matrix is in scope. |
| G7 | 7 | Design approved | **deferred** | Application design is outside the docket. |
| G8 | 8 | Release ready | **deferred** | No application code in scope. Database backup/restore (docket B80) is tracked at step 28. |

A phase is complete only when its gate passes. A gate is checked by a reviewer who did not produce the work.

## Phase 1: Discover  (steps 1-5, 5/5 done)

| Step | Name | Status | Artifacts | Docket | Note |
|--:|:--|:--|:--|:--|:--|
| 01 | Requirement Analysis Docket | **done** | [`phase-1-discover/01-requirements.md`](../phase-1-discover/01-requirements.md)<br>[`phase-1-discover/01-scope-assumptions.md`](../phase-1-discover/01-scope-assumptions.md)<br>[`phase-1-discover/01-docket-reconciliation.md`](../phase-1-discover/01-docket-reconciliation.md) | B2, B3 | 120 requirement IDs, 100% with an actor. Reconciliation found 14 gaps, but 7 of them (GAP-01, 02, 04, 07, 08, 10, 11) are in fact implemented and GAP-14 is partly covered; see phase-report section 4. Several headers still say 'docket unavailable'. |
| 02 | Stakeholders, Personas and Roles | **done** | [`phase-1-discover/02-personas.md`](../phase-1-discover/02-personas.md) | - | 8 actors against the docket's 9: Guest exists as a seeded role holding only job.search, but no requirement or persona names it (GAP-05). The role-permission matrix is now in the database: 28 permissions, 99 role mappings (migration 021). |
| 03 | Feature Discovery | **done** | [`phase-1-discover/03-feature-inventory.md`](../phase-1-discover/03-feature-inventory.md)<br>[`phase-1-discover/03-competitive-benchmark.md`](../phase-1-discover/03-competitive-benchmark.md) | - | Competitors researched from their own pages on 2026-10-28: LinkedIn and one foundit page read in full (High); Naukri and foundit terms from search summaries of official pages that blocked the fetch (Medium). 17 capabilities compared, 6 gaps recorded and left unbuilt (DEC-26). Recruiter side only; compliance posture and pricing not researched. |
| 04 | NFR Discovery | **done** | [`phase-1-discover/04-nfr-register.md`](../phase-1-discover/04-nfr-register.md)<br>[`scripts/run_nfr_checks.py`](../../scripts/run_nfr_checks.py)<br>[`benchmarks/results/nfr_results.md`](../../benchmarks/results/nfr_results.md)<br>[`lifecycle/decision-log.md`](../lifecycle/decision-log.md) | - | 27 NFRs: 17 met and measured, 4 met by construction and tested, 3 met for the database but need an operator (availability, delivery sender, backup schedule), 2 boundaries, 1 out of scope, 0 failed. Targets are Delegated Decisions (assistant-set under the owner's delegation), AI-reviewed, not human-approved. |
| 05 | Business Workflow Analysis | **done** | [`phase-1-discover/05-workflows.md`](../phase-1-discover/05-workflows.md)<br>[`phase-1-discover/05-exceptions.md`](../phase-1-discover/05-exceptions.md)<br>[`phase-1-discover/05-audit-event-matrix.md`](../phase-1-discover/05-audit-event-matrix.md)<br>[`scripts/lifecycle/gen_audit_matrix.py`](../../scripts/lifecycle/gen_audit_matrix.py) | - | Audit matrix is generated from the database: 14 of 14 sensitive classes, 21 action codes, 13 audit triggers, 6 writing functions. Exception catalogue updated where migrations 029 and 031 changed an entry (EXC-29, EXC-32); EXC-33 consent suppression remains open. |

## Phase 2: Model  (steps 6-12, 7/7 done)

| Step | Name | Status | Artifacts | Docket | Note |
|--:|:--|:--|:--|:--|:--|
| 06 | Entities Discovery | **done** | [`phase-2-model/06-entity-catalogue.md`](../phase-2-model/06-entity-catalogue.md) | B4, B5, B6, B7, B24, B25, B26, B36, B37, B38, B48, B49, B50 | Generated from the migrated database: 100 tables + 3 partitions. Rule Group 4 conformance is measured per table (every soft/hard/reference table now carries all four audit columns; tested). |
| 07 | Attributes Discovery | **done** | [`phase-2-model/07-attribute-catalogue.md`](../phase-2-model/07-attribute-catalogue.md) | B12, B13, B14, B15, B30, B31, B32, B42, B43, B44, B54, B55, B56 | 1,212 columns across 105 base tables: type, nullability, default, keys, class and protection all generated from the database; every column defined, every nullable column says what NULL means (418 of 418; 35 written by hand). Classification is AI-reviewed (DEC-24), not human-reviewed. |
| 08 | Entity Lifecycle and State Machines | **done** | [`phase-2-model/08-state-machines.md`](../phase-2-model/08-state-machines.md) | - | 24 governed state machines (legal moves in master.status_transition, enforced by trigger, tested) and 5 recorded exemptions with reasons; no status column is undecided (tests/test_state_machines.sql). |
| 09 | Database, Tables and Relationships Discovery | **done** | [`phase-2-model/09-er-diagram.md`](../phase-2-model/09-er-diagram.md)<br>[`phase-2-model/09-architecture.md`](../phase-2-model/09-architecture.md)<br>[`db/migrations/001_create_schemas.sql`](../../db/migrations/001_create_schemas.sql) | B8, B9, B10, B11, B16, B17, B18, B19, B27, B28, B29, B39, B40, B41, B51, B52, B53 | 10 bounded schemas, 105 base tables; the gig-versus-core decision is recorded as DEC-28. |
| 10 | Data Dictionary v1 | **done** | [`phase-2-model/07-attribute-catalogue.md`](../phase-2-model/07-attribute-catalogue.md)<br>[`phase-2-model/10-data-dictionary.md`](../phase-2-model/10-data-dictionary.md)<br>[`db/migrations/033_document_columns.sql`](../../db/migrations/033_document_columns.sql)<br>[`tests/test_column_definitions.sql`](../../tests/test_column_definitions.sql) | - | Dictionary generated from the database: 1,212 of 1,212 columns defined (migration 033 and later), with class, protection and nullability reasons; tests/test_column_definitions.sql keeps it complete. |
| 11 | Data Rules and Constraints Discovery | **done** | [`phase-2-model/11-rule-compliance.md`](../phase-2-model/11-rule-compliance.md)<br>[`phase-1-discover/01-requirements.md`](../phase-1-discover/01-requirements.md)<br>[`tests/test_enumerations.sql`](../../tests/test_enumerations.sql)<br>[`db/migrations/035_add_enumeration_catalogue.sql`](../../db/migrations/035_add_enumeration_catalogue.sql) | B20, B21, B22, B33, B34, B35, B45, B46, B47, B57, B58, B59 | All ten docket rule groups tabulated in 11-rule-compliance.md; none is a deviation. Enumerations: CHECK is authority, mirrored by a lookup table with English labels (DEC-27). Retention approvals are the assistant's (DEC-23). |
| 12 | Data Classification and Privacy | **done** | [`phase-2-model/12-tax-id-security-design.md`](../phase-2-model/12-tax-id-security-design.md)<br>[`phase-2-model/12-threat-model.md`](../phase-2-model/12-threat-model.md)<br>[`db/migrations/021_add_access_control.sql`](../../db/migrations/021_add_access_control.sql)<br>[`db/migrations/024_add_column_classification.sql`](../../db/migrations/024_add_column_classification.sql)<br>[`tests/test_access_control.sql`](../../tests/test_access_control.sql)<br>[`tests/test_classification.sql`](../../tests/test_classification.sql)<br>[`db/migrations/034_encrypt_organization_identifier.sql`](../../db/migrations/034_encrypt_organization_identifier.sql)<br>[`scripts/identifier_crypto.py`](../../scripts/identifier_crypto.py)<br>[`tests/test_identifier_encryption.sql`](../../tests/test_identifier_encryption.sql) | B75, B76, B77, B78, B81 | 5 roles, row-level security on candidate and organisation tables, masking view, hash-format checks, append-only enforcement, erasure, column classification, tax identifiers encrypted (DEC-25). AI-reviewed under the owner's delegation; the encryption has no consuming application yet and the seed key is public. |

## Phase 3: Prove  (steps 13-21, 9/9 done)

| Step | Name | Status | Artifacts | Docket | Note |
|--:|:--|:--|:--|:--|:--|
| 13 | Data Volumetrics and Distribution Profile | **done** | [`phase-4-platform/28-performance-report.md`](../phase-4-platform/28-performance-report.md)<br>[`benchmarks/results/scale_comparison.md`](../../benchmarks/results/scale_comparison.md)<br>[`phase-3-prove/13-volume-sheet.md`](../phase-3-prove/13-volume-sheet.md)<br>[`scripts/lifecycle/gen_volume_sheet.py`](../../scripts/lifecycle/gen_volume_sheet.py) | B74 | Two measured sizes 100x apart (10K and 1M candidates; 50K and 5M applications) with the distributions that produced them, and a generated per-table volume sheet (launch, one year, three years; null rates; size). The model puts the laptop dataset at 10.5 GB against 11 GB measured, and the docket target at about 150 GB (a projection). |
| 14 | Sample Data Generation (Discovery) | **done** | [`db/seeds/development_data.sql`](../../db/seeds/development_data.sql)<br>[`db/seeds/golden_dataset.sql`](../../db/seeds/golden_dataset.sql)<br>[`scripts/generate_data.py`](../../scripts/generate_data.py)<br>[`tests/golden_kpi_expected.json`](../../tests/golden_kpi_expected.json)<br>[`tests/test_golden_kpis.py`](../../tests/test_golden_kpis.py) | B60, B61, B62, B63, B64 | Seeded and reproducible (--seed), with a hand-built golden dataset whose KPI answers are known and reconciled (tests/test_golden_kpis.py). At medium and laptop scale every base table except audit.system_error_log is populated; that one is written by the application. |
| 15 | Test Suite v1 (Data) | **done** | [`tests/test_access_control.sql`](../../tests/test_access_control.sql)<br>[`tests/test_classification.sql`](../../tests/test_classification.sql)<br>[`tests/test_constraints.sql`](../../tests/test_constraints.sql)<br>[`tests/test_domains_and_transitions.sql`](../../tests/test_domains_and_transitions.sql)<br>[`tests/test_identity.sql`](../../tests/test_identity.sql)<br>[`tests/test_lifecycle.sql`](../../tests/test_lifecycle.sql)<br>[`tests/test_master_data.sql`](../../tests/test_master_data.sql) | B66 | Executed 2026-10-28 on PostgreSQL 17.11: every SQL suite passes, and the runner also flags FAIL markers, not just ERROR lines. |
| 16 | Schema Coverage against Business Workflow | **done** | [`phase-3-prove/16-workflow-coverage.md`](../phase-3-prove/16-workflow-coverage.md)<br>[`phase-3-prove/16-gap-owners.json`](../phase-3-prove/16-gap-owners.json)<br>[`scripts/lifecycle/gen_workflow_coverage.py`](../../scripts/lifecycle/gen_workflow_coverage.py)<br>[`phase-1-discover/05-workflows.md`](../phase-1-discover/05-workflows.md) | B67, B68, B69 | 21 workflows, 129 steps; 124 are backed by a table, function, view, governed state machine, query, script or another workflow, and the other 5 are owned by Application (named in 16-gap-owners.json); no table is unreached by a workflow (107 of 107); every workflow states which sensitive action classes it evidences. The generator fails when a step has neither a backing artefact nor an owner. |
| 17 | Design-Based Refinement | **done** | [`gate-reviews/phase2c-documentation-audit.md`](../gate-reviews/phase2c-documentation-audit.md)<br>[`gate-reviews/phase3-followup-findings.md`](../gate-reviews/phase3-followup-findings.md)<br>[`phase-3-prove/17-change-log.md`](../phase-3-prove/17-change-log.md) | - | Change log updated through Phase 3 with reasons; the deferred list now names what is left and why. |
| 18 | Business Rules and Data Constraints v2 | **done** | [`phase-3-prove/18-business-rules-catalogue.md`](../phase-3-prove/18-business-rules-catalogue.md)<br>[`phase-3-prove/18-rule-extensions.json`](../phase-3-prove/18-rule-extensions.json)<br>[`scripts/lifecycle/gen_rules_catalogue.py`](../../scripts/lifecycle/gen_rules_catalogue.py)<br>[`tests/test_br_decision_and_outreach.sql`](../../tests/test_br_decision_and_outreach.sql)<br>[`db/migrations/037_enforce_outreach_block_rule.sql`](../../db/migrations/037_enforce_outreach_block_rule.sql) | - | 40 rules (BR-001..027 from the register, BR-028..040 added from the docket), each with an owner role, an enforcement point checked against the live catalog (39 database, 1 reconciled), and a named test. All four rows of the BR-002 decision table are tested; BR-005 and BR-021 moved into the database (migration 037). |
| 19 | Data Dictionary v2 | **done** | [`phase-2-model/07-attribute-catalogue.md`](../phase-2-model/07-attribute-catalogue.md)<br>[`.github/workflows/ci.yml`](../../.github/workflows/ci.yml)<br>[`scripts/lifecycle/gen_model_catalogues.py`](../../scripts/lifecycle/gen_model_catalogues.py) | - | Dictionary is generated from the database, and the CI step 'generated documents are up to date' fails when it differs. The hand-written 10-data-dictionary.md is superseded by it. |
| 20 | Test Suite v2 (Data, Business and NFR) | **done** | [`tests/test_business_rules.sql`](../../tests/test_business_rules.sql)<br>[`tests/test_concurrency.py`](../../tests/test_concurrency.py)<br>[`tests/test_golden_kpis.py`](../../tests/test_golden_kpis.py)<br>[`tests/test_wallet_functions.sql`](../../tests/test_wallet_functions.sql)<br>[`scripts/run_nfr_checks.py`](../../scripts/run_nfr_checks.py)<br>[`scripts/lifecycle/tag_tests.py`](../../scripts/lifecycle/tag_tests.py) | B79 | 39 suites: 34 SQL, concurrency (4 tests, including the wallet function under 40 simultaneous debits), golden-dataset KPIs, benchmark harness, identifier crypto and an NFR measurement run. Every test file carries a Covers: header naming the requirement, rule and NFR IDs, checked by tag_tests.py --check; no requirement lacks a test or script, and no test lacks a requirement. |
| 21 | Baseline ER and Physical Model | **done** | [`phase-2-model/09-er-diagram.md`](../phase-2-model/09-er-diagram.md)<br>[`db/migrations/019_create_analytics_marts.sql`](../../db/migrations/019_create_analytics_marts.sql)<br>[`db/migrations/026_fix_domain_rule_gaps.sql`](../../db/migrations/026_fix_domain_rule_gaps.sql)<br>[`db/migrations/027_seed_job_roles.sql`](../../db/migrations/027_seed_job_roles.sql)<br>[`db/migrations/028_add_query_performance_structures.sql`](../../db/migrations/028_add_query_performance_structures.sql) | B23, B82 | 37 of 37 migrations apply cleanly from empty on PostgreSQL 17.11 (the target) and applied on 16.15 earlier; the backup and restore check confirmed identical row counts and object counts at 11 GB. The CI workflow is written but has not run on GitHub. |

## Phase 4: Platform  (steps 22-28, 6/7 done)

| Step | Name | Status | Artifacts | Docket | Note |
|--:|:--|:--|:--|:--|:--|
| 22 | Integration and Source Mapping | **done** | [`phase-4-platform/22-integration-boundaries.md`](../phase-4-platform/22-integration-boundaries.md)<br>[`scripts/lifecycle/gen_integration_doc.py`](../../scripts/lifecycle/gen_integration_doc.py)<br>[`db/migrations/038_add_integration_data_structures.sql`](../../db/migrations/038_add_integration_data_structures.sql)<br>[`tests/test_integration_structures.sql`](../../tests/test_integration_structures.sql) | - | The nine docket boundaries are generated from messaging.integration_boundary with their stored-versus-referenced data, failure behaviour, retry policy and the database objects that hold what each promises (every object checked in the catalog). Four promises had no table behind them (identity verification, social sharing, company reviews, geocoding place reference) and now do (migration 038). Legacy sync: 60 mapped columns, 31 synchronised with a direction, one of five conflict rules and an owner role, and 29 recorded as not synchronised with the reason; the legacy field names are assumptions because no legacy schema existed. |
| 23 | Data Generation at Scale | **done** | [`benchmarks/results/scale_comparison.md`](../../benchmarks/results/scale_comparison.md)<br>[`scripts/generate_data.py`](../../scripts/generate_data.py) | B60, B61 | Run on 2026-10-27: 1,000,000 candidates, 100,000 jobs, 4,999,836 applications, 9,636,883 status events, 11 GB, loaded in 1,414 s (23.6 min); validator 15/15 at that scale. Volumes follow the step 13 distributions. A 3-year volume (to find where performance degrades) is projected in scale_comparison.md, not generated. |
| 24 | Data Seeding | **done** | [`db/seeds/reference_data.sql`](../../db/seeds/reference_data.sql)<br>[`db/seeds/development_data.sql`](../../db/seeds/development_data.sql)<br>[`db/migrations/004_seed_master_reference_data.sql`](../../db/migrations/004_seed_master_reference_data.sql) | B62, B63, B64 | A fresh database seeds in 0.4 s (dev) to 9 s (medium) and the same seed gives the same shape. The seed now also fills the integration tables (verifications, share events, review figures, legacy ids, outbox events). Seeding a populated database is refused; --append is the explicit opt-in. |
| 25 | Data Ingestion | **deferred** | - | - | ETL and data migration are explicitly out of scope in the docket (issued as a separate requirement). Not designed here. |
| 26 | Test Automation (Data Quality and Analytics) | **done** | [`scripts/validate_data.py`](../../scripts/validate_data.py)<br>[`scripts/lifecycle/gen_quality_scorecard.py`](../../scripts/lifecycle/gen_quality_scorecard.py)<br>[`phase-4-platform/26-table-quality.md`](../phase-4-platform/26-table-quality.md)<br>[`phase-4-platform/26-27-28-test-automation.md`](../phase-4-platform/26-27-28-test-automation.md)<br>[`.github/workflows/ci.yml`](../../.github/workflows/ci.yml) | B66 | Validator 15/15 on dev, medium and laptop seeds; a per-table scorecard (7 checks) puts all 113 tables at 7/7 after it found 41 tables with unindexed foreign keys (migration 039) and 5 empty tables. CI is written but has not run on GitHub. |
| 27 | Test Automation (Business Rules) | **done** | [`scripts/run_all_tests.py`](../../scripts/run_all_tests.py)<br>[`scripts/lifecycle/tag_tests.py`](../../scripts/lifecycle/tag_tests.py)<br>[`phase-4-platform/26-27-28-test-automation.md`](../phase-4-platform/26-27-28-test-automation.md)<br>[`.github/workflows/ci.yml`](../../.github/workflows/ci.yml) | - | run_all_tests.py runs 40 suites against any PostgreSQL; every rule in the catalogue names its test and tag_tests.py --check enforces the reverse; the CI workflow runs all of it plus the generated-documents check (not yet run on GitHub). |
| 28 | Test Automation (NFR) | **done** | [`phase-4-platform/26-27-28-test-automation.md`](../phase-4-platform/26-27-28-test-automation.md)<br>[`scripts/run_nfr_checks.py`](../../scripts/run_nfr_checks.py)<br>[`scripts/run_load_test.py`](../../scripts/run_load_test.py)<br>[`benchmarks/results/nfr_results.md`](../../benchmarks/results/nfr_results.md)<br>[`benchmarks/results/load_test.md`](../../benchmarks/results/load_test.md)<br>[`benchmarks/results/scale_comparison.md`](../../benchmarks/results/scale_comparison.md)<br>[`scripts/run_benchmarks.py`](../../scripts/run_benchmarks.py)<br>[`scripts/backup_restore.sh`](../../scripts/backup_restore.sh) | B65, B70, B71, B72, B73, B74, B80 | Benchmarks at 10K and 1M candidates, NFR checks (write, 500 sessions, master lookups, 50,000-application pipeline), a mixed-workload load test at 1, 8, 32 and 64 clients (no errors, no wallet drift, no device-limit breach, worst p95 18.5 ms at 64 clients), and backup/restore at 11 GB (restore 224 s of 900 s). Not done: 500 simultaneous connections, a soak test, and a repeat of the laptop run on the current schema. |

## Phase 5: Insight  (steps 29-30, 1/2 done)

| Step | Name | Status | Artifacts | Docket | Note |
|--:|:--|:--|:--|:--|:--|
| 29 | KPI Discovery | **done** | [`phase-5-insight/29-kpi-catalogue.md`](../phase-5-insight/29-kpi-catalogue.md)<br>[`db/kpi/01_hiring_volume.sql`](../../db/kpi/01_hiring_volume.sql)<br>[`scripts/lifecycle/gen_kpi_catalogue.py`](../../scripts/lifecycle/gen_kpi_catalogue.py) | - | 16 KPIs, each a SQL file the generator executes (16 of 16 compute) and each reconciled to a hand-built golden dataset with known answers. Targets are unset (none in the docket; owners must approve). |
| 30 | Business Intelligence and Analytics (C-Suite) | **MISSING** | [`db/migrations/019_create_analytics_marts.sql`](../../db/migrations/019_create_analytics_marts.sql)<br>[`db/migrations/023_add_analytics_loader.sql`](../../db/migrations/023_add_analytics_loader.sql)<br>[`db/queries/10_analytics_time_to_hire_kpi.sql`](../../db/queries/10_analytics_time_to_hire_kpi.sql)<br>[`tests/test_golden_kpis.py`](../../tests/test_golden_kpis.py) | B49, B52, B55, B58 | The star schema now has a real load process (migration 023) and 16 KPIs reconcile with a golden dataset. Still missing: the executive question set and a dashboard (UI is out of scope, but SQL views and the reconciliation are not). |

## Phase 6: Specify  (steps 31-35, 1/5 done)

| Step | Name | Status | Artifacts | Docket | Note |
|--:|:--|:--|:--|:--|:--|
| 31 | Feature Analysis and Requirements Engineering | **deferred** | - | - | User stories and prioritised backlog are application-level; the docket asks for a database design only. |
| 32 | PRD (Product Requirements Document) | **deferred** | - | - | No product build in scope. |
| 33 | Requirements vs Database Gap Analysis | **partial** | [`phase-1-discover/01-docket-reconciliation.md`](../phase-1-discover/01-docket-reconciliation.md) | - | A docket-to-requirement reconciliation exists; it needs correction (7 false gaps) and a requirement-to-table mapping. |
| 34 | Traceability Matrix | **done** | [`phase-6-specify/34-traceability-matrix.md`](../phase-6-specify/34-traceability-matrix.md)<br>[`scripts/lifecycle/gen_traceability.py`](../../scripts/lifecycle/gen_traceability.py) | - | Generated from the requirement register. Test and KPI links are limited to what the register names; code links are migration line references. |
| 35 | UAT Scenarios Test Suite Discovery | **deferred** | - | - | No users or UI in scope. |

## Phase 7: Design  (steps 36-41, 0/6 done)

| Step | Name | Status | Artifacts | Docket | Note |
|--:|:--|:--|:--|:--|:--|
| 36 | Prototyping | **deferred** | - | - | UI is out of scope. |
| 37 | Architecture Definition | **partial** | [`phase-2-model/09-architecture.md`](../phase-2-model/09-architecture.md) | B1 | Database architecture is documented (modular monolith, PostgreSQL). The engine choice has no ADR recording the rejected option (MySQL). |
| 38 | HLD (High-Level Design) | **deferred** | - | - | Application component design is outside the docket. |
| 39 | LLD (Low-Level Design) | **deferred** | - | - | No API layer in scope. |
| 40 | Test Suite (Functional) | **deferred** | - | - | No application features to test. |
| 41 | Test Suite (Integration, E2E and Security) | **partial** | [`tests/test_access_control.sql`](../../tests/test_access_control.sql)<br>[`tests/test_administration.sql`](../../tests/test_administration.sql)<br>[`tests/test_security.sql`](../../tests/test_security.sql) | B78, B79 | Database-level access and audit tests now exist and act as each role (tests/test_access_control.sql): tenant isolation, spoofing, blocked candidates, append-only, masking. No application-layer tests (out of scope). |

## Phase 8: Release  (steps 42-46, 0/5 done)

| Step | Name | Status | Artifacts | Docket | Note |
|--:|:--|:--|:--|:--|:--|
| 42 | Code Generation | **deferred** | - | - | No application code in scope. |
| 43 | AI Output Review and Code Verification | **deferred** | - | - | Applies once code exists. Review of this repository's own AI-assisted output is recorded under docs/gate-reviews. |
| 44 | Test Execution and Defect Loop | **partial** | [`lifecycle/verification-2026-10-27.md`](../lifecycle/verification-2026-10-27.md) | - | Execution run recorded with defects and their closure. No standing defect log with severities. |
| 45 | Release | **deferred** | - | B80 | No CI/CD or release in scope. Backup and restore is tracked at step 28. |
| 46 | Observe and Learn | **deferred** | - | - | No production system. |

## Docket crosswalk (B1-B82 to lifecycle steps)

The docket's five delivery phases are a different cut of the same work. Each backlog item maps to the lifecycle step that produces its deliverable.

| Backlog | Step(s) | Backlog | Step(s) | Backlog | Step(s) |
|:--|:--|:--|:--|:--|:--|
| B1 | 37 | B2 | 01 | B3 | 01 |
| B4 | 06 | B5 | 06 | B6 | 06 |
| B7 | 06 | B8 | 09 | B9 | 09 |
| B10 | 09 | B11 | 09 | B12 | 07 |
| B13 | 07 | B14 | 07 | B15 | 07 |
| B16 | 09 | B17 | 09 | B18 | 09 |
| B19 | 09 | B20 | 11 | B21 | 11 |
| B22 | 11 | B23 | 21 | B24 | 06 |
| B25 | 06 | B26 | 06 | B27 | 09 |
| B28 | 09 | B29 | 09 | B30 | 07 |
| B31 | 07 | B32 | 07 | B33 | 11 |
| B34 | 11 | B35 | 11 | B36 | 06 |
| B37 | 06 | B38 | 06 | B39 | 09 |
| B40 | 09 | B41 | 09 | B42 | 07 |
| B43 | 07 | B44 | 07 | B45 | 11 |
| B46 | 11 | B47 | 11 | B48 | 06 |
| B49 | 06, 30 | B50 | 06 | B51 | 09 |
| B52 | 09, 30 | B53 | 09 | B54 | 07 |
| B55 | 07, 30 | B56 | 07 | B57 | 11 |
| B58 | 11, 30 | B59 | 11 | B60 | 14, 23 |
| B61 | 14, 23 | B62 | 14, 24 | B63 | 14, 24 |
| B64 | 14, 24 | B65 | 28 | B66 | 15, 26 |
| B67 | 16 | B68 | 16 | B69 | 16 |
| B70 | 28 | B71 | 28 | B72 | 28 |
| B73 | 28 | B74 | 13, 28 | B75 | 12 |
| B76 | 12 | B77 | 12 | B78 | 12, 41 |
| B79 | 20, 41 | B80 | 28, 45 | B81 | 12 |
| B82 | 21 |  |  |  |  |

**82 of 82 backlog items are mapped to a step.** Unmapped: none.

