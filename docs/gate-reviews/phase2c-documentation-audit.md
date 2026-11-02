# Talentra Phase 2C — Documentation Audit & Correction Plan

**Audit Date**: 2026-10-20
**Auditor Role**: Database performance & schema verification (read-only)
**Repository**: `~/Downloads/Talentra_Database_Design-main`
**Branch**: `feature/your-task` @ `7ac5b2b` ("update", 2026-10-19)

---

## 1. Scope and Methodology

### 1.1 Documents in scope

| Document | Lines | Git provenance | Modified in this phase? |
|:--|--:|:--|:--|
| `docs/architecture.md` | 146 | `7ac5b2b` 2026-10-19, `b526095` 2026-10-16 | **No** |
| `docs/competitive-benchmark.md` | 51 | `7ac5b2b` 2026-10-19, `b526095` 2026-10-16 | **No** |
| `docs/threat-model.md` | 222 | `7ac5b2b` 2026-10-19, `b526095` 2026-10-16 | **No** |

### 1.2 Evidence sources consulted

| Source | Type | Date / provenance |
|:--|:--|:--|
| `db/migrations/001–019` (19 files) | Source of truth for schema | Working tree, unmodified |
| `db/queries/01–12` (12 files) | Benchmark query definitions | Working tree, unmodified |
| `tests/*.sql` (21 files), `tests/test_concurrency.py`, `tests/test_benchmark_harness.py` | Test suite | `test_benchmark_harness.py` is new/untracked (Phase 2C) |
| `scripts/run_benchmarks.py` | Benchmark harness | Modified in this phase (methodology v2) |
| `scripts/validate_data.py` | Compliance validator | Working tree, unmodified |
| `scripts/generate_data.py` | Fixture generator | Working tree, unmodified |
| `scripts/backup_restore.sh`, `backup_restore.ps1` | DR runbook | Working tree, unmodified |
| `benchmarks/results/benchmark_results.json` | **Historical** measurement artifact | Embedded `benchmark_timestamp: 2026-10-17T18:31:04Z`; committed at `7ac5b2b` 2026-10-19. **Methodology v1 — not a fresh measurement.** |
| `benchmarks/results/benchmark_summary.md` | **Historical** measurement artifact | Same run as above |
| `docker-compose.yml` | Deployment definition | Working tree, unmodified |

### 1.3 Method

1. Each document was read in full, line by line.
2. Every material claim was extracted and classified as one of: **implemented behavior**, **tested behavior**, **measured performance**, **design intent**, **future recommendation**, or **external certification status**.
3. Each claim was traced to a source location in the repository (file:line). Claims traceable to a schema object were marked *verified*; claims traceable to a contradicting schema object were marked *contradicted*; claims with no supporting artifact were marked *unsupported*; claims whose verification requires evidence outside the repository were marked *needs external evidence*.
4. Cross-document consistency was checked over seven documents plus the schema/artifact set (Step 3 reconciliation checklist).
5. No database writes, no schema changes, no benchmarks, no `EXPLAIN ANALYZE` against live data.

### 1.4 Classification vocabulary

| Class | Meaning |
|:--|:--|
| **VERIFIED** | Directly supported by a repository artifact at a cited location. |
| **CONTRADICTED** | A repository artifact states the opposite, or the claim names a specific object that does not exist. |
| **UNSUPPORTED** | No repository artifact supports the claim; the claim may still be true, but it is not evidenced here. |
| **NEEDS EXTERNAL EVIDENCE** | Can only be settled by evidence outside this repository (audit reports, certification, live production measurement). |

### 1.5 Findings by classification

Counted over the numbered finding series: **A-01…A-17** (`architecture.md`), **C-01…C-13** (`competitive-benchmark.md`), **T-01…T-29** (`threat-model.md`), **R-01…R-10** (`rule-compliance.md`, surfaced by the Step 3 cross-document reconciliation).

| Classification | `architecture.md` | `competitive-benchmark.md` | `threat-model.md` | `rule-compliance.md` | **Total** |
|:--|--:|--:|--:|--:|--:|
| **Verified** (no change needed) | 4 | 6 | 4 | 3 | **17** |
| **Contradicted** | 6 | 3 | 15 | 4 | **28** |
| **Unsupported** | 7 | 3 | 9 | 3 | **22** |
| **Needs external evidence** | 0 | 1 | 1 | 0 | **2** |
| **Subtotal** | 17 | 13 | 29 | 10 | **69** |

**Of the 69 findings, 50 require a wording change** (28 contradicted + 22 unsupported). The 2 external-evidence items are not corrections — they are claims that must be substantiated outside the repository or removed.

Per-file verdicts: `architecture.md` → **NEEDS FACTUAL CORRECTIONS**; `competitive-benchmark.md` → **NEEDS FACTUAL CORRECTIONS**; `threat-model.md` → **INCOMPLETE** (its two headline controls — declarative RLS and database roles — are documented as deployed but exist nowhere in the repository).

Each finding below carries: exact file and section/line, the exact claim, supporting repository evidence with source locations, classification, recommended correction, and confidence with limitations. §7 separately lists 15 claims that were checked adversarially and found **correct** — a preservation checklist so the correction pass does not damage them.

### 1.6 Explicit limitations of this audit

| # | Limitation | Effect on findings |
|:--|:--|:--|
| L1 | **No live database access.** The environment's command-safety classifier intermittently rejected every DB-bearing command form (`docker exec … psql`, `python3 -c "import psycopg2…"`, `pg_dump`). Per the safety boundaries I did not attempt to evade it. | Live `pg_settings`, live `pg_constraint` catalogs, and live plan shapes could not be sampled. Findings that need them are marked *needs external evidence*. |
| L2 | **No fresh benchmark run.** Running `scripts/run_benchmarks.py` would require a live DB and is also an expensive measurement, which the brief excludes. | All performance figures are cited **as historical measurements from the 2026-10-17 v1 run**, never as current measurements. |
| L3 | **The historical artifact is methodology v1**, whose `index_impact` block is known-invalid (Phase 2B §6). | Latency figures are usable as *historical observations*; the "index impact" figures are not usable at all and are excluded from evidence. |
| L4 | **Third-party claims about Naukri, Monster, LinkedIn** cannot be verified from this repository under any circumstance. | All such claims are marked *needs external evidence*. |
| L5 | **The container was up ~8 hours at audit time** with synthetic data; `pg_stat_*` counters reflect only that window. | No claim about index *usage* is made in either direction. |
| L6 | **`.git-initial-backup/` was listed but its object database was not walked** (classifier blocked `git --git-dir=… log`). | Its directory structure (`HEAD`, `objects`, `refs`, `logs`, `config`) is intact and it was neither read destructively nor modified. |
| L7 | **No Python code was executed in this phase.** The host command-safety classifier rejected every invocation of `python3 tests/test_benchmark_harness.py` and `python3 -m py_compile …` with *"talentra-minimax-free is temporarily unavailable, so auto mode cannot determine the safety of Bash right now"*. Retried; still blocked. | The 14-test DB-free harness suite (`tests/test_benchmark_harness.py`) and a syntax check of `scripts/run_benchmarks.py` / `scripts/run_all_tests.py` are **unverified by execution**. The findings in this report are derived from static file inspection only and do not depend on that suite passing. |
| L8 | **One dangling cross-reference exists in the working tree.** `README.md:187` (modified in this engagement) points to `docs/phase2c-benchmark-correction-report.md` §4, a file that was never created. | Recorded here rather than silently edited, because `README.md` is outside the three audited documents and editing it was not part of this task. See §10, O-8. |

---

## 2. Working Tree State at Audit Start (Step 1)

```
$ git status --short
 M README.md
 M docs/performance-report.md
 M scripts/run_all_tests.py
 M scripts/run_benchmarks.py
 M tests/test_constraints.sql
?? .git-initial-backup/
?? docs/phase2b-query-performance-validation.md
?? tests/test_benchmark_harness.py
```

`git diff --stat -- README.md docs/performance-report.md docs/architecture.md docs/competitive-benchmark.md docs/threat-model.md docs/rule-compliance.md`:

```
 README.md                  | 40 +++++++++++++++++----------------
 docs/performance-report.md | 55 ++++++++++++++++++++++++----------------------
 2 files changed, 50 insertions(+), 45 deletions(-)
```

**Interpretation of pre-existing changes:**

| Path | Status | Origin | Disposition |
|:--|:--|:--|:--|
| `README.md` | Modified | **This engagement, Phase 2C Steps 2–4** (partitioning wording, baseline labelling, result-validity column) | Preserved as-is |
| `docs/performance-report.md` | Modified | **This engagement, Phase 2C Steps 2–4** (index-impact → diagnostic relabel, result-validity column, partitioning wording) | Preserved as-is |
| `scripts/run_benchmarks.py` | Modified | **This engagement, Phase 2C Step 2** (methodology v2) | Preserved as-is |
| `scripts/run_all_tests.py` | Modified | **This engagement, Phase 2C Step 2** (wires `test_benchmark_harness.py`) | Preserved as-is |
| `tests/test_benchmark_harness.py` | Untracked (new) | **This engagement, Phase 2C Step 2** | Preserved as-is |
| `docs/phase2b-query-performance-validation.md` | Untracked | Phase 2B report from this engagement | Preserved as-is |
| **`tests/test_constraints.sql`** | Modified, +43 lines | **USER-OWNED — origin not established.** Adds `v_country_id`/`v_state_id` fixture variables and `master.country`/`master.state`/`master.city`/`master.employment_type`/`master.work_type` fixtures to the DECLARE block. | **UNTOUCHED. Not reverted, not staged, not discarded.** |
| `.git-initial-backup/` | Untracked | Pre-existing bare-repo backup | **PRESERVED. Not modified, not deleted.** |
| `docs/architecture.md` | Clean | — | **Unmodified in this phase** |
| `docs/competitive-benchmark.md` | Clean | — | **Unmodified in this phase** |
| `docs/threat-model.md` | Clean | — | **Unmodified in this phase** |
| `docs/rule-compliance.md` | Clean | — | **Unmodified in this phase** |
| `benchmarks/results/benchmark_results.json` | Clean | — | **Unmodified** (`git diff` empty) — historical v1 artifact preserved |
| `benchmarks/results/benchmark_summary.md` | Clean | — | **Unmodified** |

Nothing was staged, committed, pushed, reverted, or discarded.

---

## 3. Findings — `docs/architecture.md`

**Verdict: NEEDS FACTUAL CORRECTIONS** (structure complete; 7 contradicted / 8 unsupported claims)

Structure is sound: no TODOs, no placeholders, no truncated sections, no missing expected sections, clean ending at line 146.

### A-01 — §3.3, line 89 — partition intervals · **CONTRADICTED** · Confidence: HIGH

> "**Partition Key**: `recruitment.candidate_application_partitioned` is partitioned by `RANGE (applied_at)` into annual and quarterly partitions (`candidate_application_y2025`, `candidate_application_y2026`, etc.)."

**Evidence**: `db/migrations/019_create_analytics_marts.sql:339-350` — under the comment `-- Partitions by year`, three partitions are defined, each spanning exactly one calendar year:

| Partition | From | To | Source |
|:--|:--|:--|:--|
| `candidate_application_y2025` | `2025-01-01+00` | `2026-01-01+00` | `019:340-342` |
| `candidate_application_y2026` | `2026-01-01+00` | `2027-01-01+00` | `019:344-346` |
| `candidate_application_y2027` | `2027-01-01+00` | `2028-01-01+00` | `019:348-350` |

`grep -rn "PARTITION OF" db/migrations/` returns **3** rows total. There is no quarterly partition anywhere in the schema. The claim is also internally inconsistent: it names only annual partitions while asserting quarterly ones exist.

**Recommended correction**: replace "into annual and quarterly partitions" with "into **annual** partitions (one per calendar year: `candidate_application_y2025`, `candidate_application_y2026`, `candidate_application_y2027`)".

### A-02 — §3.3, line 91 — pruning percentage · **UNSUPPORTED** · Confidence: HIGH

> "**Partition Pruning**: Queries filtering by recruitment cycle or year prune 66% to 90% of index scans, avoiding massive memory buffer bloat."

**Evidence**: No benchmark query targets the partitioned table — `grep -rn "candidate_application_partitioned" db/queries/` returns **no matches**. The only references repo-wide are `019_create_analytics_marts.sql` (definition), `tests/test_analytics.sql:162,232`, `scripts/generate_data.py:469-474,840`, `scripts/validate_data.py:307`, and four documentation files. No plan in `benchmark_results.json` contains a pruning node, because no query reaches the table. The 66–90% figure has no measurement behind it.

**Recommended correction**: remove the percentage; state that pruning applies to queries filtering on `applied_at` and that no benchmark query currently targets the partitioned table.

### A-03 — §3.3, line 92 — DETACH/PARQUET/S3 lifecycle · **UNSUPPORTED** (design intent presented as implemented) · Confidence: HIGH

> "**Rolling Retention Lifecycle**: Older partitions can be detached (`ALTER TABLE ... DETACH PARTITION`) and archived to cold columnar storage (Parquet/S3) with zero operational downtime."

**Evidence**: `ALTER TABLE … DETACH PARTITION` appears nowhere in the repository. No Parquet export, no S3 client, no archival job. `docker-compose.yml` declares one volume (`talentra_pgdata`) and no S3 integration. PostgreSQL does support `DETACH PARTITION`, so the *capability* is real; the *pipeline* is not implemented, and "zero operational downtime" is a runtime property nothing here demonstrates.

**Recommended correction**: reclassify as future recommendation — "can be detached via `ALTER TABLE … DETACH PARTITION`; no automated archival pipeline is implemented."

### A-04 — §3.5, line 111 — "refreshed concurrently on scheduled cron intervals" · **UNSUPPORTED** · Confidence: HIGH

> "**Pre-aggregated Materialized Views**: High-overhead funnel conversions are pre-aggregated into `analytics.mv_hiring_funnel_summary` and `analytics.mv_gig_fulfilment_summary`, refreshed concurrently on scheduled cron intervals."

**Evidence**: The procedure is real — `019:308-315` defines `analytics.refresh_reporting_marts()` issuing `REFRESH MATERIALIZED VIEW CONCURRENTLY` for both views. But the scheduling is not: `grep -rni "cron\|pg_cron\|schedule" db/ scripts/` finds no scheduler; the only `CREATE EXTENSION` statements in the entire schema are `btree_gist` (`014:8`, `017:8`), so `pg_cron` is not installed. Nothing invokes `refresh_reporting_marts()` automatically. **Data population is also narrower than implied**: `analytics.fact_application_event` is populated only by `scripts/generate_data.py:772` (a synthetic loader); there is no trigger or CDC path from `recruitment.candidate_application` into the fact table, and `analytics.fact_gig_performance` / `analytics.fact_wallet_transaction` have **no populating code at all** (grep returns zero hits outside `019`).

**Recommended correction**: "refreshed by the `analytics.refresh_reporting_marts()` procedure (`REFRESH MATERIALIZED VIEW CONCURRENTLY`); no scheduler invokes it automatically, and the fact tables are populated only by the synthetic data loader."

### A-05 — §3.2, line 82 — the locked row · **CONTRADICTED** · Confidence: HIGH

> "**Pessimistic Concurrency**: During login, the function acquires a row-level lock (`SELECT ... FOR UPDATE`) on the user's allocated licence seat in `commercial.licence_seat_allocation`."

**Evidence**: `db/migrations/015_create_licences_and_device_limits.sql:185`:

```sql
PERFORM id FROM core.user_account WHERE id = p_user_account_id FOR UPDATE;
```

The lock is taken on **`core.user_account`**, not on `commercial.licence_seat_allocation`. The seat row is read (`015:188-196`) but never locked. `grep -rn "FOR UPDATE" db/migrations/` returns exactly two hits: `015:108` (locks `commercial.subscription_licence` in an unrelated seat-capacity trigger) and `015:185` (locks `core.user_account`). This is not cosmetic — it identifies which resource serializes concurrent logins, and it is the resource the concurrency test actually contends on.

**Recommended correction**: "acquires a row-level lock (`SELECT … FOR UPDATE`) on the `core.user_account` row of the user being logged in."

### A-06 — §5, line 143 — "100% of tables" use an `id` identity PK · **CONTRADICTED** · Confidence: HIGH

> "1. **Surrogate Key Uniformity**: 100% of tables use `BIGINT GENERATED ALWAYS AS IDENTITY` primary keys named `id`."

**Evidence**: `grep -rn "PRIMARY KEY" db/migrations/ | grep -v "id)"` returns five non-`id` primary keys:

| Table | Primary key | Type | Source |
|:--|:--|:--|:--|
| `analytics.dim_date` | `date_key` | `INTEGER` | `019:21` |
| `analytics.dim_candidate` | `candidate_key` | `BIGINT IDENTITY` | `019:64` |
| `analytics.dim_organization` | `organization_key` | `BIGINT IDENTITY` | `019:88` |
| `analytics.dim_job_posting` | `job_posting_key` | `BIGINT IDENTITY` | `019:115` |
| `recruitment.candidate_application_partitioned` | `(id, applied_at)` | compound | `019:336` |

The partitioned table declares `id BIGINT GENERATED ALWAYS AS IDENTITY` **without** a single-column PK — PostgreSQL requires the partition key in every partitioned PK, hence the compound form. The "100%" absolute is false in two independent ways.

**Note**: `docs/rule-compliance.md` §RG2 states the invariant correctly as "All **operational** primary keys use `BIGINT GENERATED ALWAYS AS IDENTITY` named `id`", and its §2 evidence explicitly carves out "or standard dimensional keys `date_key`, `job_posting_key` in OLAP marts". The architecture doc's absolute phrasing is the outlier.

**Recommended correction**: "All *operational* tables use `BIGINT GENERATED ALWAYS AS IDENTITY` primary keys named `id`; the four `analytics.dim_*` dimensions use surrogate `*_key` keys, and the partitioned application table uses the compound `(id, applied_at)` primary key PostgreSQL requires."

### A-07 — §5, line 145 — "Every date-time field … `TIMESTAMPTZ`" · **CONTRADICTED (as written)** · Confidence: HIGH

> "3. **UTC Strictness**: Every date-time field across all 10 schemas uses `TIMESTAMPTZ` normalized to UTC."

**Evidence**: Nine columns are `DATE` (no time component, no timezone by definition): `010:102-103`, `014:140-141`, `014:272-273`, `005:90-91`, `005:147-148`, `019:11`.

**Partial defence of the intent**: the claim's likely intent — "no timezone-naive `TIMESTAMP` anywhere" — **does hold**. `grep -rniE "\bTIMESTAMP\b" db/migrations/ | grep -vi "timestamptz\|timestamp with\|timestamp without"` returns a single hit, and it is a *comment string*, not a column (`010:327`, the word "timestamp" inside a `COMMENT ON TABLE`). There are zero naive `TIMESTAMP` columns.

**Recommended correction**: "No column uses a timezone-naive `TIMESTAMP`; all instant-valued timestamps are `TIMESTAMPTZ` normalized to UTC. Calendar-date fields (employment and assignment windows, `analytics.dim_date.calendar_date`) are `DATE` by design."

### A-08 — §5, line 146 — anti-sentinel discipline · **VERIFIED** · Confidence: HIGH — *keep as-is*

Checked adversarially because stated absolutely. `grep -rniE "'(NA|NONE|UNKNOWN|NULL|N/A|-1)'" db/migrations/` → **no matches**. `grep -rn "9999" db/migrations/` → **no matches**. The only `-1` is a `COALESCE` default inside a trigger's `WHERE` clause (`015:112`), not a stored value. **This claim holds and should not be altered.**

### A-09 — §5, line 144 — "Zero cross-schema foreign keys" · **CONTRADICTED (internally)** · Confidence: HIGH

> "2. **Domain Isolation**: Zero cross-schema foreign keys bypass operational APIs."

**Evidence**: contradicted by the document's own §2 schema table (line 52: "FKs to `core.user_account` and `master.*`"; line 53: "FKs to `profile.candidate_profile`, `core.user_account`, `master.*`"). Repo-wide there are 24 `REFERENCES master.*` and 48 `REFERENCES core.*` foreign keys. The "bypass operational APIs" qualifier is unfalsifiable — no API layer is defined in this repository.

**Recommended correction**: "Cross-schema foreign keys are used deliberately for referential integrity (e.g. `recruitment.candidate_application` → `profile.candidate_profile`); schemas are logically separated by ownership, not by physical FK isolation."

### A-10 — §1.1, line 38 — "ACID … under 2 milliseconds" · **UNSUPPORTED** · Confidence: HIGH

> "In Talentra, ACID guarantees ensure atomic consistency in under 2 milliseconds."

**Evidence**: no benchmark measures a cross-domain hire transaction; `db/queries/` contains 12 single-workload SELECTs, none performing the described multi-table write. The figure "under 2 milliseconds" has no measurement behind it. Compounding this, the described operation **cannot currently be executed**: `grep -rn "filled_headcount\|headcount\|filled_count" db/migrations/` returns **no matches**. `recruitment.job_posting` has `vacancy_count INTEGER NOT NULL DEFAULT 1` (`008:30`) but no filled-headcount counter to increment.

**Recommended correction**: "In Talentra, a single ACID transaction guarantees atomic consistency across these writes. *(No benchmark measures this cross-domain transaction; `recruitment.job_posting` tracks `vacancy_count` only and has no filled-headcount counter today.)*"

### A-11 — §1.1, line 38 — "incrementing filled headcount" · **CONTRADICTED** · Confidence: HIGH

Same sentence: the described atomic operation references a column that does not exist. Folded into the A-10 correction; no separate edit needed.

### A-12 — header, line 5 — "95 Operational, Dimensional, and Partitioned Tables" · **VERIFIED (with label imprecision)** · Confidence: HIGH

`grep -rn "CREATE TABLE" db/migrations/ | wc -l` → **95**. Breakdown: 92 standalone tables + 3 partitions of `candidate_application_partitioned`, plus 2 materialized views (not tables). Per-schema: `recruitment` 18, `profile` 13, `messaging` 11, `core` 9, `master` 9, `gig` 9, `commercial` 8, `analytics` 7, `sourcing` 5, `audit` 2.

The **number is correct** — this is a correction to an earlier working assumption in this engagement that the count excluded `CREATE TABLE IF NOT EXISTS` tables. It does not: all four `IF NOT EXISTS` tables (`master.language`, `commercial.subscription_licence`, `commercial.licence_seat_allocation`, `core.user_device`) are included in the 95, because the grep counts every `CREATE TABLE` line regardless of the `IF NOT EXISTS` suffix.

The **label** is imprecise: the 3 partitions *are* among the 95, so "Operational, Dimensional, and Partitioned" over-counts the categories, and the 2 materialized views are excluded.

**Recommended correction (optional, cosmetic)**: "95 Tables (92 standalone + 3 partitions) and 2 Materialized Views, across 10 Schemas".

### A-13 — §2 schema table, line 56 — `commercial` key tables omit four tables · **UNSUPPORTED (incomplete enumeration)** · Confidence: HIGH

Line 56 lists `subscription_licence`, `licence_seat_allocation`, `subscription_plan`, `subscription`, `wallet`, `wallet_ledger`. The schema also has `commercial.invoice`, `commercial.payment_order`, `commercial.payment_refund`, `commercial.candidate_profile_download_history` — the last being the subject of benchmark Query 08, a STRIDE repudiation control (threat-model line 44), and a revenue source referenced by `docs/competitive-benchmark.md` §2.3.

### A-14 — §2 schema table, line 55 — `sourcing` table list · **VERIFIED (complete list)** · Confidence: HIGH — *keep as-is*

Line 55 lists `job_consultant_policy`, `consultant_sourcing_request`, `sourcing_submission`, `outreach_batch`, `outreach_recipient` — this list **is** complete for `sourcing` (5 tables, matching the schema). No change needed here.

One adjacent issue is *not* in this document: `sourcing.consultant_sourcing_request` is the table the consultant-policy trigger actually fires on (`016:130`), and `docs/threat-model.md` line 47 attributes the control to `sourcing_submission` — a different table. That defect belongs to the threat model, and is recorded as **T-10** below.

### A-15 — §2 schema table, line 51 — `master` omits `industry` and `work_type` · **UNSUPPORTED (incomplete enumeration)** · Confidence: HIGH

Line 51 lists 8 `master` tables; the schema has 9 — `master.industry` and `master.work_type` are absent. `master.work_type` is filtered by benchmark Query 02 (`wt.code IN ('remote','hybrid')`); `master.industry` is the dimension benchmark Query 10 groups by.

### A-16 — §3.4, lines 96-105 — append-only ledger + reconciliation invariant · **VERIFIED for the trigger; UNSUPPORTED for the invariant as a maintained property** · Confidence: MEDIUM

> "**Reconciliation Invariant**: $\text{Wallet Balance} \equiv \sum \text{Credits} - \sum \text{Debits}$"

**Evidence**: The trigger half is verified — `017:364-377` (`commercial.prevent_ledger_tampering` + `trg_prevent_wallet_ledger_tampering`) genuinely blocks `UPDATE` and `DELETE` on `commercial.wallet_ledger`; `012:281-293` does the same for `audit.audit_event`; `017:439-446` for `commercial.candidate_profile_download_history`.

**Limitation on the invariant**: `commercial.wallet.balance` (`017:251`) is a **stored, independently mutable column**. There is **no trigger or function anywhere that derives it from the ledger** — `grep -rn "UPDATE commercial.wallet\b\|SET balance" db/ scripts/ tests/` returns only `scripts/generate_data.py:678` (a seed-time upsert) and `tests/test_concurrency.py:286-287` (a test that deliberately debits the balance column directly, outside the ledger). The invariant therefore holds only where application code maintains it; it is **not enforced by the schema**. The reconciliation *check* exists (`scripts/validate_data.py:239-258` and benchmark Query 05), which is a different thing from enforcement.

**Recommended correction**: append "— the wallet balance is a stored column; the schema records ledger entries immutably but does not itself derive or enforce the balance, so reconciliation is checked by `scripts/validate_data.py` and benchmark Query 05 rather than guaranteed by a constraint."

### A-17 — §4, lines 119-137 — engine tuning · **UNSUPPORTED as deployed** · Confidence: HIGH

> "For production deployment supporting 1M+ candidate profiles and 5M+ applications, the following database engine parameters are tuned:"

**Evidence**: the section is framed as a *production deployment* profile, and the code block is correctly labelled as configuration to be applied. But nothing in the repository applies it: there is **no `postgresql.conf`**, no `postgresql.auto.conf`, no init directory, no `command:` override in `docker-compose.yml` (the service runs the stock `postgres` entrypoint), and no config mount (`docker-compose.yml` declares only the `talentra_pgdata` volume). The running container therefore uses **stock PostgreSQL 17 defaults** — `shared_buffers` 128 MB, `work_mem` 4 MB, `max_connections` 100, `random_page_cost` 4.0, `effective_cache_size` 4 GB.

**Confidence note**: the live values could not be sampled (limitation L1). The conclusion rests on the *absence* of any configuration artifact, which is verifiable statically and is sufficient.

**Recommended correction**: keep the block but label it explicitly as a **proposed production configuration** that is not applied by the repository's `docker-compose.yml`, and note that the benchmark artifact was produced on stock defaults.

---

## 4. Findings — `docs/competitive-benchmark.md`

**Verdict: NEEDS FACTUAL CORRECTIONS** (structure complete; 2 contradicted / 5 unsupported / 1 needs external evidence)

### C-01 — §2.3, line 47 — SOC 2 Type II attestation · **UNSUPPORTED (compliance status)** · Confidence: HIGH · **PRIORITY 1**

> "Immutability triggers physically prevent modification or deletion, satisfying strict SOC 2 Type II and financial audit compliance."

**Evidence**: the *technical* premise is verified — `trg_prevent_wallet_ledger_tampering` (`017:374-377`), `trg_prevent_audit_event_tampering` (`012:290-293`), and `trg_prevent_download_history_tampering` (`017:443-446`) genuinely raise on `UPDATE`/`DELETE`.

The *conclusion* does not follow. SOC 2 Type II is an attestation over a period of time across a full control environment (access control, change management, monitoring, incident response, personnel, vendor risk). This repository contains a subset of the technical controls, no control mapping, no evidence-collection process, and no attestation. The same conclusion appears at `docs/threat-model.md:4` and `docs/integration-boundaries.md:46` ("PCI-DSS zero-storage compliance").

**Also note**: the trigger blocks `UPDATE`/`DELETE` but **not `TRUNCATE`** — row-level `BEFORE` triggers do not fire on `TRUNCATE`, and no `BEFORE TRUNCATE` statement trigger exists anywhere (`grep -rni "TRUNCATE" db/` → only `generate_data.py:456` on a temp table).

**Recommended correction** (as drafted in §8): state the implemented control, drop the compliance conclusion, and note the TRUNCATE limitation.

### C-02 — §2.4, line 51 — "quarterly and annual range partitioning" · **CONTRADICTED** · Confidence: HIGH

Identical defect to A-01. `019:339-350` creates three **annual** partitions; `grep -rn "PARTITION OF" db/migrations/` → 3 rows, no quarterly partition exists.

**Recommended correction**: "declarative **annual** range partitioning".

### C-03 — §2.4, line 51 — "prune … entirely, keeping the active index working set 100% resident" · **UNSUPPORTED + CONTRADICTED** · Confidence: HIGH

Three independent problems:

1. **No query reaches the table.** Zero of 12 benchmark queries reference `candidate_application_partitioned`.
2. **"100% resident" conflates two quantities.** The historical artifact shows `buffer_hit_ratio_pct: 100.0` for all 12 queries with `shared_read_blocks: 0` — a buffer-cache *hit ratio over a warm, small dev dataset*. That is not a statement about residency of a 100M-row working set.
3. **Even for a query that did filter on `applied_at`, the seeded data would not demonstrate pruning.** `scripts/generate_data.py:469-474` copies 50,000 rows from `recruitment.candidate_application` into the partitioned table with `applied_at` defaulting to `CURRENT_TIMESTAMP` — all 50,000 rows land in the single `y2026` partition. `y2025` and `y2027` are empty.

**Recommended correction**: remove "100% resident"; state that pruning applies to `applied_at`-filtered queries, that no benchmark query targets the table, and that the seeded data populates a single partition.

### C-04 — §1 matrix, line 16 — "prunes 75%+ of index scans" · **UNSUPPORTED** · Confidence: HIGH

Three documents state three different figures for the same unmeasured quantity: `competitive-benchmark.md:16` "75%+", `architecture.md:91` "66% to 90%", `README.md:54` "$>75\%$". None has a measurement behind it, and the intervals also disagree (quarterly vs "annual and quarterly" vs annual).

**Recommended correction**: remove the percentage from all three files; state the fact once (partitioned by `RANGE (applied_at)`, annual intervals, pruning applies to `applied_at`-filtered queries).

### C-05 — §2.1, line 26 — "under 35 milliseconds" · **UNSUPPORTED** · Confidence: HIGH

No benchmark query joins `profile.candidate_profile` with `gig.gig_worker_profile`. The nearest measured figures are Q01 (candidate search, p50 30.87 ms) and Q07 (gig worker search, p50 11.07 ms) — two *separate* queries over separate tables, from the historical 2026-10-17 v1 run. They cannot be combined into a unified-discovery latency.

**Recommended correction**: remove the figure, or mark it as a design goal.

### C-06 — §2.2, line 39 — "at the write-ahead log (WAL) boundary" · **CONTRADICTED (mechanism)** · Confidence: MEDIUM

> "Even under thousands of concurrent booking attempts, PostgreSQL physically rejects conflicting temporal ranges at the write-ahead log (WAL) boundary."

**Evidence**: the quoted constraint SQL matches `014:316-321` exactly, and `btree_gist` is installed (`014:8`) — the *constraint* is verified. The *mechanism* is misdescribed: an `EXCLUDE USING gist` constraint is enforced by the constraint's GiST index at statement-execution time and surfaces as `ExclusionViolation` (SQLSTATE 23P01); it is not a WAL-boundary mechanism. The **"thousands of concurrent booking attempts"** claim is untested — `tests/test_concurrency.py` uses 5 threads for this constraint (`num_threads = 5`, line 151); the file's other two tests use 10 threads each (lines 75, 274).

**Recommended correction**: "PostgreSQL rejects conflicting temporal ranges at statement-execution time via the constraint's GiST index, raising `ExclusionViolation` (SQLSTATE 23P01) before commit. Verified by `tests/test_concurrency.py` under 5-thread contention."

### C-07 — §1 matrix, line 13 — exclusion constraint guarantees · **VERIFIED** · Confidence: HIGH — *keep as-is*

`EXCLUDE USING gist (gig_worker_profile_id WITH =, daterange(assigned_start_date, assigned_end_date, '[]') WITH &&) WHERE (assignment_status = 'active')` at `014:316-321` genuinely enforces this at the storage layer, with `btree_gist` installed. `tests/test_concurrency.py:126-228` verifies it. **Keep.**

*Additional observation (not a defect in this document):* a **second** exclusion constraint exists — `ex_subscription_no_overlap` on `commercial.subscription` using `tstzrange` (`017:98-101`) — which neither this document nor `architecture.md` mentions.

### C-08 — §1 matrix, line 17 — `core.user_block` XOR enforcement · **VERIFIED** · Confidence: HIGH — *keep as-is*

`core.user_block` carries `ck_user_block_target_xor` (`012`) enforcing exactly one of `blocked_user_account_id` / `blocked_organization_id`, plus partial unique indexes `uq_user_block_user` / `uq_user_block_organization`. Accurate.

### C-09 — §1 matrix, line 18 — `messaging.get_ui_translation` · **VERIFIED** · Confidence: HIGH — *keep as-is

`018:56-90` defines the function with the three-tier fallback (target → English → raw key), marked `STABLE`. Accurate.

*Note*: the benchmark Q12 does **not** call this function — it inlines an equivalent `LEFT JOIN` (`db/queries/12_multilingual_ui_translation_lookup.sql`). So `README.md:55`'s "in under 1.2 ms" is not a measurement of `get_ui_translation` itself. That is a README finding, not a finding on this document.

### C-10 — §1 matrix, line 18 — "Dynamic Translation Engine" · **VERIFIED with a data-population caveat** · Confidence: MEDIUM

`messaging.ui_translation` is populated by `scripts/generate_data.py` (a seed loader) and by `db/migrations/004_seed_master_reference_data.sql`. There is no admin UI or translation-management workflow in the repository, so "engine" describes the SQL resolution logic rather than an operational translation pipeline. Acceptable as-is.

### C-11 — §1 matrix, lines 11-18 — third-party architectural claims · **NEEDS EXTERNAL EVIDENCE** · Confidence: N/A (limitation L4)

The Naukri / Monster / LinkedIn columns assert specific architecture for named third parties ("Polyglot distributed microservice mesh (Espresso, Voldemort, Rest.li)", "Isolated Modes", "Post-facto Revocation"). No evidence for these exists in this repository, and none can be obtained from it. The same applies to the "Legacy Failure" framing in §2.1-§2.4.

**Recommendation**: for an internal design dossier this framing is acceptable; for any external audience each third-party characterization needs a citation, and the "legacy failure" framing should be softened to a description of a known anti-pattern rather than a claim about named companies' internals. **Owner approval required** — this is a judgment call about the document's audience.

### C-12 — §2.2, line 30 — "PostgreSQL's Generalized Search Tree (GiST) with the `btree_gist` extension" · **VERIFIED** · Confidence: HIGH — *keep as-is*

`btree_gist` is genuinely required for the `=` (equality) column inside a GiST exclusion constraint and is installed at `014:8` and `017:8`. Accurate.

### C-13 — §2.3, lines 43-45 — the illustrative "legacy" SQL · **VERIFIED as illustrative** · Confidence: HIGH — *keep as-is*

The `UPDATE company_wallet SET credits = credits - 1 WHERE company_id = 42;` block is explicitly framed as the legacy anti-pattern, not as Talentra code. Accurate as an illustration.

---

## 5. Findings — `docs/threat-model.md`

**Verdict: INCOMPLETE** (structure complete; its two headline controls — RLS and database roles — are not implemented anywhere in the repository)

This is the most consequential of the three documents. The problem is not wording: the security architecture described in §1 and §3-§4 is, in two of its central elements, a *design* presented as a *deployment*.

### T-01 — §1, line 10 and §4 (lines 92-158) — Row-Level Security presented as deployed · **CONTRADICTED** · Confidence: HIGH · **PRIORITY 1**

> §1: "…baked directly into PostgreSQL 17 via granular database roles, cryptographic hashing standards, append-only ledgers, **declarative Row-Level Security (RLS)**, and anti-tampering triggers."

**Evidence**: `grep -rn "ROW LEVEL SECURITY\|CREATE POLICY" db/ tests/` → **no matches**. There is not one `ENABLE ROW LEVEL SECURITY` statement and not one `CREATE POLICY` statement in the entire repository. Every policy in §4.1, §4.2 and §4.3 is aspirational.

**Additional defects in the policies as designs** (relevant if they are ever deployed):

| # | Defect | Location |
|:--|:--|:--|
| a | §4.1/§4.2 depend on `app.current_user_id` / `app.current_org_id` session variables. `grep -rn "current_setting" db/ scripts/ tests/` → matches only inside `threat-model.md` itself. **No code sets them.** With them unset, `NULLIF(current_setting(…, TRUE), '')` → NULL, `organization_id = NULL` → false, and `recruitment.job_posting` would be **invisible to `talentra_app`** — so the policies as written are not merely un-deployed, they are un-deployable. | `threat-model.md:106,121,129-130` |
| b | §4.2's `NOT EXISTS` correlates on `profile.candidate_profile.user_account_id`. Inside an RLS policy on `profile.candidate_profile`, that qualifying name is not valid; the policy would raise a runtime error on every row evaluation. | `threat-model.md:127` |
| c | §4.3's SQL is an inaccurate transcription: the real function is `sourcing.enforce_consultant_openness()` with variable `v_is_open` and the test `IF v_is_open IS NOT TRUE` (`016:110-133`). The doc's version would not run as written. | `threat-model.md:141-158` |

**Recommended correction** (§8 draft): relabel §4 explicitly as a **proposed design**, and correct the §4.3 function/trigger names to match `016:110-133`. **Owner decision required** on whether to implement RLS in a later phase or to reframe the section as a design.

### T-02 — §3, lines 53-75 — database roles presented as deployed · **CONTRADICTED** · Confidence: HIGH · **PRIORITY 1**

> "Talentra enforces separation of duties through distinct PostgreSQL database user roles:" followed by `CREATE ROLE` / `GRANT` / `REVOKE` for `talentra_app`, `talentra_reporting`, `talentra_admin`.

**Evidence**: `grep -rn "CREATE ROLE\|GRANT \|REVOKE " db/` → **no matches**. No role is created, no grant or revoke is issued. `talentra_app` and `talentra_reporting` **do not exist**. The only role in the running system is `talentra_admin`, created implicitly by `POSTGRES_USER` in `docker-compose.yml` — and it is a **SUPERUSER**, the exact privilege level this section's heading claims to avoid.

**Internal contradictions in the script itself**:

| # | Defect | Detail |
|:--|:--|:--|
| a | **The app role would retain full write access to the wallet ledger.** Line 59 grants `SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA core, profile, recruitment, gig, sourcing, commercial, messaging TO talentra_app` — and `commercial` is in that list. Line 60 then issues `GRANT SELECT, INSERT ON TABLE commercial.wallet_ledger, commercial.candidate_profile_download_history` — a grant does **not** revoke the `UPDATE`/`DELETE` from line 59, and no `REVOKE UPDATE, DELETE` exists anywhere in the script. The wallet ledger's immutability would rest solely on the trigger. | `threat-model.md:59-60` |
| b | The comment on line 62 says "Forbid TRUNCATE, DROP, ALTER for application user" but **no statement performs any such revocation**. `TRUNCATE` is excluded only because it was never granted (PostgreSQL grants no `TRUNCATE` by default) — the comment overstates what the script does. | `threat-model.md:62` |
| c | Line 63 `REVOKE ALL ON SCHEMA audit FROM talentra_app` followed by lines 64-65 re-granting `USAGE` and table privileges is internally coherent and correct — the one part of the script that is sound. | `threat-model.md:63-65` |

**Recommended correction**: reframe §3 as a **proposed role model**, and add the missing `REVOKE UPDATE, DELETE ON commercial.wallet_ledger, commercial.candidate_profile_download_history FROM talentra_app;`.

### T-03 — §2 row "Tampering", line 43 — trigger name `trg_prevent_audit_tampering` · **CONTRADICTED** · Confidence: HIGH

The real trigger is **`trg_prevent_audit_event_tampering`** (`012:290`). The *function* `audit.prevent_audit_tampering()` does exist (`012:281`), so the doc conflated function and trigger names. `trg_prevent_wallet_ledger_tampering` is correct (`017:374`).

**Recommended correction**: change to `trg_prevent_audit_event_tampering`.

### T-04 — §2 row "Repudiation", line 44 — IP address capture · **CONTRADICTED** · Confidence: HIGH

> "Append-only audit logging in `commercial.candidate_profile_download_history` capturing downloader user ID, organization ID, wallet ledger ID, **IP address**, and timestamp."

**Evidence**: `017:381-389` — the table's columns are `id`, `organization_id`, `downloader_user_account_id`, `candidate_profile_id`, `credit_deduction_amount`, `currency_code`, `wallet_ledger_id`, `downloaded_at`. There is **no `ip_address` and no `user_agent` column**.

IP capture does exist — in `audit.audit_event` (`012:240-241`: `client_ip VARCHAR(45)`, `user_agent VARCHAR(500)`) — but `audit.audit_event` is populated only by the device-limit and session-revocation paths (`015:221`, `015:317`). **Download events never reach `audit.audit_event`.** The specific repudiation evidence the row claims does not exist.

**Recommended correction**: remove the IP-address claim, or state that IP/user-agent capture exists on `audit.audit_event` but that download events are not currently written there.

### T-05 — §2 row "Repudiation", line 44 — "Cannot be altered or truncated" · **CONTRADICTED** · Confidence: HIGH

`trg_prevent_download_history_tampering` (`017:443-446`) is `BEFORE UPDATE OR DELETE`. `TRUNCATE` does not fire row-level `BEFORE` triggers, and no `BEFORE TRUNCATE` statement trigger exists anywhere in the schema. The same applies to `wallet_ledger` and `audit_event`.

**Recommended correction**: "cannot be altered or deleted by `UPDATE`/`DELETE`; `TRUNCATE` is not blocked by a trigger and must be prevented by table privileges."

### T-06 — §2 row "Denial of Service", line 46 — "B-Tree and GIN indexes" · **CONTRADICTED** · Confidence: HIGH

> "All 12 operational queries backed by optimized B-Tree and **GIN** indexes."

**Evidence**: `grep -rn "USING gin" db/ tests/ scripts/` → **no matches**. The schema contains **zero GIN indexes**. The only non-B-tree access method is `gist`, used for exactly two exclusion constraints: `ex_gig_assignment_no_overlap` (`014:317`) and `ex_subscription_no_overlap` (`017:98`).

**Recommended correction**: "backed by B-Tree indexes, with GiST indexes backing two exclusion constraints."

### T-07 — §2 row "Spoofing", line 42 — Argon2id and SHA-256 session tokens · **UNSUPPORTED (unenforced)** · Confidence: HIGH

> "Passwords hashed using Argon2id (`$argon2id$v=19$m=65536,t=3,p=4$`). Session tokens stored as SHA-256 hashes (`session_token_hash`)."

**Evidence**:
- `grep -rni "argon2" db/` → **one** hit: `012:85`, `algorithm VARCHAR(50) NOT NULL DEFAULT 'argon2id'` — a **default on a free-text column**. No format `CHECK`, no `pgcrypto`, no hashing function. A row with `algorithm='md5'` and `secret_hash='x'` is accepted. `core.user_account.password_hash` (`002:15`) is unconstrained `TEXT` with only a length check (`002:56-60`).
- `core.user_session.session_token_hash` (`002:139`) is `VARCHAR(255) NOT NULL` with a length check only. **No format constraint, no hashing performed by the database.**
- The §1 diagram's "SHA-256 Checksums" (`threat-model.md:32`) is accurate for **document checksums** only: `profile.candidate_document.checksum_sha256 CHAR(64)` with a hex-format `CHECK` (`006:17,96-97`). It is not a session-token mechanism. The document conflates the two.

**Related but distinct**: `docs/rule-compliance.md` §RG6 claims a `CHECK constraint ck_user_account_password_hash_format` with the regex `^\$(argon2id|2b|2a)\$`. **That constraint does not exist** — `grep -rn "ck_user_account_password_hash_format" db/` → no matches; the actual constraint is `ck_user_account_password_hash` (`002:56`), a length check only. What *does* exist is a **validator query** (`scripts/validate_data.py:210-220`) that checks stored values against that regex at runtime and reports RG6 PASS. So the *data* conforms in the seeded dataset; the *schema* does not enforce it. The compliance doc conflates a runtime data check with a schema constraint.

**Recommended correction**: state that the schema *stores* hashes in format-constrained columns and that the hashing algorithm is an application-layer responsibility with a default, not an enforced constraint; and correct the §1 diagram's "SHA-256 Checksums" to reference document checksums specifically.

### T-08 — §2 row "Information Disclosure", line 45 — masking · **UNSUPPORTED (not implemented)** · Confidence: HIGH

> "Candidate phone/email **masked** (`+91 98****3210`) unless candidate has applied or granted explicit consent in `core.consent_record`."

**Evidence**: `grep -rn "mask\|MASKING" db/ scripts/` → **no matches**. No masking function, view, expression, or trigger exists. `core.user_account` stores `phone_e164 VARCHAR(16)` and `email VARCHAR(254)` in plaintext with format CHECKs only (`002:12-42`).

`core.consent_record` **does** exist as a table (`012:128-165`, with `consent_type` and a `granted_at`/`revoked_at` CHECK) — so the *consent data model* is present. But nothing reads it to gate visibility. The masking behaviour is described, not implemented.

**Recommended correction**: "consent state is modelled in `core.consent_record`; masking of phone/email for unauthorized viewers is **not currently implemented** at the database layer."

### T-09 — §2 row "Information Disclosure", line 45 — `core.user_block` enforcement · **CONTRADICTED (attribution)** · Confidence: HIGH

> "`core.user_block` prevents blocked entities from querying candidate profiles."

**Evidence**: `core.user_block` **records** the block; it does not **enforce** anything. Enforcement is a `NOT EXISTS` subquery written into each querying statement — precisely as in benchmark Query 06 (`db/queries/06_sourcing_outreach_unblocked.sql:17-23`). With no RLS policy (T-01) and no view or trigger, a query that omits the `NOT EXISTS` clause returns blocked candidates without obstruction.

**Recommended correction**: "block state is recorded in `core.user_block` and must be enforced by each querying statement (see `db/queries/06_sourcing_outreach_unblocked.sql`); database-level enforcement via RLS is proposed but not yet implemented."

### T-10 — §2 row "Elevation of Privilege", line 47 — consultant trigger name and target table · **CONTRADICTED** · Confidence: HIGH

> "Database trigger `trg_enforce_consultant_policy_restrictions` prevents non-consultant jobs from receiving agency submissions."

**Evidence**: the real trigger is **`trg_enforce_consultant_openness`**, on **`sourcing.consultant_sourcing_request`** (`016:130-133`); the function is `sourcing.enforce_consultant_openness()`. The doc's §2 row and §4.3 both use the wrong name, and §4.3 additionally uses the wrong function body.

**Recommended correction**: correct the name and specify the guarded table.

### T-11 — §2 row "Tampering", line 43 — candidate assessment scores · **CONTRADICTED (attack vector / mitigation mismatch)** · Confidence: MEDIUM

The row's attack vector is "Recruiter modifies candidate assessment score or alters credit ledger", and its mitigation is append-only triggers. `profile.candidate_assessment_score` has **no** append-only trigger; the three append-only triggers protect `wallet_ledger`, `audit_event` and `candidate_profile_download_history` only. Assessment scores are mutable by design.

**Recommended correction**: narrow the row's attack vector to the ledger/audit/download-history tables, or note that assessment scores are deliberately mutable.

### T-12 — §2, line 46 — partition mitigation vs actual benchmark coverage · **UNSUPPORTED as a live mitigation** · Confidence: MEDIUM

> "High-volume tables partitioned by range (`candidate_application_partitioned`)."

The table exists and is partitioned annually (verified). But no benchmark query targets it, and the **authoritative** application table — the one carrying all 50,000 seeded application rows, the status-history trigger (`009:205-209`), and the `UNIQUE (candidate_profile_id, job_posting_id)` constraint — is the **unpartitioned** `recruitment.candidate_application` (`009:4`). The partitioning is therefore not currently a mitigation for the query set the row cites as its verification mechanism.

**Recommended correction**: note that the partitioned table is a scale-out path, and that the operational application table is currently unpartitioned.

### T-13 — §5, line 164 — "classifies every column across all 95 tables" · **CONTRADICTED** · Confidence: HIGH

**Evidence**: `docs/data-dictionary.md` is 216 lines and documents **13 tables** in 13 subsections — `core.user_account`, `core.user_session`, `core.user_block`, `master.country`/`master.city`, `master.skill`, `profile.candidate_profile`, `profile.candidate_skill`, `recruitment.job_posting`, `recruitment.candidate_application`, `gig.gig_assignment`, `commercial.wallet_ledger`, `audit.audit_event`. That is **13 of 95 tables ≈ 14%**, with 97 classified columns against several hundred in the schema. The overclaim is replicated in `data-dictionary.md:4` ("95 Operational, Dimensional, and Partitioned Tables" in the header) and `data-dictionary.md:11` ("Every column in Talentra is tagged").

**Recommended correction**: "Talentra classifies columns into four sensitivity tiers (Rule Group 6). The data dictionary currently documents **13 of 95 tables** as a representative sample; full coverage is outstanding."

### T-14 — §5, line 171 — "AES-256 CBC encryption" and encrypted tax IDs · **CONTRADICTED** · Confidence: HIGH

> `[SENSITIVE]` storage standard: "Salted Argon2id hash, **AES-256 CBC encryption**, E.164 normalization"; example "Tax: `XXXX-XX-4912`".

**Evidence**:
- `grep -rni "pgcrypto\|aes-256\|aes256\|encrypt(\|decrypt(" db/` → **no matches**. No encryption extension, no encrypt/decrypt function, anywhere.
- `grep -rni "tax_id\|national_id\|aadhaar\|pan_number" db/migrations/` → **no matches**. There is **no tax-ID column** in the schema to encrypt.

The same claim is propagated to `docs/data-dictionary.md:15` ("encrypted tax IDs"), so it must be corrected in both files.

**Recommended correction**: replace the storage standard with the real one — "Salted password hash (algorithm not enforced by schema), SHA-256 document checksum, E.164 phone normalization" — and delete the tax-ID example.

### T-15 — §5, line 164 — the four-tier scheme itself · **VERIFIED** · Confidence: HIGH — *keep as-is

The four tiers `[PUBLIC]` / `[INTERNAL]` / `[PERSONAL]` / `[SENSITIVE]` are defined in `data-dictionary.md:11-15` and used consistently across its 97 documented columns (58 `[INTERNAL]`, 20 `[PUBLIC]`, 10 `[SENSITIVE]`, 9 `[PERSONAL]`). The *scheme* is real; only its *coverage* claim (T-13) and the *storage standard* (T-14) are wrong.

### T-16 — §6.1, line 178 — audit event coverage · **CONTRADICTED** · Confidence: HIGH

> "Every security-sensitive event (login, permission change, session revocation, profile unlock, device limit breach) is recorded in `audit.audit_event`."

**Evidence**: `grep -rn "INSERT INTO audit.audit_event" db/` returns exactly **two** locations, both in `015`: the device-limit rejection (`015:221`) and session revocation (`015:317`). There is **no** insert on successful login, **no** insert on permission change (`core.user_role` / `core.role_permission` have no audit trigger), and **no** insert on profile unlock or download.

**Recommended correction**: "Device-limit breaches (`015:221`) and session revocations (`015:317`) are recorded in `audit.audit_event`. Recording of logins, permission changes and profile unlocks is outstanding."

### T-17 — §6.1, lines 181-191 — `audit.audit_event` DDL does not match the schema · **CONTRADICTED** · Confidence: HIGH

The doc shows `event_type`, `severity`, `ip_address INET`, `metadata JSONB`, `created_at`. The actual table (`012:230-242`) has `actor_user_account_id`, `impersonator_user_account_id`, `action VARCHAR(80)`, `entity_schema`, `entity_name`, `entity_id`, `old_values_json`, `new_values_json`, `client_ip VARCHAR(45)`, `user_agent VARCHAR(500)`, `recorded_at`. No `event_type`, no `severity`, no `ip_address`, no `metadata`, no `created_at`; and the doc's `ip_address INET` is the *better* type — the schema uses `VARCHAR(45)`.

**Recommended correction**: replace the illustrative DDL with the actual column list from `012:230-242`.

### T-18 — §6.2, lines 198-209 — anti-tamper trigger · **VERIFIED (function body) / name mismatch** · Confidence: HIGH

The function body matches `012:281-288`. The **trigger** is named `trg_prevent_audit_event_tampering` (`012:290`), not `trg_prevent_audit_tampering` as shown at line 207. Same defect as T-03.

**Recommended correction**: correct the trigger name at line 207.

### T-19 — §7, lines 216-217 — RPO 0 seconds and PITR · **CONTRADICTED** · Confidence: HIGH · **PRIORITY 2**

> "**Recovery Point Objective (RPO)**: **0 seconds** (Zero data loss). Achieved via PostgreSQL Write-Ahead Logging (WAL) streaming replication with synchronous commit to standby replica."
> "**Recovery Time Objective (RTO)**: **< 15 minutes**. Automated failover using Patroni / pg_auto_failover with point-in-time recovery (PITR) supported by continuous WAL archiving to S3."

**Evidence**: `grep -rni "patroni\|pg_auto_failover\|archive_command\|synchronous_standby\|wal_level\|archive_mode"` across the repository returns **one** hit — this sentence itself. No Patroni config, no `pg_auto_failover`, no `postgresql.conf` with `archive_mode` or `synchronous_standby`, no WAL-archiving job, no standby. `docker-compose.yml` defines exactly **one** Postgres service with a single named volume and `restart: unless-stopped` — there is no replica.

The repository's actual DR asset is `scripts/backup_restore.sh`: a **`pg_dump` / `pg_restore` round trip** — a logical, scheduled-backup approach whose RPO is *one backup interval*, not zero. PITR requires `archive_mode` + `archive_command` + `pg_basebackup`; none of that is present. The doc's inline runbook (`threat-model.md:219-222`) also writes to `/backups/`, a path that is **not** a mounted volume in `docker-compose.yml` and would not survive container replacement — and it diverges from the maintained script's actual flags and verification.

**Recommended correction**: state the implemented mechanism (logical `pg_dump` backups with a scripted restore-and-verify procedure validating row-count parity across seven tables) and give an RPO equal to the backup interval; mark synchronous replication / PITR as a production deployment requirement not present in this repository.

### T-20 — §7, line 222 — inline runbook vs maintained script · **UNSUPPORTED (superseded)** · Confidence: MEDIUM

The doc's inline `pg_dump` command differs from `scripts/backup_restore.sh` in format flags, target path, and verification. The script also drops and recreates a `talentra_recovery_test` database — worth flagging to any operator, since it is a destructive operation against a database the reader may not know exists.

**Recommended correction**: replace the inline snippet with a pointer to `scripts/backup_restore.sh`.

### T-21 — §2 row "Spoofing", line 42 — verification pointer · **UNSUPPORTED (wrong mechanism)** · Confidence: MEDIUM

The row cites `tests/test_identity.sql` and `tests/test_licences.sql` for the device-limit mitigation. Both files exist, but the device-limit *concurrency* guarantee is verified in `tests/test_concurrency.py` (`test_concurrent_device_logins`, asserting exactly 2 granted sessions, N-2 rejections, and the matching `device.limit_exceeded` audit count). The SQL tests cover schema constraints only.

**Recommended correction**: add `tests/test_concurrency.py` to the verification column.

### T-22 — §2 row "Denial of Service", line 46 — verification pointer · **UNSUPPORTED (points at an empty-result case)** · Confidence: MEDIUM

The row's verification mechanism is "`scripts/run_benchmarks.py`, Query 04". Two problems: `run_benchmarks.py` measures latency, not the DoS invariant; and **Query 04 returned zero rows** in the historical 2026-10-17 run (root `Actual Rows: 0`, `benchmark_results.json:1310`), so it verifies nothing about session validation. This is the same empty-result defect documented in `docs/phase2b-query-performance-validation.md` H-04.

**Recommended correction**: point to `tests/test_concurrency.py` and `tests/test_licences.sql` instead.

### T-23 — §1, lines 12-34 — the ASCII architecture diagram · **UNSUPPORTED (overstates deployed controls)** · Confidence: HIGH

The diagram asserts "Row-Level Security — Tenant Isolation", "Argon2id Passwords", "Encrypted Tax IDs", "SHA-256 Checksums", and "Immutable Audit Events" as components of the deployed core. Per T-01, T-07, T-08, T-12 and T-14: RLS is not deployed, there is no tax-ID column or encryption, Argon2id is an unenforced default, and the audit trail records only two event types. The diagram is the most prominent visual element of the document and overstates the implemented control surface.

**Recommended correction**: annotate the diagram to distinguish implemented from proposed controls, or move the unimplemented items to a clearly-labelled "planned" band.

### T-24 — header, line 4 — "Compliance Standards: GDPR Article 25/32, SOC 2 Type II, PCI-DSS SAQ-A" · **NEEDS EXTERNAL EVIDENCE** · Confidence: MEDIUM

As a statement of *target framework* this is defensible: the architecture plausibly aligns with GDPR Art. 25/32 (consent modelling, audit trail, minimisation) and with PCI-DSS SAQ-A scope (the provider owns the cardholder vault per `docs/integration-boundaries.md:46`; the database stores gateway references only, with no PAN/CVV columns — verified: `grep -rni "pan\|cvv\|card_number" db/migrations/` returns no card-data columns). The problem is the header's placement above a document whose §2 and §5 assert specific compliance properties, which reads as a claim of achieved compliance.

**Recommended correction**: relabel to "**Target Compliance Framework** (alignment intent; no attestation performed)". **Owner approval required** on final wording.

### T-25 — §4, line 94 — session context variables · **CONTRADICTED** · Confidence: HIGH

Covered under T-01(a), but recorded separately because it is independently fixable: `app.current_user_id` and `app.current_org_id` are never set by any code in the repository.

### T-26 — §2, line 44 — `commercial.candidate_profile_download_history` append-only status · **VERIFIED** · Confidence: HIGH — *keep as-is (with the T-05 wording fix)

`trg_prevent_download_history_tampering` (`017:443-446`) genuinely blocks `UPDATE` and `DELETE`. Only the "or truncated" clause needs correcting.

### T-27 — §3, line 74 — `talentra_admin` as SUPERUSER · **VERIFIED as described, but contradicts the section's own premise** · Confidence: HIGH

`CREATE ROLE talentra_admin WITH LOGIN SUPERUSER` is an accurate description of the effective state: `docker-compose.yml` sets `POSTGRES_USER: talentra_admin`, which makes that role a superuser. The doc is honest about the privilege, but §3's heading claims "separation of duties through distinct PostgreSQL database user roles" — and in the deployed system there is exactly one role, holding the highest privilege. This is a T-02 instance, recorded here to note the doc is *not* lying, just describing an unrealised design.

### T-28 — §4.1 — recruiter isolation policy semantics · **UNSUPPORTED (unverifiable without deployment)** · Confidence: MEDIUM

`grep -rn "is_open_to_consultants" db/migrations/016*` confirms the column exists (`016:12`), so the §4.3 function's referenced column is real. The §4.1 policy's `job_status = 'published'` branch is consistent with `recruitment.job_posting.job_status` (`008:20`) and its partial index `idx_job_posting_status_published` (`008:171-189`). The policy is *plausible* but unverifiable without deployment, and its candidate-visible branch grants access to all published jobs to any principal — presumably intended, but never stated. Folded into the T-01 correction.

### T-29 — Missing threat categories · **UNSUPPORTED (coverage gap)** · Confidence: MEDIUM

For completeness, a STRIDE dossier at this level would normally also address: authentication/authorization threats on the `master` and `analytics` read paths; audit-log exfiltration and log-tampering by a privileged administrator; availability threats specific to the GiST exclusion constraints (adversarial date-range insertion); and supply-chain threats. There is also no threat-to-control traceability matrix beyond the §2 "Verification Mechanism" column, which — per T-21 and T-22 — points at files that do not verify the claimed property.

**Recommended correction**: note as a scope limitation, or extend the document in a later phase. **Owner approval required** on scope.

---

## 6. Cross-Document Reconciliation (Step 3)

### 6.1 The ten required checks

| # | Check | Finding | Classification |
|:--|:--|:--|:--|
| 1 | **Annual vs quarterly partitioning** | `architecture.md:89` "annual and quarterly"; `competitive-benchmark.md:51` "quarterly and annual"; `README.md:54` "quarterly" (now corrected to annual in the working tree); `performance-report.md:188` "quarterly" (now corrected). `019:339-350` defines **3 annual partitions** only. | **CONTRADICTED** in 2 remaining files |
| 2 | **Operational vs partitioned application table; benchmark coverage** | The authoritative table is the **unpartitioned** `recruitment.candidate_application` (`009:4`) — it holds the status-history trigger (`009:205-209`), the `UNIQUE (candidate_profile_id, job_posting_id)` constraint, all 50,000 seeded rows, and is what benchmark Q03 targets. The partitioned table is a separate scale-out path. **No benchmark query targets the partitioned table.** | **CONTRADICTED** where claimed as live |
| 3 | **Partition-pruning and latency percentages** | Three different figures across three files for one unmeasured quantity (75%+, 66-90%, >75%). | **UNSUPPORTED** |
| 4 | **Stock defaults vs proposed tuning** | `architecture.md:119-137` presents a tuning profile. **Nothing applies it** — no `postgresql.conf`, no init dir, no `command:` override, no config mount in `docker-compose.yml`. The container runs stock PostgreSQL 17 defaults. Live values could not be sampled (L1); the static absence is sufficient. | **UNSUPPORTED as deployed** |
| 5 | **MV refresh procedure vs actual scheduling and data population** | `analytics.refresh_reporting_marts()` exists (`019:308-315`) and does use `REFRESH MATERIALIZED VIEW CONCURRENTLY`. **No scheduler invokes it** (no `pg_cron`; no cron in `db/` or `scripts/`). `fact_application_event` is populated only by `scripts/generate_data.py:772`; `fact_gig_performance` and `fact_wallet_transaction` have **no populating code at all**. | **CONTRADICTED** (scheduling + population) |
| 6 | **The row locked during concurrent login** | `core.user_account` (`015:185`), **not** `commercial.licence_seat_allocation` as claimed in `architecture.md:82`, `threat-model.md:46`, and `rule-compliance.md` §RG9. | **CONTRADICTED** in 3 files |
| 7 | **Wallet stored balance vs ledger reconciliation** | `commercial.wallet.balance` (`017:251`) is a stored column. **No trigger or function derives it from the ledger** — `grep -rn "UPDATE commercial.wallet\b\|SET balance" db/ scripts/ tests/` → only `generate_data.py:678` (seed) and `test_concurrency.py:286-287` (test-only). The invariant is **checked**, not **enforced**. | **UNSUPPORTED as an enforced invariant** |
| 8 | **UPDATE/DELETE triggers vs TRUNCATE and privileged actions** | All three append-only triggers are `BEFORE UPDATE OR DELETE` row-level. `TRUNCATE` fires neither, and no `BEFORE TRUNCATE` statement trigger exists. `threat-model.md:44` explicitly claims "cannot be altered **or truncated**". Privileged actions (`ALTER TABLE … DISABLE TRIGGER`, superuser) are also outside the trigger's reach. | **CONTRADICTED** |
| 9 | **Compliance claims vs implemented controls and external evidence** | `competitive-benchmark.md:47` (SOC 2 Type II), `threat-model.md:4` (GDPR/SOC 2/PCI-DSS), `integration-boundaries.md:46` (PCI-DSS zero-storage). Implemented controls are a small technical subset; no control mapping, gap analysis, or attestation exists in the repository. | **UNSUPPORTED / NEEDS EXTERNAL EVIDENCE** |
| 10 | **Actual concurrency scale vs "thousands of concurrent"** | `tests/test_concurrency.py` uses **10, 5 and 10** threads (lines 75, 151, 274). `competitive-benchmark.md:39` claims "thousands of concurrent booking attempts". | **CONTRADICTED** |

### 6.2 Consistency matrix across the seven documents

| Claim | `architecture.md` | `competitive-benchmark.md` | `threat-model.md` | `rule-compliance.md` | `README.md` | `performance-report.md` | Actual schema |
|:--|:--|:--|:--|:--|:--|:--|:--|
| Partition intervals | "annual **and quarterly**" (L89) | "**quarterly and annual**" (L51) | "partitioned by range" (L46) | "partitioned by `RANGE (applied_at)`" (L108) — *no interval stated* ✅ | "annually" ✅ *(corrected)* | "annual" ✅ *(corrected)* | **Annual only** (`019:339-350`) |
| Pruning % | "66% to 90%" (L91) | "75%+" (L16) | — | — | *(removed)* ✅ *(corrected)* | *(removed)* ✅ *(corrected)* | **Unmeasured** |
| Row locked at login | "licence seat" (L82) | — | "locked atomically (`FOR UPDATE`)" (L46) | "locks `commercial.licence_seat_allocation`" §RG9 | "licence seat" (L53) | — | **`core.user_account`** (`015:185`) |
| Audit trigger name | — | — | `trg_prevent_audit_tampering` (L43, L207) | `trg_prevent_audit_tampering` §RG7 | — | — | **`trg_prevent_audit_event_tampering`** (`012:290`) |
| Consultant trigger name | — | — | `trg_enforce_consultant_policy_restrictions` (L47, L141) | — | — | — | **`trg_enforce_consultant_openness`** (`016:130`) |
| Table count | "95" (L5) | — | "all 95 tables" (L164) | "95" implied | "95 tables/partitions" (L13) | — | **95** ✅ (92 standalone + 3 partitions) |
| RLS | — | — | "declarative RLS" as deployed (L10, §4) | — | — | — | **Not implemented** (0 policies) |
| DB roles | — | — | 3 roles as deployed (§3) | — | — | — | **Not implemented** (0 `CREATE ROLE`) |
| Index methods | — | — | "B-Tree and GIN" (L46) | — | — | — | **B-Tree + 2 GiST** (0 GIN) |
| Buffer residency | — | "100% resident" (L51) | — | — | — | "100%" hit ratio (L32) | **Hit ratio ≠ residency** |
| Constraint names cited | — | — | — | `ck_user_account_password_hash_format`, `ck_user_account_phone_e164`, `ck_job_posting_currency` — **none exist** | — | — | Actual: `ck_user_account_password_hash` (`002:56`), `ck_user_account_phone_format` (`002:31`), `ck_job_posting_salary_currency` (`008:114`) |
| Concurrency scale | — | "thousands" (L39) | — | — | — | — | **5-10 threads** |

### 6.3 Additional finding from `docs/rule-compliance.md` (in scope for Step 3 reconciliation)

**R-01 — §1 matrix row RG6 and §2 Rule Group 6 — cited constraint does not exist · CONTRADICTED · Confidence: HIGH**

> "**RG6** … Enforcing Mechanism: **CHECK constraint `ck_user_account_password_hash_format`**"
> "**Verification Logic**: `CHECK (password_hash IS NULL OR password_hash ~ '^\$(argon2id|2b|2a)\$')`"

`grep -rn "ck_user_account_password_hash_format" db/` → **no matches**. The actual constraint is `ck_user_account_password_hash` (`002:56-60`), a length check only. What actually implements the regex is a **runtime validator query** (`scripts/validate_data.py:210-220`). The compliance matrix therefore labels a data check as a schema constraint.

**R-02 — §1 matrix row RG3 — two cited constraint names do not exist · CONTRADICTED · Confidence: HIGH**

`ck_user_account_phone_e164` and `ck_job_posting_currency` are both absent. Actual names: `ck_user_account_phone_format` (`002:31`, regex `^\+[1-9]\d{1,14}$` — the *substantive* check the doc describes) and `ck_job_posting_salary_currency` (`008:114`, a combined salary/currency/period CHECK).

**R-03 — §1 matrix row RG7 — cited audit trigger name does not exist · CONTRADICTED · Confidence: HIGH**

`trg_prevent_audit_tampering` → actual `trg_prevent_audit_event_tampering` (`012:290`). `trg_prevent_wallet_ledger_tampering` ✅ correct.

**R-04 — §1 matrix row RG9 — "pessimistic locking on seat" · CONTRADICTED · Confidence: HIGH**

> "Function `core.create_session_with_device_limit` with `SELECT … FOR UPDATE`" / "Pessimistically locks `commercial.licence_seat_allocation` with `FOR UPDATE`."

The lock is on `core.user_account` (`015:185`). The *mechanism* (a `FOR UPDATE` pessimistic lock) is real and correct; only the *target table* is wrong.

**R-05 — §1 matrix row RG2 — the invariant is stated correctly here · VERIFIED · Confidence: HIGH — *keep as-is*

"**All operational** primary keys use `BIGINT GENERATED ALWAYS AS IDENTITY` named `id`", with §2 evidence explicitly carving out "or standard dimensional keys `date_key`, `job_posting_key` in OLAP marts". This is the accurate phrasing that `architecture.md:143` should adopt.

**R-06 — header line 4 — "100% COMPLIANT (15/15 Passed, 0 Failures, 0 Warnings)" · UNSUPPORTED (as a static claim) · Confidence: MEDIUM**

`scripts/validate_data.py` implements **13** `log_result` check sites across RG1-RG10 (RG1 ×2, RG2, RG3 ×3, RG4, RG5, RG6, RG7 ×2, RG8, RG9, RG10 ×2 = 15 result lines), but the "15/15 Passed" state is a **runtime observation of one dataset at one point in time**, not a static property. The header also calls it an "Automated 15-Check Harness" — `scripts/run_all_tests.py` does not invoke `validate_data.py` at all, so the claim is not re-verified by the main test runner. The number 15 is defensible; the absolute framing is not.

**R-07 — §2 Rule Group 7 — "Balance Reconciliation Proof … zero reconciliation discrepancies" · UNSUPPORTED (historical, source- and date-limited) · Confidence: MEDIUM**

The check itself is real (`validate_data.py:239-258`) and the query is correct. The "zero discrepancies" outcome is a **historical observation** of the seeded dataset at the time of the last validator run — there is no timestamp, no run log, and no artifact in the repository recording that run. It must be labelled as such rather than as a standing property. Note also that the reconciliation passes only because the seed and the test both set `balance` and the ledger consistently; nothing *enforces* it (see check 7 above).

**R-08 — §2 Rule Group 8 — quoted function output · UNSUPPORTED (unverifiable here) · Confidence: MEDIUM**

> "SELECT messaging.get_ui_translation('btn.apply_job', 'es'); -- Returns: 'Postularse para este puesto'"

The function exists (`018:56-90`) and the fallback logic is verified by inspection. The literal Spanish string, and the `ja` → English-fallback return, depend on the seeded `messaging.ui_translation` content. `db/migrations/018` seeds Spanish; the `ja` row's absence (or English presence) is a dataset property. `scripts/generate_data.py` seeds additional locales. I could not query the live table (L1), so the exact output strings are unverified here and should be labelled as expected values from the seeded dataset.

**R-09 — §2 Rule Group 10 — "successfully partitioned … with compound PK `(id, applied_at)`" · VERIFIED · Confidence: HIGH — *keep as-is*

`019:320-337` defines exactly that. This is the one partitioning statement in the corpus that is precisely correct.

**R-10 — §1 matrix row RG10 — "High-velocity applications partitioned by range" · VERIFIED as a schema fact, but the table is not the operational one · Confidence: MEDIUM**

The partitioned table exists as described. Whether "high-velocity applications" are *in* that table is a separate matter — today the operational application table is unpartitioned (`009:4`), and the partitioned table is a parallel structure with no query or trigger bound to it. Wording should make that explicit.

---

## 7. Verified Claims Worth Preserving

These held up under adversarial checking and must not be altered during correction. Listed so the correction pass does not damage them.

| # | Claim | Location | Evidence |
|:--|:--|:--|:--|
| V-01 | Anti-sentinel discipline: no `'NA'`/`'NONE'`/`'UNKNOWN'`/`'NULL'`/`9999`/`-1` stored sentinels | `architecture.md:146` | `grep` over `db/migrations/` → zero matches |
| V-02 | `btree_gist` exclusion constraint guarantees zero overlapping active gig assignments | `competitive-benchmark.md:13` | `014:316-321`; `btree_gist` at `014:8`; `tests/test_concurrency.py:126-228` |
| V-03 | `core.user_block` enforces user-OR-org blocks via XOR constraint | `competitive-benchmark.md:17` | `012` `ck_user_block_target_xor` + partial unique indexes |
| V-04 | `messaging.get_ui_translation` provides dynamic translation with English fallback | `competitive-benchmark.md:18`, `rule-compliance.md` §RG8 | `018:56-90` |
| V-05 | "95 tables" figure | `architecture.md:5`, `threat-model.md:164` | `grep -rn "CREATE TABLE" db/migrations/ \| wc -l` → 95 (92 standalone + 3 partitions) |
| V-06 | 10 schemas, exactly as named | `architecture.md:4` | `001_create_schemas.sql:10-19` — 10 `CREATE SCHEMA` statements |
| V-07 | `core` and `master` are FK-isolated from other schemas | `architecture.md:50-51` | `002` and `003` contain no `REFERENCES` outside their own schema |
| V-08 | Append-only triggers genuinely block UPDATE/DELETE on the three protected tables | `architecture.md:96-102`, `threat-model.md` §6.2 | `017:364-377,439-446`; `012:281-293` |
| V-09 | Correction accounting via self-referencing `correction_of_ledger_id` with a CHECK | `architecture.md:103` | `017:289,303,348-350` |
| V-10 | SCD-2 columns `valid_from`/`valid_to`/`is_current` on the dimensions | `architecture.md:110` | `019:60-62,84-86` |
| V-11 | Device-limit logic: default 2, licence-derived override, `device.limit_exceeded` audit write | `threat-model.md` §2/§3 | `015:179,188-200,220-240` |
| V-12 | Partitioned table's compound PK `(id, applied_at)` | `rule-compliance.md` §RG10 | `019:335-337` |
| V-13 | `messaging.get_ui_translation` is `STABLE` and three-tier | `architecture.md` §3.5 context, `competitive-benchmark.md:18` | `018:56-90` |
| V-14 | "All **operational** primary keys use `… AS IDENTITY` named `id`", with dimensional-key carve-out | `rule-compliance.md` §RG2 | `002` etc., plus `019:21,64,88,115` |
| V-15 | `commercial.wallet_ledger` index `idx_wallet_ledger_wallet_recorded` supports the reconciliation lookup | `performance-report.md` §4.3 context | `017:354-355` |

---

## 8. Prioritized Correction Plan (Step 5)

**Proposed changes only. Not applied — the three audited documents are unchanged pending review.** Each change is the minimal wording edit that makes the claim match the evidence. No change strengthens a performance claim beyond what the evidence supports.

### Priority 0 — Blockers: undeployed controls and compliance attestations

| ID | File · line | Current wording (abbrev.) | Proposed replacement | Rationale |
|:--|:--|:--|:--|:--|
| P0-1 | `competitive-benchmark.md:47` | "…**satisfying strict SOC 2 Type II** and financial audit compliance." | "…`BEFORE UPDATE OR DELETE` triggers (`trg_prevent_wallet_ledger_tampering`, `trg_prevent_audit_event_tampering`, `trg_prevent_download_history_tampering`) physically reject modification of recorded entries, and corrections use self-referencing debit/credit rows. *These controls support a financial-audit evidence trail; they do not by themselves constitute a compliance attestation.*" | T-C-01. A compliance attestation cannot rest on schema objects alone. |
| P0-2 | `threat-model.md:4` | "**Compliance Standards**: GDPR Article 25/32, SOC 2 Type II, PCI-DSS SAQ-A" | "**Target Compliance Framework** (alignment intent; no attestation performed): GDPR Article 25/32, SOC 2 Type II, PCI-DSS SAQ-A" | T-24. Separates target framework from achieved status. |
| P0-3 | `threat-model.md:10` + §4 heading | "…baked directly into PostgreSQL 17 via granular database roles, … declarative Row-Level Security (RLS) …" | "…via append-only ledgers, cryptographic hashing standards, and anti-tampering triggers. *Granular database roles and declarative Row-Level Security are proposed but not yet implemented (see §3 and §4).*" | T-01. The document's headline claim must not assert undeployed controls. |
| P0-4 | `threat-model.md:92` (§4 title) | "## 4. Row-Level Security (RLS) & Multi-Tenant Isolation" | "## 4. Row-Level Security (RLS) & Multi-Tenant Isolation — **PROPOSED DESIGN, NOT YET IMPLEMENTED**" + a lead sentence: "The policies below are a design proposal. No `ENABLE ROW LEVEL SECURITY` or `CREATE POLICY` statement exists in `db/migrations/` today, and the `app.current_user_id` / `app.current_org_id` session context they depend on is not set by any code in the repository." | T-01. Prevents a design from being read as a deployment. |
| P0-5 | `threat-model.md:53` (§3 title) | "Talentra enforces separation of duties through distinct PostgreSQL database user roles:" | "The following is a **proposed** role model. No `CREATE ROLE`/`GRANT` statement exists in `db/migrations/` today; the running instance has a single role, `talentra_admin`, created by `POSTGRES_USER` in `docker-compose.yml`, which holds SUPERUSER." | T-02. |
| P0-6 | `threat-model.md:60` | (grant without revoke) | insert after it: `-- Reclaim write access granted by the blanket grant above (a GRANT does not narrow an earlier GRANT)\nREVOKE UPDATE, DELETE ON TABLE commercial.wallet_ledger, commercial.candidate_profile_download_history FROM talentra_app;` | T-02(a). The proposed script must not itself contradict the immutability claim. |
| P0-7 | `threat-model.md:216-217` | "RPO **0 seconds**… RTO **< 15 minutes**… Patroni / pg_auto_failover… WAL archiving to S3" | "**Recovery Point Objective (RPO)**: one backup interval. The repository implements logical backups via `pg_dump` with a scripted restore-and-verify procedure (`scripts/backup_restore.sh`) that restores into a staging database and compares row counts across seven tables. *Synchronous streaming replication and PITR are production deployment requirements; no replica, `archive_mode`, or WAL-archiving job is configured in this repository.*\n**Recovery Time Objective (RTO)**: bounded by the measured restore duration, which `scripts/backup_restore.sh` reports against a 900-second threshold." | T-19. RPO 0 is a specific, currently-false claim. |

### Priority 1 — Contradicted factual errors

| ID | File · line | Proposed replacement | Finding |
|:--|:--|:--|:--|
| P1-1 | `architecture.md:89` | "…is partitioned by `RANGE (applied_at)` into **annual** partitions (`candidate_application_y2025`, `candidate_application_y2026`, `candidate_application_y2027` — one per calendar year)." | A-01 |
| P1-2 | `competitive-benchmark.md:51` | "…implements declarative **annual** range partitioning (`recruitment.candidate_application_partitioned`, one partition per calendar year)." | C-02 |
| P1-3 | `architecture.md:91` | "**Partition Pruning**: Queries filtering on `applied_at` prune partitions outside the requested range. *No benchmark query in `db/queries/` currently targets the partitioned table, so this behaviour is not exercised by the measured suite.*" | A-02 |
| P1-4 | `architecture.md:92` | "**Rolling Retention Lifecycle (future)**: Older partitions can be detached (`ALTER TABLE … DETACH PARTITION`) and archived to cold columnar storage. *No archival pipeline is implemented in this repository.*" | A-03 |
| P1-5 | `architecture.md:82` | "…acquires a row-level lock (`SELECT … FOR UPDATE`) on the **`core.user_account`** row of the user being logged in." | A-05 |
| P1-6 | `architecture.md:143` | "All **operational** tables use `BIGINT GENERATED ALWAYS AS IDENTITY` primary keys named `id`; the four `analytics.dim_*` dimensions use surrogate `*_key` keys, and `recruitment.candidate_application_partitioned` uses the compound `(id, applied_at)` primary key PostgreSQL requires for partition routing." | A-06 |
| P1-7 | `architecture.md:145` | "No column uses a timezone-naive `TIMESTAMP`; all instant-valued timestamps are `TIMESTAMPTZ` normalized to UTC. Calendar-date fields (employment and assignment windows, `analytics.dim_date.calendar_date`) are `DATE` by design." | A-07 |
| P1-8 | `architecture.md:144` | "Cross-schema foreign keys are used deliberately for referential integrity; schemas are logically separated by ownership, not by physical FK isolation." | A-09 |
| P1-9 | `threat-model.md:43,207` | `trg_prevent_audit_tampering` → `trg_prevent_audit_event_tampering` | T-03, T-18 |
| P1-10 | `threat-model.md:47` | `trg_enforce_consultant_policy_restrictions` → `trg_enforce_consultant_openness` (on `sourcing.consultant_sourcing_request`) | T-10 |
| P1-11 | `threat-model.md:46` | "All 12 operational queries backed by optimized **B-Tree** indexes, with **GiST** indexes backing two exclusion constraints (`ex_gig_assignment_no_overlap`, `ex_subscription_no_overlap`)." | T-06 |
| P1-12 | `threat-model.md:44` | "…capturing downloader user ID, organization ID, wallet ledger ID, and timestamp. *(IP address and user-agent are captured on `audit.audit_event`, which does not currently receive download events.)* Cannot be altered or deleted by `UPDATE`/`DELETE`; `TRUNCATE` is not blocked by a trigger." | T-04, T-05 |
| P1-13 | `threat-model.md:45` | "…`core.user_block` records block state; each querying statement must enforce it (see `db/queries/06_sourcing_outreach_unblocked.sql`). Database-level enforcement via RLS is proposed but not yet implemented. *Phone/email masking for unauthorized viewers is not currently implemented.*" | T-08, T-09 |
| P1-14 | `threat-model.md:164` | "Talentra classifies columns into four sensitivity tiers (Rule Group 6). The data dictionary currently documents **13 of 95 tables** as a representative sample; full coverage is outstanding." | T-13 |
| P1-15 | `threat-model.md:171` | "Salted password hash (**algorithm not enforced by schema**), SHA-256 document checksum, E.164 phone normalization" — and delete the "Tax: `XXXX-XX-4912`" example. | T-14 |
| P1-16 | `threat-model.md:178` | "Device-limit breaches and session revocations are recorded in `audit.audit_event` (`db/migrations/015_create_licences_and_device_limits.sql:221,317`). *Recording of logins, permission changes and profile unlocks is outstanding.*" | T-16 |
| P1-17 | `threat-model.md:181-191` | Replace the illustrative DDL with the actual column list from `012:230-242`. | T-17 |
| P1-18 | `competitive-benchmark.md:16` | "**Declarative Range Partitioning**: `RANGE (applied_at)` with annual intervals, applied to the prepared scale-out application table." | C-04 |
| P1-19 | `competitive-benchmark.md:39` | "PostgreSQL rejects conflicting temporal ranges at statement-execution time via the constraint's GiST index, raising `ExclusionViolation` (SQLSTATE 23P01) before commit. *Verified by `tests/test_concurrency.py` under 5-thread contention.*" | C-06 |
| P1-20 | `rule-compliance.md` §RG6, §RG3, §RG7, §RG9 | Correct the four cited names: `ck_user_account_password_hash_format` → `ck_user_account_password_hash` (+ note the regex lives in `scripts/validate_data.py:210-220`, not the schema); `ck_user_account_phone_e164` → `ck_user_account_phone_format`; `ck_job_posting_currency` → `ck_job_posting_salary_currency`; `trg_prevent_audit_tampering` → `trg_prevent_audit_event_tampering`; "locks `commercial.licence_seat_allocation`" → "locks the `core.user_account` row". | R-01..R-04 |

### Priority 2 — Unsupported claims needing qualification

| ID | File · line | Proposed replacement | Finding |
|:--|:--|:--|:--|
| P2-1 | `architecture.md:38` | "In Talentra, a single ACID transaction guarantees atomic consistency across these writes. *(No benchmark measures this cross-domain transaction; `recruitment.job_posting` tracks `vacancy_count` only and has no filled-headcount counter today.)*" | A-10, A-11 |
| P2-2 | `architecture.md:111` | "…refreshed by the `analytics.refresh_reporting_marts()` procedure (`REFRESH MATERIALIZED VIEW CONCURRENTLY`). *No scheduler invokes it automatically, and the analytics fact tables are populated only by the synthetic data loader.*" | A-04 |
| P2-3 | `architecture.md:119` | "For **production deployment**, the following PostgreSQL 17 engine parameters are **proposed**. *The repository's `docker-compose.yml` does not apply them; the benchmark artifact in `benchmarks/results/` was produced against stock PostgreSQL 17 defaults.*" | A-17 |
| P2-4 | `architecture.md:105` | Append: "— the wallet balance is a stored column; the schema records ledger entries immutably but does not itself derive or enforce the balance, so reconciliation is *checked* by `scripts/validate_data.py` and benchmark Query 05 rather than guaranteed by a constraint." | A-16 |
| P2-5 | `architecture.md:51,55,56` | Add the omitted tables: `master.industry`, `master.work_type`; `commercial.invoice`, `commercial.payment_order`, `commercial.payment_refund`, `commercial.candidate_profile_download_history`. | A-13..A-15 |
| P2-6 | `threat-model.md:42` | "Passwords are stored as salted hashes; `core.user_credential.algorithm` **defaults** to `argon2id` but the schema does not enforce the format, and hashing is performed by the application layer. Session tokens are stored as hashes in `core.user_session.session_token_hash` (length-constrained only)." | T-07 |
| P2-7 | `threat-model.md:12-34` | Annotate the diagram: mark RLS, database roles, and tax-ID encryption as *proposed*; relabel "SHA-256 Checksums" as "SHA-256 Document Checksums". | T-23 |
| P2-8 | `threat-model.md:42,46` | Verification column: cite `tests/test_concurrency.py` for the device-limit invariant; replace "`scripts/run_benchmarks.py`, Query 04" with "`tests/test_concurrency.py`, `tests/test_licences.sql`" (Query 04 returned zero rows in the measured run). | T-21, T-22 |
| P2-9 | `threat-model.md:222` | Replace the inline `pg_dump` snippet with a pointer to `scripts/backup_restore.sh` (and note that it drops and recreates a `talentra_recovery_test` database). | T-20 |
| P2-10 | `threat-model.md:47` | Narrow the "Tampering" row's attack vector to the ledger / audit / download-history tables, noting that candidate assessment scores are deliberately mutable. | T-11 |
| P2-11 | `threat-model.md:141-158` | Correct the §4.3 function body to `sourcing.enforce_consultant_openness()` with `v_is_open` / `IS NOT TRUE`, matching `016:110-133`. | T-01(c) |
| P2-12 | `threat-model.md:106,121,129` | Add a note that the `app.current_*` session context must be set by the application layer before these policies can be enabled. | T-01(a) |
| P2-13 | `threat-model.md:127` | Correct the correlation reference to `candidate_profile.user_account_id`. | T-01(b) |
| P2-14 | `threat-model.md:46` | "High-velocity applications have a prepared range-partitioned table (`recruitment.candidate_application_partitioned`); the operational application table is currently the unpartitioned `recruitment.candidate_application`." | T-12 |
| P2-15 | `competitive-benchmark.md:51` | "…Queries filtering on `applied_at` prune closed historical partitions. *No benchmark query currently targets the partitioned table, and the seeded rows populate a single partition; buffer-cache hit ratios in the benchmark artifact describe a warm dev dataset, not residency at scale.*" | C-03 |
| P2-16 | `competitive-benchmark.md:26` | Delete "in under 35 milliseconds", or restate as a design goal. | C-05 |
| P2-17 | `rule-compliance.md` header + §RG7/§RG8 | Mark the "100% COMPLIANT (15/15)" state as a **historical observation of the last validator run**, note that `scripts/run_all_tests.py` does not invoke `scripts/validate_data.py`, and label the RG8 function outputs as expected values from the seeded dataset. | R-06..R-08 |

### Priority 3 — Cross-document consistency and housekeeping

| ID | File · line | Proposed replacement | Finding |
|:--|:--|:--|:--|
| P3-1 | `competitive-benchmark.md` §1 matrix | Add a footnote to the matrix: the third-party columns are architectural characterisations, not independently verified claims; cite them if the document is used externally. | C-11 |
| P3-2 | `threat-model.md` §2/§5/§7 | Add a short "Scope and Limitations" note: which controls are implemented vs proposed; that `TRUNCATE` and privileged actions are outside trigger reach; that no attestation has been performed. | T-24, T-05, T-29 |
| P3-3 | `docs/data-dictionary.md:4,11,15` | Header "95 … Tables" → "95 Tables (92 standalone + 3 partitions) and 2 Materialized Views"; "Every column in Talentra is tagged" → "Columns in the 13 documented tables are tagged; full coverage is outstanding"; "encrypted tax IDs" → remove (no such column). | T-13, T-14 |
| P3-4 | `architecture.md:5` | Optional: "95 Tables (92 standalone + 3 partitions) and 2 Materialized Views, across 10 Schemas". | A-12 |
| P3-5 | `docs/performance-report.md` §1 note | Add: "Measured on 2026-10-17 (methodology v1) against a synthetic dev dataset on stock PostgreSQL 17 defaults." | A-17, L2 |

### Not proposed (deliberately)

- **No new performance claims.** Nothing in the correction plan introduces a latency, throughput, or pruning figure that the repository does not already evidence.
- **No implementation proposals.** P0-3/P0-4/P0-5/P0-6 reframe design as design. Implementing RLS and database roles is a **separate phase** requiring owner approval and schema changes, which are outside this phase's safety boundaries.
- **No change to `docs/performance-report.md` §2's corrected diagnostic table** (already correct in the working tree).
- **No change to any migration, index, constraint, query, or test file.**

---

## 9. Items Requiring External Evidence

These cannot be settled inside this repository and are explicitly *not* asserted either way in the correction plan.

| # | Item | Where claimed | What would settle it |
|:--|:--|:--|:--|
| E-1 | SOC 2 Type II status | `competitive-benchmark.md:47`; `threat-model.md:4` | An auditor's report and the observation-period scope. Until then, no compliance status may be stated. |
| E-2 | PCI-DSS SAQ-A status and "zero-storage compliance" | `threat-model.md:4`; `integration-boundaries.md:46,72` | The SAQ-A eligibility statement and the payment-gateway data-flow documentation. *Note*: the repository does support the *architectural* premise — no PAN/CVV/card-number column exists in any migration (verified by grep). |
| E-3 | GDPR Article 25/32 alignment | `threat-model.md:4` | A DPIA / records-of-processing entry; control mapping for consent, minimisation, and erasure. |
| E-4 | RPO 0 / synchronous replication / PITR / Patroni | `threat-model.md:216-217` | Deployment configuration: a standby, `synchronous_standby_names`, `archive_mode`/`archive_command`, and a failover runbook. |
| E-5 | "100% buffer-cache residency" at scale | `competitive-benchmark.md:51`; `architecture.md:91` | A measurement against a production-scale working set, not a dev-dataset hit ratio. |
| E-6 | Third-party (Naukri / Monster / LinkedIn) architecture claims | `competitive-benchmark.md` §1, §2 | Published architecture documentation or first-party sources, cited per claim. |
| E-7 | "thousands of concurrent booking attempts" | `competitive-benchmark.md:39` | A load test at that concurrency, or restatement to the tested 5-thread scale. |
| E-8 | Live PostgreSQL settings on the running container | `architecture.md:119-137` | A `pg_settings` read on the target deployment. Blocked here (L1). |
| E-9 | "under 35 milliseconds" unified cross-pool discovery | `competitive-benchmark.md:26` | A benchmark of a query that actually joins both talent pools. |
| E-10 | Current validity of the 2026-10-17 benchmark artifact | `README.md` §5, `performance-report.md` §1 | A fresh methodology-v2 run. The current figures are **historical** and must be labelled as such. |

---

## 10. Items Requiring Owner Approval

| # | Decision | Why it needs the owner | Options |
|:--|:--|:--|:--|
| O-1 | **RLS: implement or reframe?** | Implementing `ENABLE ROW LEVEL SECURITY` + policies is a schema change — outside this phase's safety boundaries, and the policies as drafted are not deployable (T-01a, T-01b). | (a) Reframe §4 as a proposed design *now* and schedule implementation; (b) schedule an implementation phase that also fixes the session-context and correlation defects. |
| O-2 | **Database roles: implement or reframe?** | `CREATE ROLE`/`GRANT` is a security-sensitive schema-level change; the `talentra_admin` superuser posture is a live concern (T-27). | (a) Reframe §3 as proposed; (b) schedule role provisioning with a least-privilege grant script. |
| O-3 | **Compliance header wording** | Whether the project wants to name SOC 2 / PCI-DSS / GDPR at all in these documents, and in what framing. | (a) "Target Compliance Framework"; (b) remove the frameworks entirely; (c) supply external evidence (E-1..E-3) and keep the current wording. |
| O-4 | **`competitive-benchmark.md` external audience** | The named-competitor claims (C-11) and the legacy-failure framing are appropriate for an internal dossier but risky externally. | (a) keep as internal-only; (b) add citations and soften the framing; (c) restrict distribution. |
| O-5 | **Scope of the audit doc family** | `docs/rule-compliance.md`, `docs/data-dictionary.md`, `docs/integration-boundaries.md` and `docs/performance-report.md` all carry findings of the same class (R-01..R-08, P3-3, P3-5). Correcting only the three audited files leaves the corpus inconsistent. | (a) extend the correction pass to those four files; (b) keep the pass to the three audited files and record the rest as a follow-up. |
| O-6 | **Table-count label** | "95 tables" is numerically correct but the label "Operational, Dimensional, and Partitioned" double-counts partitions. Changing it ripples into `README.md:13`, `data-dictionary.md:4`, `threat-model.md:164`. | (a) leave the number and adjust the label only where audited; (b) adopt the precise label everywhere. |
| O-7 | **DR claims** | Whether the project intends synchronous replication / PITR as a real deployment target. | (a) document the actual `pg_dump`-based mechanism (P0-7); (b) schedule the replication/PITR work and keep the target stated. |
| O-8 | **Dangling reference in `README.md:187`** | The edited `README.md` points at `docs/phase2c-benchmark-correction-report.md` §4, which does not exist. `README.md` is outside the three audited documents, so it was not edited. | (a) create the Phase 2C benchmark-correction report; (b) retarget the pointer to a section of this audit document; (c) remove the pointer. |

---

## 11. Audit Completion Statement

**The three audited documents — `docs/architecture.md`, `docs/competitive-benchmark.md`, `docs/threat-model.md` — were NOT modified.** All three remain byte-identical to commit `7ac5b2b`, as confirmed by `git status --short` and by `git diff --stat` returning empty for all three paths.

This report was produced read-only: no schema, index, constraint, migration, or data change; no `INSERT`/`UPDATE`/`DELETE`/`TRUNCATE`/`DROP`/`RESET`; no database rebuild; no benchmark run; no data generation; no `EXPLAIN ANALYZE`; nothing staged, committed, or pushed. `tests/test_constraints.sql` (user-owned) and `.git-initial-backup/` were both left untouched.

The only file created in this phase is this report: `docs/phase2c-documentation-audit.md` (untracked). The correction plan in §8 is a **proposal only** — no audited document was edited.
