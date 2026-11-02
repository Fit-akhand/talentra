# Non-Functional Requirement Register

**Phase 1, step 4.** Rewritten 2026-10-28. Replaces the register of 2026-10-21, in which every target was an unapproved proposal and 9 of 27 had no measurement.
Measurements come from `scripts/run_benchmarks.py` (benchmark queries), `scripts/run_nfr_checks.py` (write latency, concurrency, master lookups, 50,000-application pipeline), the test suites, and `scripts/backup_restore.sh`. Raw results: `benchmarks/results/`.

## 1. Provenance

| Label | Meaning |
|:--|:--|
| `Docket` | Stated in the Talentra docket (scale, laptop dataset, 900 s recovery objective, device limits, retry policy) |
| `Delegated Decision` | A target the docket does not give. The project owner delegated product decisions to the assistant on 2026-10-28; the assistant set the target, recorded the reason, and attached evidence. Not a human approval: the owner may change any of these |
| `Configuration` | A setting or boundary, not a service level |
| `Out of scope` | Not a property of a database design; reason given |

A `Delegated Decision` target is a real target with evidence, but it has no business sign-off behind it. Gate reviews that rely on it are **AI-reviewed**, not human-approved. Decision references are in [`../lifecycle/decision-log.md`](../lifecycle/decision-log.md).

## 2. Verdict

| Status | Count | NFRs |
|:--|--:|:--|
| **Met, measured** | 17 | 001, 002, 003, 004, 005, 006, 009, 010, 012, 013, 014, 015, 016, 017, 018, 021, 024 |
| **Met by construction, tested** | 4 | 020, 022, 026, 027 |
| **Met for the database; needs an operator** | 3 | 007, 008, 011 |
| **Boundary / configuration** | 2 | 023, 025 |
| **Out of scope** | 1 | 019 |
| **Failed** | 0 | |

Environment of every measurement: PostgreSQL 17.11 in Docker for the checks run on 2026-10-27/28; PostgreSQL 16.15 for the benchmark queries at 10,000 and 1,000,000 candidates (a re-run on 17 at 1M was not repeated). Medium dataset: 10,000 candidates, 1,000 jobs, 50,000 applications. Laptop dataset (docket): 1,000,000 candidates, 100,000 jobs, 5,000,000 applications, 11 GB.

## 3. The register

### 3.1 Performance

| ID | Requirement | Target | Provenance | Method | Evidence | Status |
|:--|:--|:--|:--|:--|:--|:--|
| NFR-001 | Candidate search | p95 <= 50 ms, p99 <= 100 ms, medium and laptop | Delegated Decision | `run_benchmarks.py` Q01, non-empty result required | Medium p95 **1.05 ms**; laptop p50 **0.5 ms**, p95 **0.53 ms**. Before migration 028 the laptop figure was 491 ms and failed | **Met** |
| NFR-002 | Point reads and feed | p95 <= 20 ms (Q02, Q06, Q07, Q09) | Delegated Decision | `run_benchmarks.py` | Medium: Q02 0.37, Q06 0.44, Q09 0.08 ms. Laptop: Q02 0.39, Q06 0.40, Q07 **14.1 ms** (the gig availability search, slowest) | **Met** |
| NFR-003 | Single-row write | p95 <= 50 ms for an application insert with its stage-history trigger and commit | Delegated Decision | `run_nfr_checks.py` | 248 inserts: p50 0.58, **p95 0.63 ms**, max 1.6 ms (loopback, default fsync). Trigger wrote 423 history rows in the same run | **Met** |
| NFR-004 | Analytics queries | p95 <= 25 ms for Q10, Q11 | Delegated Decision | `run_benchmarks.py` | Medium Q10 0.07, Q11 0.22 ms; laptop Q10 0.07 ms (reads a materialised view since 028) | **Met** |
| NFR-005 | Concurrent sessions | 500 sessions, 0 device-limit breaches, 0 deadlocks | Docket (device limit) / Delegated (500) | `run_nfr_checks.py` | 500 users logged in concurrently: 500/500 succeeded in 1.1 s. 500 concurrent attempts by one user with a 2-device limit: **exactly 2** succeeded, 2 sessions open, 0 deadlocks. At most 80 connections were in flight (server `max_connections` is 100); a pooler fronts a real deployment | **Met**, with that qualification |
| NFR-006 | Master-data lookup | p95 <= 5 ms | Delegated Decision | `run_nfr_checks.py` | 265 lookups: **p95 0.19 ms**. The master tables in the dev seed are small; the lookups use unique indexes, so they do not grow with other tables | **Met** |

### 3.2 Availability, continuity, recovery

| ID | Requirement | Target | Provenance | Method | Evidence | Status |
|:--|:--|:--|:--|:--|:--|:--|
| NFR-007 | Availability | 99.9% monthly (about 43.8 min) | Delegated Decision | An external probe; the database supplies `audit.ops_database`, `ops_connections`, `ops_replication` and a container health check | Availability is a property of a running deployment. A design repository cannot show it. No replica or failover is delivered, so 99.9% needs the operator to add one | **Database side met; needs an operator** |
| NFR-008 | Notification delivery latency | p95 to sent <= 60 s; to delivered <= 5 min | Delegated Decision | `audit.ops_delivery_latency` | The view computes both percentiles from `messaging.notification_delivery`; it returns a row per channel. The seed once produced negative latencies (delivery rows were created after they were sent); the generator now writes `created_at`, and the view is checked for non-negative values below. The sender is outside the database | **Database side met; needs the sender** |
| NFR-010 | Recovery time | <= 900 s | Docket | `scripts/backup_restore.sh` | Medium: restore 1 s. **Laptop, 11 GB: restore 224 s**, 103 tables, 0 row-count mismatches, schema-object counts equal | **Met** |
| NFR-011 | Recovery point | <= 24 h | Delegated Decision | The backup script plus `audit.maintenance_run` | Backup and verified restore take 71 s + 224 s at 11 GB, so a daily backup fits. The repository does not schedule backups on a host, and there is no WAL archive, so point-in-time recovery is not offered | **Needs an operator to schedule the script** |

### 3.3 Scale and reproducibility

| ID | Requirement | Target | Provenance | Method | Evidence | Status |
|:--|:--|:--|:--|:--|:--|:--|
| NFR-009 | Pipeline at volume | 50,000 applications on one job, aggregation p95 <= 25 ms | Delegated Decision | `run_nfr_checks.py` (Q03 against 50,009 applications) | 30 runs: p50 7.2, **p95 7.7 ms**, 6 stages returned. Loading 50,000 rows with the history trigger took 1.6 s | **Met** |
| NFR-022 | Reproducible from a clean checkout | All migrations apply from empty, no manual step | Delegated Decision | `psql -v ON_ERROR_STOP=1` per file; CI | 34 of 34 apply on PostgreSQL 17.11 from empty, repeatedly. The CI workflow is written but has **not yet run on GitHub** | **Met locally; CI unrun** |
| NFR-023 | PostgreSQL version | 17 target; 16 supported | Configuration | Tests on both | Suites and generated documents agree on 16.15 and 17.11 | **Boundary** |
| NFR-025 | Resource envelope | Laptop dataset in <= 16 GB RAM, <= 4 vCPU; <= 200 GB at 10M candidates / 100M applications | Delegated Decision | Measured at 1M; projected beyond | 11 GB for the laptop dataset on a default-configuration server. The volume sheet ([`13-volume-sheet.md`](../phase-3-prove/13-volume-sheet.md)) models 10.5 GB for that dataset (within 5% of the measurement) and about 150 GB at the docket's target; 200 GB leaves headroom. The target figure is a **projection**; the earlier 100 GB figure was too low | **Boundary (measured to 1M, projected beyond)** |

### 3.4 Integrity and data quality

| ID | Requirement | Target | Provenance | Method | Evidence | Status |
|:--|:--|:--|:--|:--|:--|:--|
| NFR-012 | Ledgers reconcile | 0 unreconciled wallets | Docket | Validator RG7; KPI-007 | Validator passes; the golden dataset reconciles to the cent | **Met** |
| NFR-013 | Consent and blocks on every candidate read path | 100% | Delegated Decision | `tests/test_candidate_privacy.sql` | `core.can_view_candidate()` is the single read policy on `candidate_profile` and on 9 child tables (migration 030). Recruiters-only profiles need an organisation context; blocks are respected. The policy applies to every non-owner role, including the application role; the benchmark queries run as the table owner and so repeat only the visibility value, not the policy | **Met** |
| NFR-014 | Credentials hashed | 100% argon2id/bcrypt format | Docket | Validator RG6; CHECK constraints | The database rejects any other format (migration 021) | **Met** |
| NFR-015 | Data quality | Validator 15/15 | Delegated Decision | `validate_data.py` | 15/15 on dev, medium and laptop datasets, and after the test suites ran | **Met** |
| NFR-016 | Audit coverage | 14 of 14 sensitive classes | Docket | `tests/test_audit_coverage.sql`; `05-audit-event-matrix.md` | All 14 classes performed and checked; 21 action codes; nothing secret in the trail | **Met** |
| NFR-017 | Retention and purge | Policy per table; purge audited | Delegated Decision | `core.purge_expired_data`; `tests/test_integration_maintenance.sql` | Retention periods approved as DEC-23 (except accounts); each purge writes `audit.maintenance_run` | **Met** |
| NFR-018 | Consent recorded | Every account has consent; disclosure follows consent | Delegated Decision | `core.accounts_missing_consent()`; self-registration trigger | Returns no account on the validated seed; `can_view_candidate` reads consent and blocks | **Met** |
| NFR-021 | No cardholder data | 0 card number, CVV or expiry columns | Docket | Catalogue scan (this register's author ran it) | 0 columns match card/CVV/expiry patterns; only gateway references are stored | **Met** |
| NFR-024 | Documentation | Every column defined; every nullable column says what NULL means | Delegated Decision | `tests/test_column_definitions.sql` | 943 definitions added by migration 033; the test fails otherwise | **Met** |

### 3.5 Operations

| ID | Requirement | Target | Provenance | Method | Evidence | Status |
|:--|:--|:--|:--|:--|:--|:--|
| NFR-019 | Accessibility | - | Out of scope | - | A user-interface property. The database holds language and translation keys (`messaging.ui_translation`) but renders nothing | **Out of scope** |
| NFR-020 | Mart freshness | <= 24 h | Delegated Decision | `audit.ops_job_freshness`; `core.run_maintenance()` | The `maintenance` service in `docker-compose.yml` loops `CALL core.run_maintenance()`, which refreshes the marts and records each run. Verified in an isolated compose project | **Met by construction** |
| NFR-026 | Telemetry | >= 4 metric families readable | Delegated Decision | `audit.ops_*` views, `pg_stat_statements` | 7 views: slow queries, connections, replication lag, job freshness, database size, integration health, delivery latency. Scraping them is the operator's exporter | **Met by construction** |
| NFR-027 | Failing integration isolated | <= 3 attempts with backoff, then dead letter | Docket | `messaging.integration_event`; `tests/test_integration_maintenance.sql` | Enqueue, claim, complete, fail, requeue functions; third failure dead-letters; replays by idempotency key are no-ops | **Met** |

## 4. What was previously missing and is now settled

| Earlier gap | Outcome |
|:--|:--|
| Five benchmark queries returned no rows (OQ-005) | Cause was the data generator; rewritten. 12 of 12 queries return rows |
| No write, concurrency, master-lookup or pipeline-volume measurement | `run_nfr_checks.py` |
| Audit coverage at 2 of 14 classes | 14 of 14 (migration 029) |
| No retention or purge | Migration 031 |
| No telemetry, no dead-letter mechanism | Migration 031 |
| RTO unmeasured | Measured at 11 GB |
| Accessibility undefined (OQ-004) | Out of scope, with reason |

## 5. Still open

- **No human sign-off** on any `Delegated Decision` target (tracked as OQ-002).
- **RPO and availability** depend on an operator: scheduled backups, a replica. Nothing in this repository can prove them.
- **NFR-025 beyond 1M candidates** is projected.
- **NFR-005** was measured with at most 80 simultaneous connections, not 500; the logic under test is the row lock inside the login function, which the 500 attempts did contend for.
- The CI workflow has not run on GitHub.
