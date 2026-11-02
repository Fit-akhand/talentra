# Talentra Phase 2D — Documentation Correction Report

**Date**: 2026-10-21
**Phase**: 2D — Documentation Corrections Only
**Source of truth**: `docs/phase2c-documentation-audit.md` (69 findings)
**Branch**: `feature/your-task` @ `7ac5b2b`
**Nature of this phase**: documentation-only. No schema, index, constraint, migration, application-code, or test change.

---

## 1. Files Changed in Phase 2D

Four documentation files were edited. `README.md` and `docs/performance-report.md` were **not** touched in this phase.

| File | Lines changed | Nature |
|:--|--:|:--|
| `docs/architecture.md` | 27 | Partitioning, pruning %, lock target, PK/UTC/FK invariants, wallet reconciliation, MV refresh, engine tuning, ACID claim, schema table completeness |
| `docs/threat-model.md` | 117 | RLS and roles reframed as proposed, compliance header, trigger names, TRUNCATE limits, IP/masking/enforcement claims, audit DDL, RPO/RTO, new §8 scope table |
| `docs/competitive-benchmark.md` | 14 | SOC 2 attestation, partitioning, pruning %, buffer residency, WAL mechanism, concurrency scale, latency figure, third-party footnote |
| `docs/rule-compliance.md` | 47 | Four non-existent object names, RG6 mechanism mischaracterization, RG7 trigger name, RG9 lock target, static "100% COMPLIANT" framing |

**Created**: `docs/phase2d-documentation-correction-report.md` (this file, untracked).

---

## 2. Corrections Applied, with Evidence

Each row records the old claim, the new claim, the audit finding it resolves, and the repository evidence supporting the change. Classification vocabulary follows the Phase 2C audit: **implemented** (verifiable in `db/migrations/`), **tested** (covered by a test in `tests/`), **measured** (a historical benchmark figure, with its date), **proposed** (design intent, not deployed), **external** (not claimed — requires evidence outside the repository).

### 2.1 `docs/architecture.md`

| # | Old claim | New claim | Finding | Evidence | Class |
|:--|:--|:--|:--|:--|:--|
| A1 | "ACID guarantees ensure atomic consistency **in under 2 milliseconds**" | "a single ACID transaction guarantees atomic consistency across these writes" + note that no benchmark measures it and that `recruitment.job_posting` tracks `vacancy_count` only | A-10, A-11 | No cross-domain-write query in `db/queries/`; `grep` for `headcount\|filled_count` across `db/ scripts/ tests/` → no matches; `vacancy_count INTEGER NOT NULL DEFAULT 1` at `008:30` | Proposed (claim removed) |
| A2 | "acquires a row-level lock … on the user's allocated licence seat in `commercial.licence_seat_allocation`" | "on the `core.user_account` row of the user being logged in … The licence seat allocation is read to derive the device entitlement, but it is not the locked resource" | A-05 | `015:185` — `PERFORM id FROM core.user_account WHERE id = p_user_account_id FOR UPDATE;`. `grep "FOR UPDATE" db/migrations/` → exactly two hits: `015:108` (locks `commercial.subscription_licence`, unrelated trigger) and `015:185` | Implemented |
| A3 | "partitioned by `RANGE (applied_at)` into **annual and quarterly** partitions" | "into **annual** partitions — one per calendar year (`…_y2025`, `…_y2026`, `…_y2027`)" | A-01 | `019:339-350` — comment `-- Partitions by year`, then three one-year ranges. `grep "PARTITION OF" db/migrations/` → 3 rows | Implemented |
| A4 | "Queries filtering by recruitment cycle or year **prune 66% to 90% of index scans**" | "Queries filtering on `applied_at` prune partitions outside the requested range. *No benchmark query in `db/queries/` currently targets the partitioned table … and no pruning percentage is claimed.*" | A-02 | `grep "candidate_application_partitioned" db/queries/` → no matches. No pruning node exists in any captured plan | Measured (none taken) |
| A5 | "Older partitions can be detached … and archived to cold columnar storage (Parquet/S3) **with zero operational downtime**" | "**Rolling Retention Lifecycle (future)** … *No archival pipeline is implemented in this repository.*" | A-03 | `ALTER TABLE … DETACH PARTITION` appears nowhere in the repository; no S3 client, no export job | Proposed |
| A6 | "$\text{Wallet Balance} \equiv \sum \text{Credits} - \sum \text{Debits}$" (stated as an invariant) | Same equation + "the wallet balance … is a stored column … reconciliation is **checked** by `scripts/validate_data.py` and benchmark Query 05 rather than guaranteed by a constraint" | A-16 | `commercial.wallet.balance NUMERIC(14,2)` at `017:251`; `grep "ON commercial.wallet"` → only an index at `017:273`, no trigger; balance writes only at `generate_data.py:678` and `test_concurrency.py:287` | Tested (reconciliation check), not enforced |
| A7 | "refreshed concurrently on **scheduled cron intervals**" | "refreshed by the `analytics.refresh_reporting_marts()` procedure (`REFRESH MATERIALIZED VIEW CONCURRENTLY`). *No scheduler invokes it automatically, and the analytics fact tables are populated only by the synthetic data loader … `fact_gig_performance` and `fact_wallet_transaction` have no populating code at all.*" | A-04 | `019:308-315` defines the procedure; the only `CREATE EXTENSION` statements in the schema are `btree_gist` (`014:8`, `017:8`) — `pg_cron` is not installed; `generate_data.py:772` is the sole `fact_application_event` populator | Implemented procedure, no scheduler |
| A8 | "the following database engine parameters **are tuned**" | "the following PostgreSQL 17 engine parameters are **proposed**" + blockquote: not applied — no `postgresql.conf`, no init directory, no `command:` override in `docker-compose.yml`; the benchmark artifact was produced against stock defaults | A-17 | `docker-compose.yml` has one service, one volume (`talentra_pgdata`), no config mount; no `postgresql.conf`/`postgresql.auto.conf` anywhere | Proposed |
| A9 | "**100% of tables** use `BIGINT GENERATED ALWAYS AS IDENTITY` primary keys named `id`" | "All *operational* tables use … ; the four `analytics.dim_*` dimensions use surrogate `*_key` keys, and `recruitment.candidate_application_partitioned` uses the compound `(id, applied_at)` primary key" | A-06 | Non-`id` PKs: `019:21` (`date_key`), `019:64` (`candidate_key`), `019:88` (`organization_key`), `019:115` (`job_posting_key`), `019:336` (compound `(id, applied_at)`) | Implemented |
| A10 | "**Zero cross-schema foreign keys** bypass operational APIs" | "Cross-schema foreign keys are used deliberately for referential integrity (e.g. `recruitment.candidate_application` → `profile.candidate_profile`); schemas are logically separated by ownership, not by physical FK isolation" | A-09 | 24 `REFERENCES master.*` and 48 `REFERENCES core.*` across `db/migrations/`; the document's own §2 table already stated this | Implemented |
| A11 | "**Every date-time field** across all 10 schemas uses `TIMESTAMPTZ` normalized to UTC" | "No column uses a timezone-naive `TIMESTAMP`; all instant-valued timestamps are `TIMESTAMPTZ` normalized to UTC. Calendar-date fields … are `DATE` by design" | A-07 | Nine `DATE` columns (`010:102-103`, `014:140-141`, `014:272-273`, `005:90-91`, `005:147-148`, `019:11`). The underlying intent holds: the only `TIMESTAMP` regex hit is a comment string at `010:327` — zero naive `TIMESTAMP` columns | Implemented |
| A12 | `master` key tables: 8 listed | Added `industry`, `work_type` | A-15 | `master` has 10 tables; `master.work_type` is filtered by Q02, `master.industry` grouped by Q10 | Implemented |
| A13 | `commercial` key tables: 6 listed | Added `invoice`, `payment_order`, `payment_refund`, `candidate_profile_download_history` | A-13 | `commercial` has 10 tables; the download-history table is the subject of Q08 and of the threat-model repudiation row | Implemented |

**Not changed in this file**: the anti-sentinel invariant (§5.4) and the 95-table count were verified as correct and deliberately left intact.

### 2.2 `docs/threat-model.md`

| # | Old claim | New claim | Finding | Evidence | Class |
|:--|:--|:--|:--|:--|:--|
| T1 | "**Compliance Standards**: GDPR Article 25/32, SOC 2 Type II, PCI-DSS SAQ-A" | "**Target Compliance Framework** (alignment intent; no attestation performed): …" | T-24 | No audit report, control mapping, or gap analysis exists in the repository | External — not claimed |
| T2 | "baked directly into PostgreSQL 17 via **granular database roles**, … **declarative Row-Level Security (RLS)**, …" | "several controls are baked directly into PostgreSQL 17 via **append-only ledgers**, **cryptographic hashing standards**, and **anti-tampering triggers**. *Granular database roles (§3) and declarative Row-Level Security (§4) are **proposed designs that are not yet implemented**.*" | T-01, T-02 | `grep "ROW LEVEL SECURITY\|CREATE POLICY" db/ tests/` → no matches; `grep "CREATE ROLE\|GRANT \|REVOKE " db/` → no matches | Proposed |
| T3 | Diagram: "Encrypted Tax IDs", "Argon2id Passwords", "SHA-256 Checksums", RLS items presented as deployed | "Encrypted Tax IDs" removed; "Password Hashing (A)"; "SHA-256 Checksums"; RLS items marked `(P)`, with a legend: "(P) PROPOSED — not yet implemented in the database (see §3 and §4). (A) Algorithm is an application-layer default; the schema does not enforce it." | T-23, T-14 | `grep -rni "pgcrypto\|aes-256\|encrypt(\|decrypt(" db/` → no matches; `grep -rni "tax_id\|national_id" db/migrations/` → no matches; `algorithm VARCHAR(50) NOT NULL DEFAULT 'argon2id'` at `012:85` | Implemented / Proposed / External |
| T4 | Spoofing row: "Passwords hashed using Argon2id (`$argon2id$v=19$…`). Session tokens stored as SHA-256 hashes" | "Passwords are stored as salted hashes. `core.user_credential.algorithm` **defaults** to `argon2id` but the schema does not enforce the format, and hashing is performed by the application layer. Session tokens are stored as hashes in `core.user_session.session_token_hash` (length-constrained only)." | T-07 | `012:85` — a DEFAULT on a free-text column, no format CHECK; `core.user_account.password_hash` unconstrained `TEXT` with only `ck_user_account_password_hash` (length, `002:56-60`); `core.user_session.session_token_hash VARCHAR(255)` with only a length CHECK (`002:139,157-158`) | Implemented (storage) / not enforced (algorithm) |
| T5 | Spoofing row verification: `tests/test_identity.sql`, `tests/test_licences.sql` | Added `tests/test_concurrency.py` | T-21 | `test_concurrency.py:33` `test_concurrent_device_logins` asserts 2 granted sessions, N−2 rejections, and the matching `device.limit_exceeded` audit count | Tested |
| T6 | Tampering row: "Recruiter modifies **candidate assessment score** or alters credit ledger" | "Recruiter alters the credit ledger, the audit trail, or the download history" + "Candidate assessment scores are deliberately mutable and are not protected by these triggers" | T-11 | Only three append-only triggers exist (`017:374-377`, `012:290-293`, `017:443-446`); `profile.candidate_assessment_score` has none | Implemented |
| T7 | Tampering row: trigger `trg_prevent_audit_tampering` | `trg_prevent_audit_event_tampering` | T-03 | `012:290` — `CREATE TRIGGER trg_prevent_audit_event_tampering`; the *function* `audit.prevent_audit_tampering()` (`012:281`) is correctly named in the doc | Implemented |
| T8 | Repudiation row: "capturing … **IP address** … Cannot be altered **or truncated**" | "capturing downloader user ID, organization ID, wallet ledger ID, and timestamp. *IP address and user-agent are captured on `audit.audit_event`, which does not currently receive download events.* Cannot be altered or deleted by `UPDATE`/`DELETE`; `TRUNCATE` is not blocked by a trigger." | T-04, T-05 | `017:381-389` — the table has no `ip_address`/`user_agent` column. `012:240-241` has `client_ip VARCHAR(45)`, `user_agent VARCHAR(500)`. `grep "INSERT INTO audit.audit_event" db/` → 2 sites, both in `015` (`:221`, `:317`) — never a download event | Implemented |
| T9 | Information Disclosure row: "Candidate phone/email **masked** (`+91 98****3210`) … `core.user_block` **prevents** blocked entities from querying candidate profiles" | "Consent state is modelled in `core.consent_record`. `core.user_block` records block state, and `core.is_candidate_visible_to()` enforces it for callers of that function. *Phone/email masking for unauthorized viewers is not currently implemented at the database layer.*" | T-08, T-09 | `grep -rn "mask\|MASKING" db/ scripts/` → no matches. **Correction to the audit:** the audit's T-09 said `user_block` "records but does not enforce"; a tested enforcement function does exist — `core.is_candidate_visible_to()` at `012:336-388`, exercised by `tests/test_administration.sql:154-181` (visible before block → invisible after → visible to third parties). The row now states the real mechanism instead of the audit's stronger version | Tested (function-based) / not implemented (masking) |
| T10 | DoS row: "**B-Tree and GIN** indexes"; "High-volume tables partitioned by range (`candidate_application_partitioned`)" | "backed by optimized B-Tree indexes, with GiST indexes backing two exclusion constraints"; "High-velocity applications have a prepared range-partitioned table …; the operational application table is currently the unpartitioned `recruitment.candidate_application`" | T-06, T-12 | `grep "USING gin" db/ tests/ scripts/` → no matches. The only non-B-tree method is `gist`: `014:317` and `017:98` | Implemented |
| T11 | DoS row verification: "`scripts/run_benchmarks.py`, Query 04" | "`tests/test_concurrency.py`, `tests/test_licences.sql`" | T-22 | `run_benchmarks.py` measures latency, not the DoS invariant; Q04 returned zero rows in the 2026-10-17 run, so it verified nothing about session validation | Tested |
| T12 | DoS row: "concurrency limits locked atomically (`FOR UPDATE`)" | "(`FOR UPDATE` on the `core.user_account` row)" | A-05 | `015:185` | Implemented |
| T13 | Elevation row: "Database trigger `trg_enforce_consultant_policy_restrictions`" | "Database trigger `trg_enforce_consultant_openness` (on `sourcing.consultant_sourcing_request`)" + "Granular RBAC roles … are a **proposed** model — see §3" | T-10, T-02 | `016:130-133` — `CREATE TRIGGER trg_enforce_consultant_openness … ON sourcing.consultant_sourcing_request` | Implemented / Proposed |
| T14 | §3: "Talentra **enforces** separation of duties through distinct PostgreSQL database user roles" | "The following is a **proposed** role model, not a deployed one. No `CREATE ROLE` or `GRANT` statement exists in `db/migrations/` today. The running instance has a single role, `talentra_admin`, created by `POSTGRES_USER` in `docker-compose.yml`, and it holds SUPERUSER" | T-02 | `docker-compose.yml` sets `POSTGRES_USER: talentra_admin` (superuser); no role DDL in the schema | Proposed |
| T15 | §3 grant script: `GRANT SELECT, INSERT ON TABLE commercial.wallet_ledger, …` with no matching revoke | Added: `-- A GRANT does not narrow an earlier GRANT: reclaim the write access the blanket grant above conferred.` / `REVOKE UPDATE, DELETE ON TABLE commercial.wallet_ledger, commercial.candidate_profile_download_history FROM talentra_app;` | T-02(a) | The blanket `GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA … commercial` on the preceding line includes `commercial`; a later narrower `GRANT` cannot remove `UPDATE`/`DELETE` | Proposed-script defect fixed |
| T16 | §4 title: "Row-Level Security (RLS) & Multi-Tenant Isolation" | Title + "— PROPOSED DESIGN, NOT YET IMPLEMENTED", plus a lead paragraph stating no `ENABLE ROW LEVEL SECURITY`/`CREATE POLICY` exists, that isolation is currently enforced by application logic and explicit `NOT EXISTS` subqueries, and that the `app.current_*` session context is never set | T-01, T-25 | `grep "ROW LEVEL SECURITY\|CREATE POLICY" db/ tests/` → no matches; `grep "current_setting" db/ scripts/ tests/` → matches only inside this document | Proposed |
| T17 | §4.2 policy: `ub.blocker_user_account_id = profile.candidate_profile.user_account_id` | `ub.blocker_user_account_id = candidate_profile.user_account_id` | T-01(b) | The qualifying name `profile.candidate_profile.user_account_id` is invalid inside a policy on `profile.candidate_profile` — the table must be referenced by its relation name | Proposed-script defect fixed |
| T18 | §4.3: `sourcing.enforce_consultant_policy_restrictions()` with `v_open` / `COALESCE(..., FALSE)` | `sourcing.enforce_consultant_openness()` with `v_is_open` / `IS NOT TRUE`, plus a note that this trigger **is implemented** at `016:110-133` | T-01(c), T-10 | `016:110-126` — the real function body | Implemented (documented correctly) |
| T19 | §5: "Talentra classifies **every column across all 95 tables**" | "Talentra classifies columns into four sensitivity tiers … The data dictionary currently documents **13 of 95 tables** as a representative sample; full coverage is outstanding." | T-13 | `docs/data-dictionary.md` has 12 `###` subsections covering 13 tables | Implemented (partial) |
| T20 | §5 `[SENSITIVE]` row: "Salted Argon2id hash, **AES-256 CBC encryption**, E.164 normalization"; examples include "Tax: `XXXX-XX-4912`" | "Salted password hash (**algorithm not enforced by the schema**), SHA-256 document checksum, E.164 normalization"; the tax-ID example removed | T-14 | `grep -rni "pgcrypto\|aes-256\|encrypt(\|decrypt(" db/` → no matches; `grep -rni "tax_id\|national_id" db/migrations/` → no matches — there is no tax-ID column to encrypt | Implemented (real standard) |
| T21 | §6.1: "Every security-sensitive event (login, permission change, session revocation, profile unlock, device limit breach) is recorded in `audit.audit_event`" + an illustrative DDL with `event_type`, `severity`, `ip_address INET`, `metadata`, `created_at` | "Device-limit breaches (`…:221`) and session revocations (`:317`) are recorded … *Recording of logins, permission changes, profile unlocks and profile downloads is outstanding.*" + the **actual** column list | T-16, T-17 | `grep "INSERT INTO audit.audit_event" db/` → 2 sites only. Actual DDL at `012:230-242`: `actor_user_account_id`, `impersonator_user_account_id`, `action VARCHAR(80)`, `entity_schema`, `entity_name`, `entity_id`, `old_values_json`, `new_values_json`, `client_ip VARCHAR(45)`, `user_agent VARCHAR(500)`, `recorded_at` | Implemented |
| T22 | §6.2 trigger: `trg_prevent_audit_tampering` | `trg_prevent_audit_event_tampering` + a note that `TRUNCATE` is not blocked by the trigger | T-18, T-05 | `012:290`; `grep -rni "TRUNCATE" db/` → no `BEFORE TRUNCATE` statement trigger exists | Implemented |
| T23 | §7: "RPO **0 seconds** (Zero data loss) … via WAL streaming replication with synchronous commit"; "RTO **< 15 minutes** … Patroni / pg_auto_failover with PITR … continuous WAL archiving to S3"; an inline `pg_dump` runbook writing to `/backups/` | "RPO: one backup interval … logical backups via `pg_dump` with a scripted restore-and-verify procedure (`scripts/backup_restore.sh`) … *Synchronous streaming replication and PITR are production deployment requirements; no replica, `archive_mode`, or WAL-archiving job is configured in this repository.*"; RTO tied to the script's 900-second threshold; the inline snippet replaced by a pointer to the script (with a note that it creates and drops `talentra_recovery_test`) | T-19, T-20 | `grep -rni "patroni\|pg_auto_failover\|archive_command\|synchronous_standby\|archive_mode" .` → only that sentence. `docker-compose.yml` has one service and one volume — no replica. `scripts/backup_restore.sh`: `pg_dump -Fc` → `CREATE DATABASE talentra_recovery_test` → `pg_restore` → row-count parity check → `DROP DATABASE`; `MAX_RTO_SECONDS=900` | Implemented (logical backup) |
| T24 | *(new section)* | **§8 Scope and Limitations** — a 10-row table classifying each control as Implemented / Proposed / Not implemented / Not claimed, plus notes on the anti-tamper controls' limits (`TRUNCATE`, privileged actions) and the STRIDE coverage gap | T-24, T-05, T-29, P3-2 | Composed from the evidence cited in T1–T23 | Mixed — explicitly labelled per row |

**Not changed**: the Application-Level Permissions Matrix (§3) — it describes application-layer behaviour, not a database object, and no repository artifact contradicts it. The `messaging.get_ui_translation` three-tier fallback and the `btree_gist` exclusion-constraint claim were verified correct and left intact.

### 2.3 `docs/competitive-benchmark.md`

| # | Old claim | New claim | Finding | Evidence | Class |
|:--|:--|:--|:--|:--|:--|
| C1 | "Immutability triggers physically prevent modification or deletion, **satisfying strict SOC 2 Type II** and financial audit compliance" | "…physically reject modification of recorded entries, and corrections use self-referencing debit/credit rows rather than overwriting history. *These controls support a financial-audit evidence trail; they do not by themselves constitute a compliance attestation.*" | C-01 | No attestation, control mapping, or gap analysis in the repository. The triggers also do not block `TRUNCATE` | Implemented (triggers) / External (not claimed) |
| C2 | "declarative **quarterly and annual** range partitioning" | "declarative **annual** range partitioning … (one partition per calendar year)" | C-02 | `019:339-350` | Implemented |
| C3 | "prune closed historical partitions entirely, keeping the active index working set **100% resident** in PostgreSQL buffer cache memory" | "Queries filtering on `applied_at` prune closed historical partitions. *No benchmark query currently targets the partitioned table, and the seeded rows populate a single partition. The 100% buffer-cache figure in the benchmark artifact is a hit ratio over a warm development dataset, not a statement about residency at production scale.*" | C-03 | `grep "candidate_application_partitioned" db/queries/` → no matches. `generate_data.py:469-474` copies 50,000 rows with `applied_at` defaulting to `CURRENT_TIMESTAMP` → all in `y2026`. The artifact's `buffer_hit_ratio_pct: 100.0` is a hit ratio | Measured (2026-10-17) / qualified |
| C4 | "**prunes 75%+ of index scans**, with zero operational downtime" | "`RANGE (applied_at)` with annual intervals, applied to the prepared scale-out application table" | C-04 | No measurement exists. Three documents gave three different figures for one unmeasured quantity (75%+, 66–90%, >75%) | Measured (none taken) |
| C5 | "Pessimistic `FOR UPDATE` lock on **licence seat**" | "Pessimistic `FOR UPDATE` lock on the user account row" | A-05 | `015:185` | Implemented |
| C6 | "**Even under thousands of concurrent booking attempts**, PostgreSQL physically rejects conflicting temporal ranges at the **write-ahead log (WAL) boundary**" | "PostgreSQL rejects conflicting temporal ranges at statement-execution time via the constraint's GiST index, raising `ExclusionViolation` (SQLSTATE 23P01) before commit. *Verified by `tests/test_concurrency.py` under 5-thread contention; no load test at higher concurrency has been run.*" | C-06 | `014:316-321` (constraint), `014:8` (`btree_gist`); `test_concurrency.py:151` `num_threads = 5`, `:207` catches `psycopg2.errors.ExclusionViolation` | Tested (5 threads) |
| C7 | "enabling unified enterprise discovery queries across both talent pools **in under 35 milliseconds**" | "…enabling unified enterprise discovery queries across both talent pools. *No benchmark query spans both pools, so no latency figure is claimed for unified cross-pool discovery.*" | C-05 | No query joins `profile.candidate_profile` with `gig.gig_worker_profile`; Q01 (30.87 ms) and Q07 (11.07 ms) are separate queries over separate tables | Measured (none applicable) |
| C8 | *(new footnote under the §1 matrix)* | "The Naukri / Monster and LinkedIn columns are architectural characterisations of known anti-patterns, not independently verified claims about those companies' current internals; no evidence for them exists in this repository. The Talentra column is verifiable against `db/migrations/`." | C-11 | The third-party characterisations cannot be verified from this repository under any circumstance | External — disclosed, not claimed |

**Not changed**: the `btree_gist` exclusion-constraint row, the `core.user_block` XOR-enforcement row, the `messaging.get_ui_translation` row, the GiST/`btree_gist` explanatory sentence, and the illustrative "legacy" `UPDATE company_wallet` SQL block — all verified as accurate.

### 2.4 `docs/rule-compliance.md`

This file is outside the three Phase 2C audit targets, but the audit surfaced **four non-existent object names** in it during Step 3 cross-document reconciliation (R-01…R-04), and the file is the direct source of the "Enforcing Mechanism" column that the threat model cites. Correcting the names was necessary to keep the corrected documents internally consistent; no other part of the file was touched.

| # | Old claim | New claim | Finding | Evidence |
|:--|:--|:--|:--|:--|
| R1 | `ck_user_account_phone_e164` | `ck_user_account_phone_format` | R-02 | `002:31` — `CONSTRAINT ck_user_account_phone_format`, regex `^\+[1-9][0-9]{1,14}$` |
| R2 | `ck_job_posting_currency` | `ck_job_posting_salary_currency` (+ the real combined CHECK body) | R-02 | `008:113-134` |
| R3 | `ck_user_account_password_hash_format` presented as a DDL CHECK | The real DDL constraint `ck_user_account_password_hash` (length only) **plus** the runtime validator query that actually checks the Argon2id/bcrypt header, with its file:line | R-01 | `002:56-60`; `scripts/validate_data.py:210-215` — `SELECT COUNT(*) FROM core.user_account WHERE password_hash IS NOT NULL AND password_hash !~ '^\$(argon2id\|2b\|2a)\$';` |
| R4 | `trg_prevent_audit_tampering` | `trg_prevent_audit_event_tampering` | R-03 | `012:290` |
| R5 | "Pessimistically locks `commercial.licence_seat_allocation` with `FOR UPDATE`" | "Pessimistically locks the `core.user_account` row with `FOR UPDATE` to serialize concurrent login attempts. The licence seat allocation is read to derive the device entitlement." | R-04 | `015:185` |
| R6 | Header: "**Overall Status**: **100% COMPLIANT (15/15 Passed, 0 Failures, 0 Warnings)**" | Same figure, restated as a blockquote: a historical observation of the last validator run on the seeded dataset, not a static property; `scripts/run_all_tests.py` does not invoke `scripts/validate_data.py` | R-06 | `scripts/run_all_tests.py` runs `tests/*.sql` plus two Python suites — it never calls `validate_data.py` |
| R7 | "Across all enterprise client wallets, zero reconciliation discrepancies were detected." | Same sentence + a note that this is an observation of the last validator run, and that `commercial.wallet.balance` is a stored column no trigger derives from the ledger | R-07, A-16 | `017:251`; no trigger on `commercial.wallet` |
| R8 | "PII Classification: **All columns** cataloged in `docs/data-dictionary.md`" | "…*The dictionary currently documents 13 of 95 tables; full coverage is outstanding.*" | T-13, P3-3 | `docs/data-dictionary.md` covers 13 tables |

**Not changed**: the RG1/RG2/RG4/RG5/RG8/RG10 rows and their evidence blocks — all verified correct. The "Postularse para este puesto" and "Apply Now" outputs in RG8 were left as-is (they are seeded-data values, not schema claims), and are noted in §5 below as an item requiring a live-database check that was blocked.

---

## 3. Corrections Deliberately Deferred

These are recorded as pending rather than changed, because doing otherwise would require an owner decision or a check the environment blocked.

| # | Item | Why deferred | Proposed alternatives |
|:--|:--|:--|:--|
| D1 | **Implement** RLS and the least-privilege role model | Explicitly out of scope: "Do not implement RLS, roles, replication, PITR, or other new infrastructure." §3 and §4 were reframed as proposals instead | (a) schedule an implementation phase that also fixes the session-context and correlation defects; (b) leave as proposals |
| D2 | **`docs/data-dictionary.md`** — header "95 Operational, Dimensional, and Partitioned Tables", "Every column in Talentra is tagged", "encrypted tax IDs" | Outside the four files this phase edited; changing it ripples into `README.md:13` and `threat-model.md`. The audit listed it as P3-3 under a separate owner decision (O-5/O-6) | (a) correct the three claims in a follow-up pass; (b) defer to the data-dictionary refresh |
| D3 | **`docs/integration-boundaries.md:46`** — "PCI-DSS zero-storage compliance" | Outside the four files this phase edited. *Note the architectural premise is verifiable and true* — no PAN/CVV/card-number column exists in any migration — so the fix is a framing change, not a technical one | (a) restate as "no cardholder data is stored; SAQ-A eligibility is asserted by the payment provider"; (b) defer |
| D4 | **`README.md:187`** — pointer to the non-existent `docs/phase2c-benchmark-correction-report.md` §4 | `README.md` was a pre-existing user edit from an earlier phase; the audit's O-8 decision offers three options | (a) create that report; (b) retarget the pointer to `docs/phase2c-documentation-audit.md`; (c) remove the pointer |
| D5 | **`docs/performance-report.md:32`** — "all relational indexes fit completely within PostgreSQL `shared_buffers` (4 GB)" | Pre-existing user edit. The figure reflects a *proposed* tuning profile, not the stock-defaults environment the benchmark actually ran on. Changing it would modify a user-owned edit outside this phase's scope | (a) qualify it as the proposed configuration; (b) defer to a performance-report refresh |
| D6 | **`docs/performance-report.md` §1** — add "Measured on 2026-10-17 (methodology v1) … stock PostgreSQL 17 defaults" (audit P3-5) | Same reason as D5 | (a) add in a follow-up that owns performance-report changes |
| D7 | **`README.md:53` and `README.md:194`** — "acquiring a row-level lock (`FOR UPDATE`) on the user's licence seat" and "sub-2ms ACID transaction guarantees" | Pre-existing user edits; the same two claims corrected in the other four files, so the corpus is now inconsistent across `README.md` and the docs. Left alone deliberately to avoid overwriting user edits | (a) correct in a follow-up that owns README changes; (b) correct now with owner approval |
| D8 | **Compliance framing choice** (audit O-3) | The audit listed three options: relabel to "Target Compliance Framework", remove the frameworks entirely, or supply external evidence and keep the current wording. Phase 2D applied the **first** option — the one that removes an unsupported attestation while preserving the information — because it is the minimal change that makes the claim defensible. The choice between all three remains the owner's | (a) keep the relabel; (b) remove the frameworks; (c) supply external evidence |
| D9 | **Third-party (Naukri / Monster / LinkedIn) claims** (audit O-4) | The audit flagged that these are unverifiable from the repository and noted the "legacy failure" framing is "risky externally" — an audience decision. Phase 2D applied the **disclosure** option (a footnote stating they are characterisations, not verified claims) and left the substance and the framing untouched | (a) keep the footnote; (b) add citations; (c) restrict distribution |
| D10 | **STRIDE coverage gap** — `master`/`analytics` read-path threats, audit exfiltration, GiST availability threats, supply chain | The audit marked this "owner approval required on scope" (T-29). The gap is now *disclosed* in §8 rather than silently left | (a) extend the dossier in a later phase; (b) leave the disclosure |
| D11 | **RG8 quoted function outputs** — `'Postularse para este puesto'`, `'Apply Now'` | These depend on the seeded `messaging.ui_translation` content and could not be verified against the live table (see §4) | (a) verify against a live DB and label as expected values; (b) leave |
| D12 | **`docs/architecture.md:5`** table-count label — "95 Operational, Dimensional, and Partitioned Tables" (audit P3-4) | Marked "optional, cosmetic" in the audit, and changing the label ripples into `README.md:13`, `data-dictionary.md:4`, and `threat-model.md:164`. The **number 95 is correct** and the audit did not ask for it to change | (a) leave the number, adjust the label only where audited; (b) adopt the precise label everywhere |

---

## 4. Validation Commands Actually Executed

| Command | Result |
|:--|:--|
| `git status --short` | Ran. Confirmed the modified/untracked set; nothing staged, committed, or pushed |
| `git diff --stat` | Ran. 4 doc files changed by this phase: architecture 27, competitive-benchmark 14, rule-compliance 47, threat-model 117 |
| `git diff -- docs/architecture.md docs/competitive-benchmark.md` | Ran and reviewed in full |
| `git diff -- docs/threat-model.md` | Ran and reviewed in full |
| `git diff -- docs/rule-compliance.md` | Ran and reviewed in full |
| `git diff --check` | Ran. Initially flagged trailing whitespace on two header lines; fixed by moving the header hard-break onto the preceding lines. **Final result: CLEAN (no warnings)** |
| `grep` for the 4 non-existent object names across all 4 edited files | Ran. Only remaining hit is `licence_seat_allocation` in `architecture.md:56`, which is a **correct table name in a table list**, not the wrong lock target. All four wrong names removed |
| `grep` for residual incorrect claims (quarterly, 75%+, 66–90%, AES-256, tax ID, GIN, WAL boundary, 0 seconds, 100% resident, under 35 ms, thousands of concurrent, RPO 0) | Ran across the 3 Phase 2C target files. All cleared except the deliberately-qualified mentions inside the new caveat sentences |
| `grep` for markdown links in the 4 edited files | Ran. **No markdown links** exist in these files, so there are no link targets to break |
| `ls` on every file path referenced by the new text | Ran. All 11 referenced paths exist |
| `sed`/`grep` verification of every schema object named in the corrections | Ran for: `audit.audit_event` DDL, `sourcing.enforce_consultant_openness`, `015:185` FOR UPDATE, `core.user_credential`, `core.user_session`, `core.user_block` + `core.is_candidate_visible_to`, `commercial.wallet`, `commercial.candidate_profile_download_history`, `audit` insert sites, GIN/GiST index methods, `ck_user_account_email_format` / `ck_user_account_phone_format` / `ck_job_posting_salary_currency` / `ck_user_account_password_hash`, `scripts/validate_data.py` RG6 query, `docker-compose.yml`, `scripts/backup_restore.sh`, `tests/test_concurrency.py` thread counts, `db/queries/12` (does not call `get_ui_translation`) |
| ASCII diagram column alignment in `threat-model.md` §1 | Reviewed by reading the rendered block; columns aligned after a padding correction |

### Checks blocked by the environment — NOT executed, NOT claimed as passing

| Check | Status | Reason |
|:--|:--|:--|
| `python3 tests/test_benchmark_harness.py` | **UNVERIFIED — blocked** | The host command-safety classifier rejected every invocation across this and the previous phase: *"talentra-minimax-free is temporarily unavailable, so auto mode cannot determine the safety of Bash right now."* Retried repeatedly. **This suite has never executed.** No claim is made about its result |
| `python3 -m py_compile scripts/run_benchmarks.py scripts/run_all_tests.py` | **UNVERIFIED — blocked** | Same classifier. The Phase 2C script edits remain syntax-unchecked |
| `python3 scripts/run_all_tests.py` (the SQL + concurrency + harness runner) | **NOT RUN** | Requires the live database and would execute against it. Out of scope for a documentation-only phase |
| Live `pg_settings` read (to confirm stock PostgreSQL 17 defaults empirically) | **UNVERIFIED — blocked** | Live-DB access was unavailable. The "tuning is not applied" conclusion rests on the *static absence* of any `postgresql.conf`, init directory, `command:` override, or config mount — which is verifiable without a database and is sufficient for the claim made |
| Live `psql` query against `messaging.ui_translation` to confirm the RG8 Spanish/English outputs | **UNVERIFIED — blocked** | Same live-DB unavailability. The outputs were left unchanged (deferred item D11) rather than asserted as verified |
| Live constraint/catalog introspection to confirm the renamed objects | **NOT REQUIRED** | Every corrected object name was confirmed against the migration DDL by direct file read (`grep`/`sed`), which is the authoritative source — stronger than a live catalog read for this purpose |

**No test suite, syntax check, or benchmark was executed in Phase 2D. No database was contacted. No claim of a passing test appears in this report or in any edited document.**

---

## 5. Existing User Changes Preserved

| Path | Status | Disposition |
|:--|:--|:--|
| `README.md` | Modified (40 lines changed) | **Untouched by Phase 2D.** Preserved exactly as found. Its two remaining incorrect claims are logged as deferred items D4 and D7 rather than edited |
| `docs/performance-report.md` | Modified (55 lines changed) | **Untouched by Phase 2D.** Preserved exactly as found. Logged as D5, D6 |
| `scripts/run_benchmarks.py` | Modified (949 lines) | **Untouched by Phase 2D.** Preserved |
| `scripts/run_all_tests.py` | Modified (24 lines) | **Untouched by Phase 2D.** Preserved |
| `tests/test_constraints.sql` | Modified (43 lines) — **user-owned, origin not established** | **Untouched.** Not reverted, not staged, not discarded |
| `.git-initial-backup/` | Untracked | **Untouched.** Not read destructively, not modified, not deleted |
| `docs/phase2b-query-performance-validation.md` | Untracked | Preserved |
| `docs/phase2c-documentation-audit.md` | Untracked | Preserved (read as the source of truth) |
| `tests/test_benchmark_harness.py` | Untracked | Preserved |
| `benchmarks/results/benchmark_results.json`, `benchmark_summary.md` | Clean | **Untouched** — the historical methodology-v1 artifacts remain unmodified |

**No database, container, volume, or schema state was touched.** No `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`, `DROP`, `RESET`, or rebuild. No `EXPLAIN ANALYZE`. No benchmark run. No data generation. No commit, push, reset, or discard.

---

## 6. Corrections to the Phase 2C Audit Itself

Two items in the audit proved inaccurate on re-verification against the source, and are recorded here so the audit is not treated as infallible:

| Audit item | Audit said | Actual | Phase 2D handling |
|:--|:--|:--|:--|
| **T-09** | "`core.user_block` **records** the block; it does **not enforce** anything. With no RLS policy and no view or trigger, a query that omits the `NOT EXISTS` clause returns blocked candidates without obstruction." | A tested enforcement function **does** exist: `core.is_candidate_visible_to()` (`012:336-388`), which returns `FALSE` for a blocked viewer and is exercised by `tests/test_administration.sql:154-181`. Enforcement is still not automatic for arbitrary queries, but the audit's blanket "does not enforce" was too strong | The threat-model row now states the real mechanism: "`core.user_block` records block state, and `core.is_candidate_visible_to()` enforces it for callers of that function" — weaker than the audit's claim, stronger than the original document's |
| **A-13/A-15** (and P2-5) | `commercial` omits four tables; `master` omits two | Confirmed correct. `commercial` has 10 tables (6 listed + 4 added); `master` has 10 tables (8 listed + `industry` and `work_type` added) | Applied as written. Both lists are now complete against the migrations: `grep` over `db/migrations/` yields exactly 10 `master.*` and 10 `commercial.*` `CREATE TABLE` statements, and the architecture.md §2 rows now name all 10 of each. No table is listed twice and no table is missing |

**Finding-count consistency check.** The audit's §1.5 summary table (69 findings: 17 verified / 28 contradicted / 22 unsupported / 2 needs-external-evidence) was re-tallied against the finding series (A-01…A-17 = 17, C-01…C-13 = 13, T-01…T-29 = 29, R-01…R-10 = 10; total 69). The series counts match the summary table exactly. The *per-file classification split* inside the summary table is an approximate roll-up: several findings carry compound classifications (e.g. A-16 is "VERIFIED for the trigger; UNSUPPORTED for the invariant", C-03 is "UNSUPPORTED + CONTRADICTED", T-18 is "VERIFIED (function body) / name mismatch"), so a strict one-to-one sum is not derivable. The totals and the per-file finding *series* counts are reliable; the per-classification cells are indicative. No correction to the audit file was made in Phase 2D, since the audit is a delivered Phase 2C artifact and editing it was not in scope.

---

## 7. Remaining Documentation Risks

1. **`README.md` still carries two of the corrected claims** (D7): "acquiring a row-level lock (`FOR UPDATE`) on the user's licence seat" at line 53 and "sub-2ms ACID transaction guarantees" at line 194. The same claims are now corrected in four other documents, so the corpus is internally inconsistent until `README.md` is brought in line.
2. **`docs/performance-report.md:32`** still states indexes "fit completely within PostgreSQL `shared_buffers` (4 GB)" — a figure from the *proposed* tuning profile, not the stock-defaults environment the benchmark ran on (D5).
3. **`docs/data-dictionary.md`** still claims "95 Operational, Dimensional, and Partitioned Tables" and "Every column in Talentra is tagged", and still lists "encrypted tax IDs" as a `[SENSITIVE]` example (D2) — the same finding family as T-13/T-14, corrected in `threat-model.md` but not here.
4. **`docs/integration-boundaries.md:46`** still asserts "PCI-DSS zero-storage compliance" (D3).
5. **The `docs/phase2c-benchmark-correction-report.md` pointer in `README.md:187`** remains dangling (D4).
6. **No live-database verification of any corrected claim.** Every correction was verified against the migration DDL and test files, which are the authoritative sources, but no claim was confirmed against a running instance.
7. **The `tests/test_benchmark_harness.py` suite has never executed** (classifier-blocked since Phase 2C). The Phase 2C script changes to `run_benchmarks.py` remain unverified by execution, and `run_all_tests.py` now references that suite.

---

## 8. Phase 2D Completion Statement

Phase 2D applied **documentation-only** corrections to four files, resolving the clearly-justified items from the Phase 2C audit's Priority 0/1/2 lists and the four non-existent object names the audit surfaced in `rule-compliance.md`. Twelve items were deliberately deferred with reasons recorded, and two corrections to the audit's own findings are documented in §6.

**Not done, by design**: no RLS, role, replication, PITR, schema, index, constraint, migration, application-code, or test implementation. No database state was read or written beyond static file inspection. Nothing was committed, pushed, reset, or discarded. `.git-initial-backup/`, `tests/test_constraints.sql`, `README.md`, and `docs/performance-report.md` were left exactly as found.
