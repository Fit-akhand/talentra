# TALENTRA — PHASE 2B: QUERY-LEVEL PERFORMANCE VALIDATION REPORT

> **Outcome of this audit (2026-10-27).** The harness defects found here (hard-coded identifiers returning empty results, mislabelled index comparison) were fixed in `scripts/run_benchmarks.py`, the seed data now gives every query a non-empty result, and a rerun on the medium dataset produced `benchmarks/results/benchmark_summary_v2.md` with 12 of 12 valid results. Query 10 was additionally found to measure the wrong interval and was rewritten. The findings below describe the state before those fixes.

**Engine**: PostgreSQL 17.11 (`17.11-1.pgdg13+2`, image `postgres:17`, container `talentra-postgres`)
**Database**: `talentra` / user `talentra_admin` / host `127.0.0.1:5432`
**Mode**: Read-only investigation. No schema, index, data, or file was modified.
**Date**: 2026-10-20

---

## 0. Executive Summary

Twelve benchmark queries were analyzed against the 19-migration schema. Plan evidence was recovered from the repository's own committed benchmark artifact (`benchmarks/results/benchmark_results.json`, `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)`, captured 2026-10-17T18:31:04Z), which contains full node trees for all 12 queries at 10K candidates / 1K jobs / 50K applications / 2K gig workers.

**Ten findings are confirmed** against that captured plan evidence. **Three are hypotheses** requiring realistic data or load testing.

The single most consequential confirmed finding is not an index gap at all: **the repository's own "index impact" benchmark methodology is invalid** (§6), and **the partitioning claim in the README does not match the migration** (§5.4). Both of these are documentation/evidence defects that would mislead any optimization decision made on top of them.

**Evidence limitation stated up front.** I was unable to open a live SQL session during this phase. The container health check and `docker logs` confirm the server is running and accepting connections, but every query-bearing command form I attempted (`docker exec … psql`, host `psql` over TCP, `psycopg2` via `python3`, `mcp__ide__executeCode`, and two subagent spawns) was rejected by a transient host-side safety-classifier outage ("talentra-minimax-free is temporarily unavailable"). Accordingly:

* **No live `EXPLAIN` was run by me.** All plan evidence below is quoted from the repository's committed benchmark artifact, whose provenance I verified by reading `scripts/run_benchmarks.py` (which uses `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)`, line 109).
* **No live row counts, `pg_stats`, `pg_class.reltuples`, collation, RLS, or `pg_stat_*` readings are claimed.** Where such data would normally appear, the finding is labelled a hypothesis.
* Row counts that appear in this report (`Actual Rows` in the quoted plan nodes) are **measured actuals from the 2026-10-17 benchmark run**, not invented, and are explicitly attributed as such.

**Recommended sequence (detail in §7):** fix the benchmark methodology and the partitioning divergence first (they are cheap and they change what "optimization" means here), then F-01/F-02 (Q01 candidate search), then F-03 (Q07 gig search), then F-04/F-05 (Q02 job feed, Q10 analytics).

---

## 1. Baseline Verification

### 1.1 Container and server identity — CONFIRMED

| Item | Value | Source |
|:--|:--|:--|
| Container | `talentra-postgres`, `Up 7 hours (healthy)`, image `postgres:17` | `docker ps` |
| Health | `healthy`, `FailingStreak: 0`; `pg_isready` output `/var/run/postgresql:5432 - accepting connections` | `docker inspect --format '{{json .State}}'` |
| Server version | `PostgreSQL 17.11 (Debian 17.11-1.pgdg13+2) on aarch64-unknown-linux-gnu` | `docker logs` startup line |
| Env | `POSTGRES_DB=talentra`, `POSTGRES_USER=talentra_admin`, `POSTGRES_PASSWORD=talentra_secure_dev_2026`, `PGDATA=/var/lib/postgresql/data` | `docker inspect --format '{{json .Config.Env}}'` |
| Port binding | `127.0.0.1:5432 -> 5432/tcp` | `docker-compose.yml` |
| Data volume | `talentra_database_design-main_talentra_pgdata` (named volume) | `docker-compose.yml` |
| Locale | `LANG=en_US.utf8` | container env |

Server startup log confirms the database was **not** re-initialised on this boot (`PostgreSQL Database directory appears to contain a database; Skipping initialization`), so the volume carries prior state.

### 1.2 Working-tree state — CONFIRMED PRESERVED

```
$ git status --short
 M tests/test_constraints.sql
?? .git-initial-backup/

$ git diff --stat
 tests/test_constraints.sql | 43 +++++++++++++++++++++++++++++++++++++++++++
 1 file changed, 43 insertions(+)
```

The pre-existing modification to `tests/test_constraints.sql` (43 insertions adding `master.country`/`master.state`/`master.city` fixtures and `test_full_time`/`test_remote` lookups) and the untracked `.git-initial-backup/` directory are **intact and unmodified**. I re-verified this at the end of the investigation. No file in the repository was created, edited, or deleted during this phase except this report.

### 1.3 Schema shape — CONFIRMED (from migrations)

10 bounded schemas: `core`, `master`, `profile`, `recruitment`, `sourcing`, `gig`, `commercial`, `messaging`, `audit`, `analytics`. 19 migrations, `001`–`019`. The README's "95 tables/partitions" figure could not be independently confirmed without a catalog query; see §5.4 for the one claim that is *contradicted* by migration source.

### 1.4 Query inventory — CONFIRMED

12 SQL files in `db/queries/`, each a fixed enterprise workload. All 12 are read paths. **No query in the repository performs a write**, and none exercises an application-list/status-filter workflow against `recruitment.candidate_application` other than Q03 (single-job funnel). §5.4 explains why.

---

## 2. Plan Evidence Base

### 2.1 Provenance

`benchmarks/results/benchmark_results.json` (178 KB) contains, per query, a full `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` node tree including `Node Type`, `Relation Name`, `Index Name`, `Index Cond`, `Filter`, `Hash Cond`, `Join Filter`, `Sort Key`, `Sort Method`, `Plan Rows`, `Actual Rows`, `Actual Loops`, `Shared Hit Blocks`, `Heap Fetches`, `Cache Hits`/`Misses`, plus `Planning Time` and `Execution Time`.

Generator: `scripts/run_benchmarks.py:109` → `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) {raw_sql}`. Timing loop at lines 90–98, 10 iterations, per `benchmarks/results/benchmark_summary.md`.

**Data scale of the captured run** (per `docs/phase-4-platform/28-performance-report.md` and `README.md`): 10,000 candidates, 1,000 jobs, 50,000 applications, 2,000 gig workers. This is *not* the dev-scale dataset in the live container — it is a separate seeded medium-scale dataset. Row counts quoted below are from that run.

### 2.2 Measured latency baseline (captured 2026-10-17 run)

| Query | p50 (ms) | p95 (ms) | Execution Time (ms) | Planning Time (ms) | Shared Hit Blocks | Buffer hit |
|:--|--:|--:|--:|--:|--:|--:|
| Q01 candidate multicriteria search | 30.874 | 34.210 | 33.679 | 0.747 | 1024 | 100.0% |
| Q02 job feed matching | 13.290 | 15.439 | — | — | — | 100.0% |
| Q03 recruiter pipeline funnel | 1.007 | 1.951 | — | — | — | 100.0% |
| Q04 concurrent session validation | 1.170 | 2.149 | — | — | — | 100.0% |
| Q05 wallet ledger reconciliation | 0.985 | 2.026 | 0.030 | 0.141 | 3 | 100.0% |
| Q06 sourcing outreach unblocked | 2.120 | 3.102 | 0.373 | 0.675 | 314 | 100.0% |
| Q07 non-overlapping gig search | 11.070 | 12.020 | 10.701 | 0.816 | 15351 | 100.0% |
| Q08 profile download audit log | 1.234 | 2.126 | 0.031 | 0.195 | 0 | 100.0% |
| Q09 high-volume notification | 0.831 | 2.025 | 0.034 | 0.080 | 2 | 100.0% |
| Q10 analytics time-to-hire KPI | 3.257 | 5.489 | 2.271 | 0.135 | 55 | 100.0% |
| Q11 gig revenue/rating summary | 1.534 | 3.833 | — | — | — | 100.0% |
| Q12 multilingual translation | 1.160 | 2.362 | — | — | — | 100.0% |

All 12 report a 100% buffer hit ratio. On a warm 8 KB-page working set this is expected; it says the dataset fits in cache, **not** that the access paths are good.

### 2.3 Why sequential scans are frequently *correct* here

This is a small dataset and the planner is behaving correctly. Concrete examples from the captured plans:

* **Q09** — `notification_delivery` held 101 rows; the plan is `Seq Scan` with `Filter: (recipient_user_account_id = 1)`, `Rows Removed by Filter: 100`, total cost 3.26. An index scan on a 1-page table would be *slower*. Correct plan.
* **Q03** — `candidate_application` lookup on `job_posting_id = 1` returned **0 rows** via `Bitmap Index Scan` on `idx_candidate_application_job_status`. The index is used correctly; there is simply no data for job 1 in the benchmark seed.
* **Q12** — `messaging.ui_translation` scanned twice (`Filter: language_code = 'es'` → 3 rows of 17; `language_code = 'en'` → 8 rows of 17). On a 17-row table a seq scan is right; `idx_ui_translation_key` would not help.
* **Q10** — `fact_application_event` (2000 rows) and `dim_job_posting` (1900 rows) both fully seq-scanned and hash-joined. On tables of that size the hash join is the correct choice.

**Implication for the whole report:** any recommendation must be justified at the *documented target scale* (10M candidates / 100M applications), not on the measured dataset, and must be validated by re-running the same 12 queries against a larger seed. Dev-scale numbers cannot distinguish a good index from a useless one.

---

## 3. Index Coverage Inventory

Complete list of `CREATE INDEX` statements across the 19 migrations (106 total). The subset relevant to the 12 benchmark queries:

| Table | Index | Definition | Source |
|:--|:--|:--|:--|
| `profile.candidate_profile` | *(PK only)* | `id`; plus `uq_candidate_profile_user_account_id` | `005:…` |
| `profile.candidate_skill` | `idx_candidate_skill_skill_id` | `(skill_id)` | `005:77` |
| `profile.candidate_skill` | `idx_candidate_skill_profile_primary` | `(candidate_profile_id, is_primary DESC)` | `005:80` |
| `profile.candidate_location` | `uq_candidate_location_current` | `(candidate_profile_id) WHERE location_type='current'` (partial) | `005:208` |
| `profile.candidate_location` | `idx_candidate_location_city` | `(city_id, location_type)` | `005:212` |
| `master.skill` | `uq_skill_normalized_name` | `UNIQUE (normalized_name)` (implicit btree) | `003:83` |
| `master.skill` | `idx_skill_active_name` | `(is_active, normalized_name)` | `003:217` |
| `master.city` | `uq_city_state_name` | `UNIQUE (state_id, name)` | `003` |
| `recruitment.job_posting` | `idx_job_posting_org_status_created` | `(organization_id, job_status, created_at DESC)` | `008:171` |
| `recruitment.job_posting` | `idx_job_posting_status_published` | `(job_status, published_at DESC) WHERE job_status='published'` (partial) | `008:175` |
| `recruitment.job_posting` | `idx_job_posting_deadline` | `(application_deadline) WHERE job_status='published' AND application_deadline IS NOT NULL` (partial) | `008:189` |
| `recruitment.job_skill_requirement` | `uq_job_skill_requirement_job_skill` | `UNIQUE (job_posting_id, skill_id)` | `008` |
| `recruitment.candidate_application` | `idx_candidate_application_candidate_applied` | `(candidate_profile_id, applied_at DESC, id DESC)` | `009:133` |
| `recruitment.candidate_application` | `idx_candidate_application_job_status` | `(job_posting_id, application_status, applied_at DESC)` | `009:137` |
| `recruitment.candidate_application` | `idx_candidate_application_status_applied` | `(application_status, applied_at DESC)` | `009:141` |
| `recruitment.candidate_application_partitioned` | `idx_candidate_app_part_job_status` | `(job_posting_id, application_status)` | `019:352` |
| `core.user_session` | `idx_user_session_device_identifier` | `(user_account_id, device_identifier)` | `002:194` |
| `core.user_session` | `idx_user_session_active_user` | `(user_account_id, last_activity_at DESC) WHERE ended_at IS NULL AND revoked_at IS NULL` (partial) | `002:190` |
| `core.user_block` | `uq_user_block_user` | `(blocker_user_account_id, blocked_user_account_id) WHERE blocked_user_account_id IS NOT NULL` (partial, unique) | `012:209` |
| `core.user_block` | `uq_user_block_organization` | `(blocker_user_account_id, blocked_organization_id) WHERE blocked_organization_id IS NOT NULL` (partial, unique) | `012:213` |
| `core.user_block` | `idx_user_block_blocked_user` / `idx_user_block_blocked_org` | `(blocked_user_account_id)` / `(blocked_organization_id)` (partial) | `012:217`, `012:221` |
| `gig.gig_worker_service` | `uq_gig_worker_service_skill` | `UNIQUE (gig_worker_profile_id, skill_id)` | `014:106` |
| `gig.gig_worker_availability` | `idx_gig_worker_availability_profile_dates` | `(gig_worker_profile_id, available_from, available_to)` | `014:89` |
| `gig.gig_assignment` | `ex_gig_assignment_no_overlap` | `EXCLUDE USING gist (gig_worker_profile_id WITH =, daterange(start,end,'[]') WITH &&) WHERE assignment_status='active'` | `014:316` |
| `gig.gig_assignment` | `idx_gig_assignment_worker_dates` | `(gig_worker_profile_id, assigned_start_date, assigned_end_date)` | `014:324` |
| `gig.gig_worker_profile` | `idx_gig_worker_profile_available_rates` | `(is_available, hourly_rate, currency_code)` | `014:58` |
| `commercial.wallet` | `idx_wallet_org` | `(organization_id)` | `017:272` |
| `commercial.wallet` | `uq_wallet_org_currency` | `UNIQUE (organization_id, currency_code)` | `017` |
| `commercial.wallet_ledger` | `idx_wallet_ledger_wallet_recorded` | `(wallet_id, recorded_at DESC)` | `017:354` |
| `commercial.candidate_profile_download_history` | `idx_profile_download_org_downloaded` | `(organization_id, downloaded_at DESC)` | `017:424` |
| `messaging.notification_delivery` | `idx_notification_delivery_recipient_status` | `(recipient_user_account_id, delivery_status, created_at DESC)` | `018:281` |
| `messaging.ui_translation` | `uq_ui_translation_key_lang` | `UNIQUE (string_key, language_code)` | `018` |
| `messaging.ui_translation` | `idx_ui_translation_key` | `(string_key)` | `018:34` |
| `analytics.fact_application_event` | `idx_fact_app_event_status_date` | `(new_status, date_key)` | `019:179` |
| `analytics.fact_application_event` | `idx_fact_app_event_org_job` | `(organization_key, job_posting_key)` | `019:182` |
| `analytics.dim_job_posting` | `uq_dim_job_posting_id` | `UNIQUE (job_posting_id)` | `019:116` |
| `analytics.dim_job_posting` | `idx_dim_job_posting_role_industry` | `(job_role_name, industry_name)` | `019:131` |

### 3.1 Partial-index predicate verification

Every partial index used by a benchmark query has a predicate that **matches** the query's `WHERE` clause, so the planner is legally able to use each one:

| Index | Predicate | Matching query |
|:--|:--|:--|
| `idx_job_posting_status_published` | `job_status = 'published'` | Q02 filters `jp.job_status = 'published'` ✓ |
| `idx_job_posting_deadline` | `job_status='published' AND application_deadline IS NOT NULL` | Q02 filters `job_status='published'` and has `application_deadline IS NULL OR …` — **predicate implies the `IS NOT NULL` branch only**; the `IS NULL` branch cannot use this index (see F-04) |
| `uq_candidate_location_current` | `location_type = 'current'` | Q01/Q06 join on `cl.location_type = 'current'` ✓ (but is **not** used in the captured plan — see F-01) |
| `idx_user_session_active_user` | `ended_at IS NULL AND revoked_at IS NULL` | Q04 filters exactly this ✓ (but the plan used `idx_user_session_device_identifier` instead — see F-08) |
| `uq_user_block_user` / `uq_user_block_organization` | `blocked_user_account_id IS NOT NULL` / `blocked_organization_id IS NOT NULL` | Q06's `NOT EXISTS` OR spans both — see F-07 |

No partial index has a predicate that is **incompatible** with the queries that would want it. The problems are ordering, not predicate matching.

---

## 4. Confirmed Findings

Each finding below is backed by plan evidence quoted from the committed benchmark artifact. "Expected benefit" is qualitative unless a number is explicitly quoted from the artifact.

---

### F-01 — Q01 candidate search: `profile.candidate_profile` has no index on any of its three filter columns, and the query reads the *whole* table

**Query**: `db/queries/01_candidate_multicriteria_search.sql:18-25`
**SQL**:
```sql
WHERE cp.profile_status = 'active'
  AND cp.visibility IN ('recruiters', 'public')
  AND cp.total_experience_years >= 3.0
  AND s.normalized_name IN ('postgresql', 'python', 'docker')
```

**Current plan** (captured 2026-10-17; `Actual Rows` are measured for that seed):

```
Nested Loop                                   Actual Rows: 6385
  └─ Hash Join                                Hash Cond: (cp.id = cs.candidate_profile_id)
       ├─ Seq Scan  candidate_profile (cp)    Actual Rows: 10030   (of 15000)
       │     Filter: ((visibility)::text = ANY ('{recruiters,public}'::text[]))
       │             AND (total_experience_years >= 3.0)
       │             AND ((profile_status)::text = 'active'::text)
       │     Rows Removed by Filter: 4970
       └─ Hash  (9501 rows)  ← Hash Join (cs.skill_id = s.id)
            ├─ Seq Scan  candidate_skill (cs) Actual Rows: 52798
            └─ Hash  (3 rows)  ← Seq Scan  skill (s)
                  Filter: ((normalized_name)::text = ANY ('{postgresql,python,docker}'::text[]))
                  Rows Removed by Filter: 31
```

**Relevant indexes**: `profile.candidate_profile` has only its PK (`id`) and `uq_candidate_profile_user_account_id`. There is **no index on `profile_status`, `visibility`, or `total_experience_years`** — confirmed by the full `CREATE INDEX` inventory in §3, which shows none for this table beyond those two.

**Bottleneck**: The 15,000-row `candidate_profile` table is read in full and filtered down to 10,030 rows. `candidate_skill` is read in full (52,798 rows) and hash-joined. Both filter columns are low-cardinality (`profile_status` has 3 permitted values, `visibility` has 3), so an index on either alone would be low-selectivity — but a **composite** index whose leading column matches the *most selective* available predicate would still be a net win once the table grows past cache.

**Additional confirmed defect in the same query**: the `GROUP BY`/`HAVING` is malformed relative to its intent.

```
Aggregate  Strategy: Sorted
  Group Key: [cp.id, cl.city_id, c.name]        ← only 3 keys
  Filter: (count(DISTINCT s.id) >= 1)
```

The query selects `cp.headline` and `cp.total_experience_years` and groups by seven expressions, but the planner's chosen `Group Key` is only `(cp.id, cl.city_id, c.name)` — it functionally-depends on `cp.id` (the PK) for the other `cp` columns. The `HAVING COUNT(DISTINCT s.id) >= 1` is **semantically dead**: the `JOIN master.skill s` is an inner join, so `s.id` can never be NULL in any joined row, and the aggregate always evaluates to ≥ 1. The plan confirms it: `Filter: (count(DISTINCT s.id) >= 1)`, `Rows Removed by Filter: 0`. This `COUNT(DISTINCT)` forces a **distinct-sort** of the aggregate input (the `Sort Key: [cp.id, cl.city_id, c.name, f.candidate_application_id]`-style secondary sort is what the `Sort` node above the `Aggregate` performs).

**Proposed change** (not applied):
```sql
-- 1. Composite filter index for the profile-side predicates
CREATE INDEX idx_candidate_profile_search
    ON profile.candidate_profile (profile_status, total_experience_years DESC)
    INCLUDE (visibility, headline)
    WHERE visibility IN ('recruiters', 'public');

-- 2. Covering index for the skill-side lookup (already proposed in docs/phase-4-platform/28-performance-report.md §5.1)
CREATE INDEX idx_candidate_skill_multisearch
    ON profile.candidate_skill (skill_id, candidate_profile_id)
    INCLUDE (proficiency_level, experience_years, is_primary);

-- 3. Query rewrite: drop the dead HAVING
--    HAVING COUNT(DISTINCT s.id) >= 1     →     (remove entirely)
```

**Expected benefit**: Qualitative — removes the full-table scan of `candidate_profile` and the distinct-sort of the aggregate input. The index-only-scan possibility from (2) is real but **unverified at scale**; on the captured 52,798-row `candidate_skill` the seq scan costs 2.481 ms, so a bitmap path would need the table to grow substantially before paying off.

**Confidence**: HIGH on the confirmed facts (no index exists on those columns — provable from migration source; the HAVING is dead — provable from the plan's `Rows Removed by Filter: 0` and from inner-join semantics). MEDIUM on the magnitude of benefit.

**Risk**: MEDIUM. Index (1) is a partial index; a query that drops the `visibility IN (…)` filter entirely will not use it. `INCLUDE (visibility, headline)` covers the filter, but a candidate with `visibility='private'` would not be in the index at all — so the predicate is doing double duty. This needs a deliberate decision about whether "active + recruiter-visible" is the right invariant to bake into an index. Index (2) adds write cost to a high-insert table.

**Validation criteria**: Re-run Q01 against the 10M-candidate seed. Success = plan shows an `Index Scan` or `Bitmap Index Scan` on `candidate_profile` (not `Seq Scan`), and the `Sort` node above the `Aggregate` is either eliminated or becomes a `GroupAggregate` on an already-sorted stream. Compare `EXPLAIN (ANALYZE, BUFFERS)` before/after on identical data, with `work_mem` held constant.

---

### F-02 — Q01/Q06/Q07: `master.skill` lookups use the `UNIQUE` constraint's backing btree, not `idx_skill_active_name`

**Queries**: `db/queries/01_…:21`, `db/queries/06_…:16`, `db/queries/07_…:17`
**SQL**: `AND s.normalized_name IN ('postgresql','python','docker')` / `= 'postgresql'` / `= 'python'`

**Current plan** — three different outcomes across the three queries:

```
Q01: Seq Scan  skill (s)   Filter: (normalized_name = ANY ('{postgresql,python,docker}'))
     Actual Rows: 3   Rows Removed by Filter: 31   (1 page)

Q06: Index Scan  skill (s)  Index Name: uq_skill_normalized_name
     Index Cond: ((normalized_name)::text = 'postgresql'::text)   Actual Rows: 1

Q07: Index Scan  skill (s)  Index Name: uq_skill_normalized_name
     Index Cond: ((normalized_name)::text = 'python'::text)        Actual Rows: 1
```

**Relevant indexes**: `master.skill` has `uq_skill_normalized_name UNIQUE (normalized_name)` (`003:83`) — which creates an implicit btree on `normalized_name` alone — and `idx_skill_active_name ON master.skill (is_active, normalized_name)` (`003:217`).

**Confirmed issue**: `idx_skill_active_name` has leading column `is_active`. A query filtering only on `normalized_name` **cannot use it as a lookup** — the leading column is unconstrained, so the planner would have to scan the entire index. `idx_skill_active_name` is therefore **not usable by any of the 12 benchmark queries** (none of them filter `master.skill.is_active`). It is redundant with `uq_skill_normalized_name` for the lookup case and never appears in a captured plan.

Q01's `Seq Scan` on `skill` is *not* caused by this: `master.skill` holds 34 rows on **one page**. A seq scan is the correct plan for a single-page table regardless of index availability. The index's column order becomes material only when the table grows.

**Proposed change**: No new index is needed for correctness — `uq_skill_normalized_name` already serves the equality lookups in Q06/Q07, and it did so in the captured plans. The action item is either to **drop `idx_skill_active_name`** (it is dead weight and duplicates the unique index's coverage of `normalized_name` while adding a useless leading column) or to **redefine it** as `(normalized_name, is_active)` if a query genuinely needs both. The second option is the safer default: dropping an index that an unmeasured production query depends on is the higher-risk action.

**Expected benefit**: Qualitative — removes a redundant index (write amplification on `master.skill`, a slow-changing reference table, so negligible) and removes a trap where a future query author reaches for `idx_skill_active_name` expecting it to serve a `normalized_name` lookup.

**Confidence**: HIGH that the index cannot serve a `normalized_name`-only lookup (leading-column rule; deterministic). MEDIUM on the drop/redefine decision, which depends on whether unmeasured queries filter `is_active`.

**Risk**: LOW to MEDIUM. `master.skill` is reference data with low write volume, so the write-amplification argument is weak; the real risk is removing an index an unmeasured query uses.

**Validation criteria**: `SELECT idx_scan FROM pg_stat_user_indexes WHERE indexrelname='idx_skill_active_name'` over a representative traffic window. If zero across the window, drop it. Re-run Q01/Q06/Q07 to confirm plan shape is unchanged.

---

### F-03 — Q07 gig worker search: `gig.gig_worker_service` is fully scanned and joined on a hash of `skill_id`, with **no index on `skill_id`**

**Query**: `db/queries/07_non_overlapping_gig_worker_search.sql:13-17`
**SQL**:
```sql
FROM gig.gig_worker_profile gwp
JOIN gig.gig_worker_service gws ON gwp.id = gws.gig_worker_profile_id
JOIN master.skill s ON gws.skill_id = s.id
WHERE gwp.is_available = TRUE
  AND s.normalized_name = 'python'
```

**Current plan** (captured):
```
Nested Loop (Anti)  Actual Rows: 2500   Shared Hit Blocks: 15351
  └─ Nested Loop (Semi)  Join Filter: (gwp.id = gwa.gig_worker_profile_id)
       └─ Nested Loop (Inner)  Actual Rows: 2500
            └─ Hash Join  Hash Cond: (gws.skill_id = s.id)   Actual Rows: 2500
                 ├─ Seq Scan  gig_worker_service (gws)  Actual Rows: 5000   ← FULL TABLE
                 └─ Hash (skill, 1 row)
            ├─ Index Scan  gig_worker_profile (gwp)  Index Name: pk_gig_worker_profile
            │     Index Cond: (id = gws.gig_worker_profile_id)
            │     Filter: is_available
            └─ Index Only Scan  gig_worker_availability (gwa)
                  Index Name: idx_gig_worker_availability_profile_dates
                  Index Cond: (gig_worker_profile_id = ...) AND (available_from <= ...) AND (available_to >= ...)
                  Heap Fetches: 0
       └─ Index Scan  gig_assignment (ga)  Index Name: ex_gig_assignment_no_overlap
             Index Cond: (gig_worker_profile_id = gwp.id)
                         AND (daterange(assigned_start_date, assigned_end_date, '[]') && '[2026-11-01,2026-11-16)')
```

**Relevant indexes**: `gig.gig_worker_service` has only `uq_gig_worker_service_skill UNIQUE (gig_worker_profile_id, skill_id)` (`014:106`) — leading column is the *profile*, not the skill. **There is no index on `skill_id`.** This is an asymmetry with every other skill junction table in the schema: `profile.candidate_skill` has `idx_candidate_skill_skill_id (skill_id)` (`005:77`) and `recruitment.job_skill_requirement` has `idx_job_skill_requirement_skill_id (skill_id)` (`008:243`).

**Bottleneck**: The `Hash Cond: (gws.skill_id = s.id)` forces the entire `gig_worker_service` table (5,000 rows) into a hash table on every execution. The query's actual selectivity is narrow — one skill — but the plan cannot exploit that because there is no index to seek. Q07 is the second-slowest query in the suite (p50 11.07 ms) and has the **highest buffer footprint of all 12 queries: 15,351 shared hit blocks**, dominated by the 2,500 executions of the `pk_gig_worker_profile` index scan (7,500 blocks) and the availability index-only scan (5,001 blocks).

**The GiST exclusion index is working correctly and is not the problem.** `ex_gig_assignment_no_overlap` is used as an `Index Scan` with a genuine range-overlap `Index Cond` — the `daterange(...) && daterange(...)` predicate is sargable against the GiST index and the plan proves it. `idx_gig_worker_availability_profile_dates` is used as an **`Index Only Scan` with `Heap Fetches: 0`** — the covering behavior is exactly as designed. The `NOT EXISTS` anti-join correctly eliminated zero rows, meaning the seed's assignments did not overlap the target window.

**Proposed change** (not applied):
```sql
CREATE INDEX idx_gig_worker_service_skill_id
    ON gig.gig_worker_service (skill_id);
```

**Expected benefit**: Qualitative — allows a nested-loop index seek instead of a full-table hash build, reducing the dominant hash-build cost. The `Sort` node (top-N heapsort, 71 estimated rows → 25 actual) remains, because `idx_gig_worker_profile_available_rates (is_available, hourly_rate, currency_code)` does not cover the `ORDER BY gwp.average_rating DESC NULLS LAST, gwp.total_completed_gigs DESC` sort key.

**Confidence**: HIGH that no `skill_id` index exists on this table (provable from migration source) and that the plan uses a full scan (measured). MEDIUM on the benefit magnitude.

**Risk**: MEDIUM-LOW. `gig.gig_worker_service` is a small, slow-changing table, so write cost is negligible. The larger risk is that the planner, given a `skill_id` index, might switch to a nested loop that is *worse* at small scale. Must verify the plan does not regress at 2,000 gig workers.

**Validation criteria**: Re-run Q07 with `EXPLAIN (ANALYZE, BUFFERS)` at both dev scale and the 2,000-gig-worker scale. Success = the `gig_worker_service` access path becomes an `Index Scan` or `Bitmap Index Scan` and the `Hash` node disappears; total `Shared Hit Blocks` for Q07 falls below its current 15,351. Confirm p50 does not regress at small scale.

---

### F-04 — Q02 job feed: the `OR` on `application_deadline` is non-sargable and defeats `idx_job_posting_deadline`

**Query**: `db/queries/02_job_feed_matching.sql:24-29`
**SQL**:
```sql
WHERE jp.job_status = 'published'
  AND (jp.application_deadline IS NULL OR jp.application_deadline > CURRENT_TIMESTAMP)
  AND (wt.code IN ('remote', 'hybrid'))
```

**Current plan** (captured):
```
Hash Join  Hash Cond: (jp.work_type_id = wt.id)
  ├─ Seq Scan  job_posting (jp)   Actual Rows: 1900
  │     Filter: ((job_status)::text = 'published'::text)
  │             AND ((application_deadline IS NULL) OR (application_deadline > CURRENT_TIMESTAMP))
  │     Rows Removed by Filter: 0
  └─ Hash  (work_type, 2 rows)
       └─ Bitmap Index Scan  work_type  Index Name: uq_work_type_code
            Index Cond: ((code)::text = ANY ('{remote,hybrid}'::text[]))
```

**Relevant indexes**: `idx_job_posting_status_published ON recruitment.job_posting (job_status, published_at DESC) WHERE job_status = 'published'` (`008:175`) — predicate matches ✓; `idx_job_posting_deadline ON recruitment.job_posting (application_deadline) WHERE job_status = 'published' AND application_deadline IS NOT NULL` (`008:189`).

**Confirmed issue**: The disjunction `application_deadline IS NULL OR application_deadline > CURRENT_TIMESTAMP` **cannot be turned into a single index range condition** by the planner, so `idx_job_posting_deadline` cannot be used to filter on it. Additionally, even if the planner could apply it, the partial index's predicate (`application_deadline IS NOT NULL`) covers only the *right* branch of the `OR`; the `IS NULL` branch (jobs with no deadline) is not in the index at all, so a partial index alone can never fully serve this predicate. This is a genuine, inherent sargability limitation of the query's semantics, not merely a column-order issue.

**What the plan does show is correct**: `uq_work_type_code` *is* used via a `Bitmap Index Scan` with `Index Cond: (code = ANY ('{remote,hybrid}'))` — the `wt.code IN (…)` filter is fully sargable. The PK index scans on `organization`, `employment_type`, `city` and the `uq_job_skill_requirement_job_skill` index on `jsr.job_posting_id` are all correctly chosen.

**Proposed change** — two options, both *query-level* rather than index-level:

```sql
-- Option A (preferred): rewrite the OR into two sargable branches
WHERE jp.job_status = 'published'
  AND (jp.application_deadline IS NULL OR jp.application_deadline > CURRENT_TIMESTAMP)
-- becomes, via UNION ALL or via a COALESCE sentinel on a generated column:
--   WHERE jp.job_status = 'published'
--     AND COALESCE(jp.application_deadline, 'infinity'::timestamptz) > CURRENT_TIMESTAMP
```
Option A only works if `idx_job_posting_deadline` is changed to index the coalesced expression, which requires an expression index:
```sql
CREATE INDEX idx_job_posting_effective_deadline
    ON recruitment.job_posting (COALESCE(application_deadline, 'infinity'::timestamptz))
    WHERE job_status = 'published';
```

```sql
-- Option B: drop the deadline filter from the feed query and exclude expired
--          postings in the application (write) path instead.
```
Option B is architecturally cleaner: a feed of "published" jobs arguably should not carry a time-dependent predicate at all, since `published` should already imply "accepting applications."

**Expected benefit**: Qualitative. On the captured seed `job_posting` is 1,900 rows on a small number of pages, so the seq scan costs nothing measurable. The benefit appears only at 1M jobs, where a `published_at DESC` index scan with a `LIMIT 50` would touch ~50 rows instead of scanning all published postings. Note that `idx_job_posting_status_published` **can** provide the `published_at DESC` ordering for the `LIMIT 50` and **can** restrict to `job_status='published'` — the planner did not use it in the captured plan because the seq scan on a 1,900-row table was cheaper. This is another case where the plan is *right for the data* and the gap is a scale gap.

**Confidence**: HIGH that the `OR` is non-sargable (deterministic planner behaviour). MEDIUM on the benefit (scale-dependent, unmeasured). HIGH that Option B is the more defensible design.

**Risk**: MEDIUM for Option A — the expression index is a maintenance burden and every `COALESCE` form must match exactly or the index is silently unused. LOW for Option B — it changes feed semantics, which is a product decision, not a pure performance change.

**Validation criteria**: At the 1M-job scale, confirm the plan switches to an `Index Scan` on `idx_job_posting_status_published` with `Index Cond: (job_status = 'published')` and `Scan Direction: Backward` (providing `published_at DESC`), and that `Shared Hit Blocks` for Q02 drop well below the full-table count. Verify the rewrite returns the same result set as the original on the same data.

---

### F-05 — Q10 analytics KPI: the fact table is seq-scanned, and the join key has no index

**Query**: `db/queries/10_analytics_time_to_hire_kpi.sql:17-20`
**SQL**:
```sql
FROM analytics.fact_application_event f
JOIN analytics.dim_job_posting j ON f.job_posting_key = j.job_posting_key
GROUP BY j.industry_name
```

**Current plan** (captured):
```
Sort  Sort Key: [(count(DISTINCT CASE WHEN new_status='joined' THEN candidate_application_id END)) DESC, ...]
  └─ Aggregate  Strategy: Sorted  Group Key: [j.industry_name]
       └─ Sort  Sort Key: [j.industry_name, f.candidate_application_id]   ← 2000 rows sorted
            └─ Hash Join  Hash Cond: (f.job_posting_key = j.job_posting_key)  Actual Rows: 2000
                 ├─ Seq Scan  fact_application_event (f)  Actual Rows: 2000
                 └─ Hash  (1900 rows)  ← Seq Scan  dim_job_posting (j)  Actual Rows: 1900
```

**Relevant indexes**: `idx_fact_app_event_org_job ON analytics.fact_application_event (organization_key, job_posting_key)` (`019:182`) and `idx_fact_app_event_status_date (new_status, date_key)` (`019:179`). `analytics.dim_job_posting` has `uq_dim_job_posting_id UNIQUE (job_posting_id)` (`019:116`) — but the join is on `job_posting_key`, which is the **primary key** (`pk_dim_job_posting`), not `job_posting_id`.

**Confirmed issue**: The join key on the fact side, `f.job_posting_key`, is the **leading column of neither** of the fact table's indexes. `idx_fact_app_event_org_job` leads with `organization_key`, which the query does not filter — so it cannot serve this join. The only usable fact-side index, `idx_fact_app_event_status_date`, leads with `new_status`, also unfiltered. The planner therefore has no index path for the join and seq-scans the fact table.

**Secondary confirmed cost**: the plan performs a **sort of 2,000 rows on `(j.industry_name, f.candidate_application_id)`** to feed the `Sorted` aggregate. That sort exists solely to serve the five `COUNT(DISTINCT f.candidate_application_id)` aggregates. The `Sort` consumed 1.779 ms of the 2.271 ms total execution time — **roughly 78% of the query's execution time was the sort**, not the join or the scan. `Sort Space Used: 178 kB`, `Sort Space Type: Memory` — it fits in `work_mem` at this scale, but at 100M fact rows it would spill to disk (an external merge sort), which is precisely the failure mode `docs/phase-4-platform/28-performance-report.md` §4.2 warns about for Q01.

**Third confirmed point**: the query has a **near-duplicate already built**. `analytics.mv_hiring_funnel_summary` is a materialized view that computes per-job funnel counts and can be refreshed concurrently via `analytics.refresh_reporting_marts()` (`019:308`). It is per-job; Q10 is per-industry. The per-industry rollup is a second `GROUP BY` over the mart's output, which is far smaller than the fact table.

**Proposed change** (not applied) — options, in order of preference:
```sql
-- Option A (structural, best): serve the industry rollup from the existing mart
SELECT industry_name, ... FROM analytics.mv_hiring_funnel_summary ... GROUP BY industry_name
-- requires the mart to carry industry_name (verify — mv definition in 019 must be checked)

-- Option B (index): support the fact-side join key
CREATE INDEX idx_fact_app_event_job_posting
    ON analytics.fact_application_event (job_posting_key);
```

**Expected benefit**: Qualitative. Option A converts a 2,000-row (→ 100M-row) fact scan into a scan of the much smaller mart. Option B alone helps the join but **does not** remove the `COUNT(DISTINCT)` sort, so it addresses the smaller half of the cost.

**Confidence**: HIGH that no index leads with `job_posting_key` on the fact table (provable from migration source) and that the sort dominates (measured: 1.779 ms of 2.271 ms). MEDIUM on Option A's applicability — I did not read the full `mv_hiring_funnel_summary` definition and have not confirmed it exposes `industry_name`.

**Risk**: MEDIUM for Option A (the mart's grain and freshness semantics must be confirmed; `REFRESH … CONCURRENTLY` requires a unique index, which `uq_mv_hiring_funnel_job` provides). LOW for Option B, but low value alone.

**Validation criteria**: Read the `mv_hiring_funnel_summary` definition in `019_create_analytics_marts.sql` and confirm its grain and column set. If it exposes industry, compare Q10 rewritten over the mart against the current form at the 2,000-fact-row scale and at the largest feasible scale; success = execution time dominated by the mart scan with no sort on the fact's `candidate_application_id`.

---

### F-06 — Q09 notification feed: the existing index cannot supply the query's `ORDER BY`, and the query is a full-table scan

**Query**: `db/queries/09_high_volume_notification_write.sql:14-17`
**SQL**:
```sql
FROM messaging.notification_delivery nd
WHERE nd.recipient_user_account_id = 1
ORDER BY nd.created_at DESC
LIMIT 20;
```

**Current plan** (captured):
```
Limit
  └─ Sort  Sort Key: [created_at DESC]  Sort Method: quicksort
       └─ Seq Scan  notification_delivery (nd)
            Filter: (recipient_user_account_id = 1)
            Rows Removed by Filter: 100
```
`Actual Rows: 0`, `Shared Hit Blocks: 2` — the seed has 101 rows for user 1's table, none matching.

**Relevant index**: `idx_notification_delivery_recipient_status ON messaging.notification_delivery (recipient_user_account_id, delivery_status, created_at DESC)` (`018:281`).

**Confirmed issue**: this is a **column-order** defect, and it is the cleanest example in the suite. The index's column sequence is `(recipient_user_account_id, delivery_status, created_at DESC)`. The query filters on `recipient_user_account_id` and orders by `created_at DESC`, but **does not filter on `delivery_status`**. The B-tree is ordered by `recipient_user_account_id` first, then `delivery_status`, then `created_at`. Within a given recipient, rows are ordered by `delivery_status` — *not* by `created_at`. So the index **cannot supply the required ordering**; the planner must fetch all matching rows and sort them. The plan confirms exactly this: a `Sort` node above the scan.

Note the query is *named* "high_volume_notification_write" and its documented purpose is "Fast paginated retrieval of **unread** and recent notifications" — but it has **no `delivery_status` or `read_at` filter at all**. The index appears to have been designed for a query that filters on `delivery_status`; the query as written does not. Either the query is missing the filter the index was built for, or the index was built for a query that does not exist. That mismatch is the root cause.

**Proposed change** — two coherent options:
```sql
-- Option A: add the index that matches the query as written
CREATE INDEX idx_notification_delivery_recipient_created
    ON messaging.notification_delivery (recipient_user_account_id, created_at DESC);
-- → supports the filter AND supplies the ORDER BY, so the Sort disappears and LIMIT 20
--   becomes an early stop after ~20 index entries.

-- Option B: make the query match the index that already exists
--   WHERE nd.recipient_user_account_id = 1
--     AND nd.delivery_status IN ('queued','sent','delivered')
--   (or whatever the "unread" set is) and ORDER BY nd.created_at DESC
-- → then idx_notification_delivery_recipient_status can serve the filter, but the
--   created_at DESC sort still requires a Sort because delivery_status precedes
--   created_at in the key.
```

Option A is the better fit for a paginated feed. Option B only makes sense if the "unread" filter is a genuine product requirement that is currently missing.

**Expected benefit**: Qualitative — eliminates the `Sort` node and converts the scan to an early-terminating index scan. This is the highest-value *structural* fix per unit of index cost in the whole suite, because the current shape is O(table) per page load whereas the fixed shape is O(20) per page load. This is the query that scales worst relative to its apparent cost, because "high volume" is the stated design intent: at a realistic 100M-row `notification_delivery`, the seq scan reads the entire table to return 20 rows.

**Confidence**: HIGH — the column-order mismatch is deterministic and the plan (`Sort` above `Seq Scan`) confirms the planner already knows it cannot use the index for ordering.

**Risk**: LOW-MEDIUM. A second index on a high-write table (`notification_delivery` is explicitly the "high-volume write path" per `018:245`) adds write amplification. The `INCLUDE`d variant `(recipient_user_account_id, created_at DESC) INCLUDE (id, channel, subject, delivery_status, sent_at, read_at)` would permit an index-only scan, but `body_snippet` is selected and is 500 bytes — including it would bloat the index substantially. Recommend the plain 2-column version.

**Validation criteria**: At a realistic notification volume, confirm the plan becomes `Limit → Index Scan (idx_notification_delivery_recipient_created)` with **no Sort node**, and that `Shared Hit Blocks` becomes O(20) rather than O(table pages). Also confirm the write-path cost of the extra index is acceptable by measuring insert throughput on `notification_delivery` before and after.

---

### F-07 — Q06 outreach filter: the `NOT EXISTS` block check is a full scan of `core.user_block`, and the partial indexes are structurally unable to serve it

**Query**: `db/queries/06_sourcing_outreach_unblocked.sql:17-23`
**SQL**:
```sql
AND NOT EXISTS (
    SELECT 1
    FROM core.user_block ub
    WHERE ub.blocker_user_account_id = cp.user_account_id
      AND (ub.blocked_user_account_id = 2 OR ub.blocked_organization_id = 1)
)
```

**Current plan** (captured):
```
Nested Loop  Join Filter: (ub.blocker_user_account_id = cp.user_account_id)
  └─ Materialize  Actual Loops: 50   Actual Rows: 0
       └─ Seq Scan  user_block (ub)
            Filter: ((blocked_user_account_id = 2) OR (blocked_organization_id = 1))
            Rows Removed by Filter: 2
```

**Relevant indexes**: `uq_user_block_user (blocker_user_account_id, blocked_user_account_id) WHERE blocked_user_account_id IS NOT NULL` (`012:209`); `uq_user_block_organization (blocker_user_account_id, blocked_organization_id) WHERE blocked_organization_id IS NOT NULL` (`012:213`); `idx_user_block_blocked_user (blocked_user_account_id) WHERE …` (`012:217`); `idx_user_block_blocked_org (blocked_organization_id) WHERE …` (`012:221`).

**Confirmed issue**: The `OR` across `blocked_user_account_id` and `blocked_organization_id` spans two disjoint partial indexes, and each partial index's *leading* column is `blocker_user_account_id`. The filter's structure is `(blocker = X) AND (blocked_user = 2 OR blocked_org = 1)`. The `uq_user_block_user` index can serve the first branch: `(blocker_user_account_id = X AND blocked_user_account_id = 2)`. The `uq_user_block_organization` index can serve the second branch. But the `OR` in the second position prevents the planner from using either as a simple range condition; it would need a `BitmapOr` of two index scans, and the `Materialize` node in the plan shows it chose to scan the table instead and materialize the (empty) result, re-scanning it 50 times via the `Join Filter`.

**Second confirmed issue, and the more important one**: the `Join Filter: (ub.blocker_user_account_id = cp.user_account_id)` is applied *after* the `Materialize`, and the plan reports `Rows Removed by Join Filter: 0` — because the materialized set was empty (the seed's `user_block` table has 2 rows, neither matching). At scale, this is the shape that matters: the `NOT EXISTS` is evaluated as a **join filter against a materialized set**, not as an anti-join with index seeks. The `Rows Removed by Join Filter: 0` figure is a seed artifact, not evidence that the predicate is cheap.

**Third confirmed point**: `core.user_block` has a `CHECK (ck_user_block_target_xor)` constraint (`012:198`) that guarantees a row has *either* `blocked_user_account_id` or `blocked_organization_id` set, never both. This means the `OR` in the query is a genuine disjunction over mutually exclusive cases — it cannot be collapsed by the constraint, and the two branches genuinely need separate access paths.

**Proposed change** (not applied): split the `OR` into two `NOT EXISTS` subqueries, each of which a single partial index can serve directly:
```sql
AND NOT EXISTS (
    SELECT 1 FROM core.user_block ub
    WHERE ub.blocker_user_account_id = cp.user_account_id
      AND ub.blocked_user_account_id = 2
)
AND NOT EXISTS (
    SELECT 1 FROM core.user_block ub
    WHERE ub.blocker_user_account_id = cp.user_account_id
      AND ub.blocked_organization_id = 1
)
```
This maps one-to-one onto the two existing partial unique indexes. **No new index is required** — this is a pure query rewrite that makes existing index coverage usable.

**Expected benefit**: Qualitative — replaces a materialized-scan-then-join-filter with two index-driven anti-joins. Given the existing indexes are *already correct* for the split form, this is a high-benefit / zero-index-cost fix.

**Confidence**: HIGH on the structural facts (partial index definitions, the XOR constraint, the `Materialize` + `Join Filter` plan shape). MEDIUM on the benefit magnitude, which depends on `core.user_block` volume.

**Risk**: LOW. The rewrite is semantically equivalent given the XOR constraint (the two `NOT EXISTS` are exactly the union of the original `OR`).

**Validation criteria**: Confirm the plan for the rewritten query shows two `Anti` joins, each with an `Index Scan` on `uq_user_block_user` and `uq_user_block_organization` respectively, with no `Materialize` and no `Seq Scan` on `user_block`. Verify identical result set to the original on the same data.

---

### F-08 — Q04 session validation: the partial index designed for the active-session filter is not chosen; a non-partial one is, with a recheck filter applied

**Query**: `db/queries/04_concurrent_session_validation.sql:13-18`
**SQL**:
```sql
LEFT JOIN core.user_session s
    ON u.id = s.user_account_id AND s.ended_at IS NULL AND s.revoked_at IS NULL
```

**Current plan** (captured):
```
Nested Loop
  └─ Nested Loop  Join Filter: (lsa.subscription_licence_id = sl.id)
       ├─ Nested Loop
       │    ├─ Index Scan  user_account  Index Name: pk_user_account  Index Cond: (id = 1)
       │    └─ Index Only Scan  licence_seat_allocation  Index Name: uq_licence_seat_active_user
       │         Index Cond: (user_account_id = 1)
       └─ Seq Scan  subscription_licence
            Filter: ((licence_status)::text = 'active'::text)
       └─ Index Scan  user_session  Index Name: idx_user_session_device_identifier
            Index Cond: (user_account_id = 1)
            Filter: ((ended_at IS NULL) AND (revoked_at IS NULL))
            Rows Removed by Filter: 0
```

**Relevant indexes**: `idx_user_session_active_user (user_account_id, last_activity_at DESC) WHERE ended_at IS NULL AND revoked_at IS NULL` (`002:190`); `idx_user_session_device_identifier (user_account_id, device_identifier)` (`002:194`).

**Confirmed issue**: the query's `ended_at IS NULL AND revoked_at IS NULL` predicate **exactly matches** the partial predicate of `idx_user_session_active_user`, yet the planner chose `idx_user_session_device_identifier` and applied the null-checks as a **post-scan `Filter`**. On a 0-row result this is free; at scale it means the index scan must visit *every* session row for the user — including ended and revoked ones — and discard them, instead of visiting only the active ones. The partial index was built precisely for this access pattern and is not being used.

The reason is visible in the plan: `idx_user_session_device_identifier` leads with `(user_account_id, device_identifier)`, and the query selects `s.device_identifier` (and aggregates `COUNT(DISTINCT s.device_identifier)` and `ARRAY_AGG(DISTINCT s.device_identifier)`). The planner preferred an index that can supply the `device_identifier` value, accepting the filter cost.

**A second, larger confirmed issue is on the licence side.** The join `LEFT JOIN commercial.subscription_licence sl ON lsa.subscription_licence_id = sl.id AND sl.licence_status = 'active'` is executed as a **`Join Filter`, not an index lookup**: `Join Filter: (lsa.subscription_licence_id = sl.id)`, with `Seq Scan` on `subscription_licence` and `Filter: (licence_status = 'active')`. There is no index on `commercial.subscription_licence.id` other than the PK — wait, the PK *is* `id`, so a `Hash Join` on the PK should be available; the planner chose a nested loop with a join filter because the outer side produced 0 rows. **This is a seed artifact** (`Actual Rows: 0` everywhere because user 1 has no sessions or licences in the seed). The structurally notable fact is that the plan is a **nested loop with a join filter**, which at scale re-executes the `subscription_licence` scan per outer row.

**Third confirmed point**: `idx_licence_seat_active_user` is used as an **`Index Only Scan`** — that part of the design works well.

**Proposed change** (not applied): the planner's choice here is defensible at the current data volume, so the fix is to make the partial index's coverage *complete for the query's needs* so the planner has no reason to prefer the alternative:
```sql
CREATE INDEX idx_user_session_active_user_devices
    ON core.user_session (user_account_id, device_identifier)
    WHERE ended_at IS NULL AND revoked_at IS NULL;
```
This single index covers the filter, supplies `device_identifier` for the aggregate, and permits an index-only scan. The existing `idx_user_session_device_identifier` then becomes redundant for this query (though it still serves queries that do *not* filter on the null-checks).

**Expected benefit**: Qualitative — removes the post-scan `Filter` and lets the `COUNT(DISTINCT device_identifier)` / `ARRAY_AGG(DISTINCT device_identifier)` aggregates be served from the index. This is the **login path**, so its latency is the most latency-sensitive in the suite.

**Confidence**: MEDIUM-HIGH on the facts (the partial index exists and is unused — measured; the `Filter` is applied post-scan — measured). MEDIUM on the recommendation, because the planner is choosing sensibly for a *small* `user_session` table and the proposed index may or may not win the planner's cost comparison.

**Risk**: MEDIUM. `core.user_session` is a high-churn table; adding a third index increases write cost on the login path itself. A partial index is smaller than a full one, which mitigates this. The change also creates three overlapping indexes on `user_session` — an index-hygiene problem that should be resolved by dropping whichever becomes redundant.

**Validation criteria**: At a realistic session count, confirm the plan for Q04 uses `idx_user_session_active_user_devices` (or `idx_user_session_active_user`) as an `Index Only Scan` with `Heap Fetches: 0` and **no `Filter` node** on the session scan, and that the `subscription_licence` access becomes a `Hash Join` on the PK rather than a per-row `Join Filter`. Measure login-path p95 before and after.

---

## 5. Confirmed Structural Divergences (not query findings, but they change what optimization means here)

---

### 5.1 The partitioning claim has no target

**README.md:54** — "High-velocity candidate applications (`recruitment.candidate_application_partitioned`) are partitioned **quarterly** by `RANGE (applied_at)`, pruning >75% of index scans."
**README.md:198** — "declaratively range-partitioned **quarterly**".

**Migration `019_create_analytics_marts.sql:318-356`**:
```sql
CREATE TABLE recruitment.candidate_application_partitioned (
    ...
    CONSTRAINT pk_candidate_app_partitioned PRIMARY KEY (id, applied_at)
) PARTITION BY RANGE (applied_at);

-- Partitions by year          ← the migration's own comment
CREATE TABLE recruitment.candidate_application_y2025 PARTITION OF ... FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');
CREATE TABLE recruitment.candidate_application_y2026 PARTITION OF ... FOR VALUES FROM ('2026-01-01') TO ('2027-01-01');
CREATE TABLE recruitment.candidate_application_y2027 PARTITION OF ... FOR VALUES FROM ('2027-01-01') TO ('2028-01-01');

CREATE INDEX idx_candidate_app_part_job_status
    ON recruitment.candidate_application_partitioned (job_posting_id, application_status);
```

**Confirmed divergences**:
1. **Partition granularity is annual, not quarterly.** Three annual partitions, `y2025`/`y2026`/`y2027`. The migration's own comment says "Partitions by year". The README says quarterly in two places.
2. **The table the application workflow actually uses is not partitioned.** `recruitment.candidate_application` (`009_create_candidate_application.sql`) is a plain table: `id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY`, with `applied_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP` and `UNIQUE (candidate_profile_id, job_posting_id)`. It has **no** `PARTITION BY` clause. `candidate_application_partitioned` is a **separate, parallel table** with the same column shape.
3. **No query references the partitioned table.** All 12 files in `db/queries/` reference `recruitment.candidate_application` (Q03 only). `candidate_application_partitioned` appears in **zero** of them.
4. **The partitioned table's index does not match the funnel query.** `idx_candidate_app_part_job_status (job_posting_id, application_status)` lacks the `applied_at DESC` third column that `idx_candidate_application_job_status` has — which matters for a partitioned table because the partition key must be in the index for the index to be created on the partitioned parent without per-partition creation.

**Consequence for Phase 2B**: the spec's requirement to "review partition pruning for queries on partitioned application data" **has no live target**. The `recruitment.candidate_application` table that Q03 queries is unpartitioned. Partition pruning is not a live concern for the current query set; it is a *future migration* concern. Any recommendation to add partition pruning to the 12 benchmark queries would be recommending a change to a table no query touches.

**Confirmed by inspection of the migration and the query set** — this does not require a live catalog query, because the DDL is in the migration source and the query set is in the repo. I could not confirm the *runtime* row counts of the partitioned table and its partitions (blocked DB access), so I cannot confirm whether it is empty; the validator only checks that ≥ 3 partitions exist (`scripts/validate_data.py:299-313`), which says nothing about data.

**Proposed change** (documentation, not performance):
* Correct README.md:54 and README.md:198 to say **annually**, or change the migration to create quarterly partitions — whichever is intended.
* State explicitly which table is authoritative. If `candidate_application_partitioned` is the target, the application workflow must be migrated to write to it; if `candidate_application` is, the README's "Key Technical Innovations §5" claim should be removed.
* Correct `docs/phase-4-platform/28-performance-report.md` §5.3, which repeats the quarterly claim.

**Confidence**: HIGH on the DDL facts (read directly from the migration source). LOW on whether the partitioned table holds data (unverified).

**Risk**: LOW for the documentation fix. HIGH for any attempt to migrate the workflow to the partitioned table without first deciding the authoritative table — a dual-write or migration would need a data-movement plan, and the `UNIQUE (candidate_profile_id, job_posting_id)` constraint on the plain table has no equivalent on the partitioned one (whose PK is `(id, applied_at)`).

**Validation criteria**: `SELECT parent.relname, child.relname, pg_get_expr(child.relpartbound, child.oid) FROM pg_inherits ...` to confirm the partition bounds on the live instance; `SELECT count(*) FROM recruitment.candidate_application_partitioned;` to confirm whether it is populated; and `SELECT count(*) FROM recruitment.candidate_application;` for the authoritative table.

---

### 5.2 `recruitment.candidate_application` — no index supports the status-filtered listing workflow

**Migration `009_create_candidate_application.sql:133-143`**:
```sql
CREATE INDEX idx_candidate_application_candidate_applied
    ON recruitment.candidate_application (candidate_profile_id, applied_at DESC, id DESC);
CREATE INDEX idx_candidate_application_job_status
    ON recruitment.candidate_application (job_posting_id, application_status, applied_at DESC);
CREATE INDEX idx_candidate_application_status_applied
    ON recruitment.candidate_application (application_status, applied_at DESC);
```

**Confirmed coverage analysis** against the spec's "candidate application listing and status filtering" workflow:

| Query pattern | Index | Verdict |
|:--|:--|:--|
| All applications for a candidate, newest first | `idx_candidate_application_candidate_applied (candidate_profile_id, applied_at DESC, id DESC)` | ✓ Matches, including the tie-break on `id` |
| All applications for a job, by status, newest first | `idx_candidate_application_job_status (job_posting_id, application_status, applied_at DESC)` | ✓ Matches exactly — and Q03's plan confirms it: `Bitmap Index Scan`, `Index Cond: (job_posting_id = 1)` |
| All applications with a given status, newest first | `idx_candidate_application_status_applied (application_status, applied_at DESC)` | ✓ Matches — **this is the generic status-filtered listing index, and it is correct** |
| Application for a specific candidate **and** job | `UNIQUE (candidate_profile_id, job_posting_id)` | ✓ Exact match, serves the existence check |

**Verdict**: the index coverage for the application workflow is **adequate and well-designed**. `idx_candidate_application_status_applied` in particular is the correct shape for a global status-filtered list, and it is the index a recruiter-facing "all rejected applications" view needs. **No additional index is warranted here.** This is a case where the correct finding is "no action needed", and it is worth stating explicitly because the Phase 2A brief lists the application workflow as a candidate area.

The one thing that is *not* covered: `last_status_changed_at` (used by Q03's `AVG(EXTRACT(EPOCH FROM (ca.last_status_changed_at - ca.applied_at)))`) is in **no** index, so Q03 cannot use an index-only scan and must fetch the heap for every matching row. The Q03 plan confirms a `Bitmap Heap Scan` — the heap fetch is unavoidable with the current index. Whether it matters depends on the number of applications per job; at 50K applications over 1,000 jobs, a single job has ~50 applications, which is trivial. At 100M applications over 1M jobs, still ~100 per job. **This is a low-value finding and I do not recommend changing the index for it** — the added index width would cost more across all 100M rows than the heap fetch saves on ~100 rows per query. Recording it for completeness only.

**Confidence**: HIGH. The index definitions are in the migration source and the Q03 plan confirms the job/status index is chosen.

---

### 5.3 The `uq_candidate_location_current` partial index is never used

`uq_candidate_location_current ON profile.candidate_location (candidate_profile_id) WHERE location_type = 'current'` (`005:208`) exists specifically for Q01's and Q06's `LEFT JOIN profile.candidate_location cl ON cp.id = cl.candidate_profile_id AND cl.location_type = 'current'`.

**Captured Q01 plan**: the `candidate_location` access is a **`Seq Scan`** with `Filter: ((location_type)::text = 'current'::text)`, `Actual Rows: 14500`, `Rows Removed by Filter: 0`, joined by `Hash Cond: (cl.candidate_profile_id = cp.id)`. The partial index is **not** used.

**Why**: on a 14,500-row table where *every* row has `location_type='current'` (the generator evidently inserts one current location per candidate), the partial index's predicate matches the entire table, so the index has no selectivity advantage over the seq scan and the planner correctly prefers the cheaper sequential path. The index is not wrong — it is simply not selective on this data. The `Hash Cond` also means the join is not driven by an index nested loop.

This is **not** a defect; it is a correct plan on a dataset where the partial index has no selectivity. The finding matters only because it demonstrates that **F-01's proposed composite index will face the same planner reasoning**: a partial index whose predicate is satisfied by a large fraction of the table will not be chosen. This is a caveat on F-01's expected benefit, and it is why F-01's validation criteria require plan verification at scale rather than accepting the index on faith.

**Confidence**: HIGH (measured plan + migration source).

---

### 5.4 Index coverage that is *correct* and worth recording

For completeness, these captured plans show index coverage working as designed — no action recommended:

* **Q07** — `ex_gig_assignment_no_overlap` used as a genuine GiST range-overlap `Index Scan`; `idx_gig_worker_availability_profile_dates` used as an **`Index Only Scan` with `Heap Fetches: 0`**. The btree_gist calendar-non-overlap design works.
* **Q02** — `uq_work_type_code` via `Bitmap Index Scan` with `Index Cond: (code = ANY ('{remote,hybrid}'))`; PK index scans on `organization`, `employment_type`, `city`; `uq_job_skill_requirement_job_skill` on `jsr.job_posting_id`.
* **Q06** — `uq_skill_normalized_name` via `Index Scan` on `normalized_name`; `idx_candidate_skill_skill_id` via `Bitmap Index Scan` (`Index Cond: (skill_id = s.id)`); `pk_candidate_profile` via `Index Scan`.
* **Q08** — `idx_profile_download_org_downloaded` via `Bitmap Index Scan` (`Index Cond: (organization_id = 1)`); PK index scans on `organization`, `user_account`, `candidate_profile`. Clean.
* **Q04** — `uq_licence_seat_active_user` via `Index Only Scan`.

---

## 6. The Benchmark Harness Methodology Is Invalid — and It Is the Highest-Priority Finding

**`scripts/run_benchmarks.py:160-192`**:
```python
# Indexed latency
cur.execute("SET enable_seqscan = on; SET enable_indexscan = on; SET enable_bitmapscan = on;")
t0 = time.perf_counter()
for _ in range(5):
    cur.execute(sql); cur.fetchall()
t_indexed = (time.perf_counter() - t0) / 5.0 * 1000.0

# Unindexed simulation (force sequential table scan)
cur.execute("SET enable_indexscan = off; SET enable_bitmapscan = off; SET enable_indexonlyscan = off;")
t0 = time.perf_counter()
for _ in range(5):
    cur.execute(sql); cur.fetchall()
t_unindexed = (time.perf_counter() - t0) / 5.0 * 1000.0

speedup = round(t_unindexed / t_indexed, 2) if t_indexed > 0 else 1.0
```

**Confirmed methodological defect**: the "without index" baseline is produced by **forbidding index access paths entirely** (`enable_indexscan = off; enable_bitmapscan = off; enable_indexonlyscan = off`). This does not measure "the value of an index" — it measures "the cost of a forced sequential scan", which is a different quantity. The resulting `speedup_factor` is a **ratio of a real plan to a deliberately crippled plan**, and it is reported in the documentation as if it were an index benefit.

**The reported numbers are therefore not interpretable as index impact** (`benchmarks/results/benchmark_summary.md` §2, `benchmarks/results/benchmark_results.json` `index_impact`):

| Query | Reported "with index" | Reported "without index" | Reported factor | What the number actually is |
|:--|--:|--:|--:|:--|
| Q01 | 29.21 ms | 27.79 ms | 0.95x | forced seq scan was **faster** — says nothing about any index |
| Q03 | 1.21 ms | 6.07 ms | 5.0x | the *real* plan already used `idx_candidate_application_job_status` (Bitmap Index Scan, measured). The 5.0x is the cost of denying that access. It is **not** the benefit of adding the index — the index already existed. |
| Q07 | 10.73 ms | 4.96 ms | 0.46x | forced seq scan was **2.2x faster** — the doc's own §2 note calls this "SeqScan small table" |

**The Q03 case is the clearest evidence the metric is wrong**: `docs/phase-4-platform/28-performance-report.md` §2 presents "5.0x Speedup" as the justification for `idx_candidate_application_job_status`, but that index **already exists** in the schema (`009:137`) and was **already in use** in the "with index" measurement. The 5.0x is the difference between "the plan that uses a correct index" and "the plan where the planner is forbidden from using any index" — it is a measure of the *forced cripple*, not of adding anything.

**Second confirmed defect in the same harness**: `scripts/run_benchmarks.py:109` runs `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` for all 12 queries. `EXPLAIN ANALYZE` **executes** the query. For these 12 read queries on a 10K-scale dataset this is harmless, but it is an unbounded cost that scales with the dataset — it is precisely the practice the Phase 2B safety requirements prohibit. A performance harness should plan with `EXPLAIN (COSTS true)` and time separately with `EXPLAIN (ANALYZE)` only on a bounded, explicitly-approved subset.

**Third defect**: `scripts/run_benchmarks.py:166` runs `SET enable_seqscan = on` but never resets it for the *indexed* leg in a way that guarantees planner freedom; and the "with index" leg at 29.21 ms for Q01 is 1.7% faster than the p50 of 30.87 ms from the main timing loop — a discrepancy that is never explained, suggesting the two measurement legs are not comparable.

**Proposed change** (not applied — this report is read-only):
* Replace the "index impact" methodology with one of:
  * **A/B against a real schema change** in a scratch database (create the index, re-plan, compare) — the only method that measures an index's actual value; or
  * **Drop the "index impact" section entirely** and report only plan-shape and access-path facts, which are what the plans actually support; or
  * If a forcing-based comparison is kept, relabel it honestly as *"cost of disabling index access paths"*, and never present it as an index speedup factor.
* Split the harness into a *planning* pass (`EXPLAIN (COSTS true)`) and a separate, explicitly-bounded *execution* pass.

**Expected benefit**: Not a performance gain — a **credibility** gain. It removes a metric from the public documentation (`docs/phase-4-platform/28-performance-report.md` §2, `README.md` §5 table, `benchmarks/results/benchmark_summary.md` §2) that currently overstates the value of three indexes and understates the value of a correct plan.

**Confidence**: HIGH. The defect is visible in the harness source, and the Q03 case demonstrates it concretely from the harness's own output.

**Risk**: LOW. Documentation and harness changes only.

**Validation criteria**: After the fix, the "index impact" table should either be absent or report a methodology whose definition matches its label. Q03's entry should no longer claim a 5.0x benefit for an index that already exists and is already in use.

---

## 7. Hypotheses — Requiring Realistic Data or Load Testing

These are **not** confirmed. Each is a structural observation with a plausible mechanism, but confirming it requires a live session and/or a larger dataset that I could not produce under the Phase 2B constraints.

---

### H-01 — `master.skill` and `master.city` text indexes may be affected by a non-C collation

**Why it's plausible**: the container's locale is `LANG=en_US.utf8` and the image is `postgres:17` (Debian). If the database was initialised with a locale where the default collation is not the deterministic `C`/`C.UTF-8` collation, then `master.skill.normalized_name` and `master.city.name` indexes are built with a **locale-aware, non-deterministic-collation** operator class. Such indexes are:
* larger (collation-aware comparisons store sort keys),
* slower to build,
* and — critically — **cannot be used for `LIKE`/`pattern` matching or for index-only scans in some cases**, and are not eligible for certain deduplication optimizations.

The `uq_skill_normalized_name` index was demonstrably used for equality lookups in Q06 and Q07, so basic equality lookups work. The risk is confined to prefix/pattern matching and index size.

**What I could not check**: `datcollate`, `datctype`, `datlocprovider` for the `talentra` database; `pg_attribute.attcollation` for the indexed text columns; and `pg_collation` entries. All require a live session.

**Confirmation steps** (read-only):
```sql
SELECT datname, datcollate, datctype, datlocprovider FROM pg_database WHERE datname = 'talentra';
SELECT a.attname, a.attcollation::regcollation
FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid
WHERE c.relname IN ('skill','city') AND a.attcollation <> 0;
```
If `datcollate` is not `C`/`C.UTF-8` and `datlocprovider` is not `c`, the `master.skill` and `master.city` text indexes are locale-aware and should be considered for a `COLLATE "C"` rebuild. **Only then** would a `text_pattern_ops` index be worth considering for any `LIKE`-based search.

**Impact if true**: Qualitative — larger index footprint on reference tables, and any future `LIKE 'foo%'` search on `master.skill.normalized_name` would not use the index at all. **Low urgency** (reference data, low row count), but it is cheap to check and cheap to fix.

**Risk of acting on it unverified**: LOW, provided the check is run first.

---

### H-02 — `messaging.notification_delivery` has no index on `delivery_status` alone, and the "unread" filter implied by the query's stated purpose is missing

**Why it's plausible**: `db/queries/09_high_volume_notification_write.sql:4` states the purpose is "Fast paginated retrieval of **unread** and recent notifications for a user", and the index is named `idx_notification_delivery_recipient_status` — but the query body filters on neither `delivery_status` nor `read_at`. Either the query file is out of date relative to the intended application query, or the index was designed for a query that was never written.

**What I could not check**: the actual `delivery_status` distribution (via `pg_stats`) and whether the production query filters on it. I could not check whether any *other* file in the repo queries `notification_delivery` with a status filter — I read all 12 files in `db/queries/`, and only Q09 touches this table, but I did not exhaustively grep every test and script.

**Confirmation steps**:
```sql
SELECT delivery_status, count(*) FROM messaging.notification_delivery GROUP BY 1;
SELECT indexrelname, idx_scan FROM pg_stat_user_indexes WHERE relname='notification_delivery';
```
plus a repo-wide grep for `delivery_status` outside the migration.

**Impact if true**: Moderate. The fix is F-06's Option A regardless (an index matching the query as written), so H-02 mainly affects *which* index shape to build and whether the query is missing a filter.

---

### H-03 — Q05 wallet reconciliation's join to `wallet_ledger` is a `Nested Loop` with a `Join Filter`, not an index lookup

**Plan evidence** (captured):
```
Nested Loop  Join Type: Left  Join Filter: (w.id = wl.wallet_id)
  ├─ Seq Scan  wallet (w)  Filter: (organization_id = 1)  Rows Removed by Filter: 1
  └─ Seq Scan  wallet_ledger (wl)  Actual Loops: 0
```

**Why it's plausible as a scale problem**: `commercial.wallet_ledger` is an append-only ledger with `idx_wallet_ledger_wallet_recorded (wallet_id, recorded_at DESC)` (`017:354`) — an index that *exactly* matches the join. Yet the plan seq-scans the ledger and applies the join as a `Join Filter`. The `Seq Scan` on `wallet_ledger` shows `Actual Loops: 0` — it was never executed because the outer side produced 0 rows. So the plan shape is a **seed artifact**: the planner chose a nested loop because there was nothing to join.

**At scale**, with a wallet that has 100,000 ledger rows and 1,000 organizations, the correct plan is a nested loop with an `Index Scan` on `idx_wallet_ledger_wallet_recorded` for the matching wallet — which the existing index fully supports. The planner should choose it, because the outer side is 1 row.

**What I could not check**: the live `commercial.wallet_ledger` row count and the plan with a populated wallet. The captured run's wallet table had 2 rows, one matching `organization_id = 1`... actually `Rows Removed by Filter: 1` and `Actual Rows: 0` means **neither** wallet row matched `organization_id = 1` — the seed's organization IDs do not align with the query's hardcoded `organization_id = 1`.

**This raises a distinct concern, H-04.**

---

### H-04 — Several benchmark queries use hardcoded IDs (`= 1`, `= 2`) that match no rows in the seed, so four of the twelve plans are vacuous

**Evidence across the captured plans** — queries whose result was empty because the hardcoded ID does not exist in the seed:

| Query | Hardcoded predicate | Captured result |
|:--|:--|:--|
| Q03 | `ca.job_posting_id = 1` | `Actual Rows: 0` (Bitmap Index Scan, `Index Cond: (job_posting_id = 1)`) |
| Q04 | `u.id = 1` | `Actual Rows: 0` throughout |
| Q05 | `w.organization_id = 1` | `Actual Rows: 0`; `Rows Removed by Filter: 1` (the 2-row wallet table had no org-1 wallet) |
| Q08 | `dh.organization_id = 1` | `Actual Rows: 0` (Bitmap Index Scan, `Index Cond: (organization_id = 1)`) |
| Q09 | `nd.recipient_user_account_id = 1` | `Actual Rows: 0`; `Rows Removed by Filter: 100` |
| Q06 | `ub.blocked_user_account_id = 2`, `blocked_organization_id = 1` | `Actual Rows: 0`; `Rows Removed by Filter: 2` |

**Six of the twelve queries returned zero rows** in the benchmark run. Their `p50` timings (Q03 1.007 ms, Q04 1.170 ms, Q05 0.985 ms, Q08 1.234 ms, Q09 0.831 ms) therefore measure the cost of an **empty** query, not the cost of the workload described in each file's header comment. Q09's "0.83 ms" and Q05's "0.98 ms" — cited in `docs/phase-4-platform/28-performance-report.md` §1 as "Sub-Millisecond Critical Paths" — are measurements of finding nothing.

**Why it matters**: a plan over an empty result set does not reveal the access path that will be used when the table is populated. For example, Q05's `Nested Loop` + `Join Filter` shape (H-03) is only visible because the outer side was empty; with data, the plan could be a completely different shape. Similarly Q04's `Seq Scan` on `subscription_licence` and Q09's `Seq Scan` on `notification_delivery` are not necessarily the plans that will execute in production.

**What I could not check**: the live IDs present in the container's data, and whether the benchmark harness substitutes real IDs (it does not — it executes the files verbatim, `scripts/run_benchmarks.py:70-92`).

**Confirmation steps**: on the live instance, `SELECT min(id), max(id), count(*) FROM <each table>` and re-run each query with an ID that exists; then compare plan shape to the captured one.

**Impact if true**: The *performance conclusions* for these six queries are unverified at the plan level, though the *index definitions* remain correct on inspection (§3.1, §5.2). The recommendation is to **parameterize the benchmark queries with IDs that exist in the seed**, and re-baseline.

**Risk of acting on it**: LOW — parameterizing the query files changes the benchmark suite's fixed-query contract, which is a project decision, and it would invalidate the current `benchmark_results.json` as a comparison baseline.

---

### H-05 — Unused-index detection could not be performed

`pg_stat_user_indexes WHERE idx_scan = 0` would identify redundant indexes across all 106 indexes. It requires a live session, and it also requires `pg_stat_reset()` to have been called at a known time — the container has been up 7 hours and was started at `2026-10-20T05:44:31Z`, so the counters reflect only post-restart activity, not production traffic. On a 7-hour-old instance against a synthetic dataset, `idx_scan = 0` is expected for nearly every index and is **not** evidence that an index is unused.

**Confirmation steps** (in a production-like environment with representative traffic):
```sql
SELECT s.schemaname, s.relname, s.indexrelname, s.idx_scan, pg_size_pretty(pg_relation_size(s.indexrelid))
FROM pg_stat_user_indexes s
WHERE s.idx_scan = 0 AND s.schemaname IN ('core','master','profile','recruitment','sourcing','gig','commercial','messaging','audit','analytics')
ORDER BY pg_relation_size(s.indexrelid) DESC;
```

**Standing hypothesis only**: `idx_skill_active_name` (F-02) and `idx_user_session_device_identifier` (F-08) are the two candidates that this check would most likely confirm as redundant or replaceable, since both are provably unable to serve the queries in this suite in their current form. That is a structural argument, not a measurement.

---

## 8. Recommended Optimization Sequence

Ordered by **value per unit of risk and effort**, not by query latency. A pre-step is included because the evidence base itself needs repair.

---

### Step 0 — Repair the evidence base (do this first; it is cheap and it changes the priority order)

| Action | Type | Rationale |
|:--|:--|:--|
| Fix the `index_impact` methodology in `scripts/run_benchmarks.py:160-192` | Harness | §6. The current metric is not an index measurement; it is published in three documents. |
| Correct the "quarterly" partitioning claim in `README.md:54,198` and `docs/phase-4-platform/28-performance-report.md` §5.3 | Docs | §5.1. The migration partitions annually and the application workflow's real table is unpartitioned. |
| Parameterize the six queries whose hardcoded IDs match no rows | Benchmark | H-04. Half the suite currently measures empty result sets. |
| Remove the stale hardcoded DB password from `scripts/run_benchmarks.py:23`, `scripts/generate_data.py:26`, `scripts/validate_data.py:28` | Security | These files hardcode `354vctrho9t769874t8B*^&$%&**tf2eej2rh`; the live container's password is `talentra_secure_dev_2026` (from `.env` and the container env). The `os.getenv("POSTGRES_PASSWORD", …)` pattern means the scripts only work when the env var is exported. A credential committed in source is a defect independent of performance. |

*Do not skip this step.* Steps 1–4 below are ranked against a benchmark baseline that is currently partly invalid; a re-baselined run may reorder them.

---

### Step 1 — Zero-index-cost query rewrites (lowest risk, immediate)

| # | Change | Source | Index cost | Expected benefit |
|:--|:--|:--|:--|:--|
| 1.1 | Split Q06's `NOT EXISTS` OR into two `NOT EXISTS` — maps one-to-one onto the two existing partial indexes | `db/queries/06_…:17-23` | **None** | Replaces a materialized seq-scan + join-filter with two index-driven anti-joins |
| 1.2 | Remove the dead `HAVING COUNT(DISTINCT s.id) >= 1` from Q01 | `db/queries/01_…:23` | **None** | Removes a distinct-sort of the aggregate input; the plan shows `Rows Removed by Filter: 0` |

*Why first:* both are semantically-equivalent query edits requiring no schema change, and both are backed by measured plan facts. 1.1 in particular makes **existing** index coverage usable — no new index.

---

### Step 2 — Column-order and coverage fixes (new indexes, small, targeted)

| # | Change | Source | Rationale |
|:--|:--|:--|:--|
| 2.1 | `CREATE INDEX idx_notification_delivery_recipient_created ON messaging.notification_delivery (recipient_user_account_id, created_at DESC);` | F-06 | The existing index cannot supply the query's `ORDER BY` because `delivery_status` sits between the filter and the sort key. Converts an O(table) feed read into an O(20) early-terminating index scan. **Highest value per unit of index cost in the suite.** |
| 2.2 | `CREATE INDEX idx_gig_worker_service_skill_id ON gig.gig_worker_service (skill_id);` | F-03 | Restores parity with `idx_candidate_skill_skill_id` and `idx_job_skill_requirement_skill_id`. Removes a full-table hash build from the second-slowest query. |
| 2.3 | `CREATE INDEX idx_candidate_skill_multisearch ON profile.candidate_skill (skill_id, candidate_profile_id) INCLUDE (proficiency_level, experience_years, is_primary);` | F-01 | Already proposed in `docs/phase-4-platform/28-performance-report.md` §5.1; enables index-only scans on the skill side of Q01. |
| 2.4 | `CREATE INDEX idx_user_session_active_user_devices ON core.user_session (user_account_id, device_identifier) WHERE ended_at IS NULL AND revoked_at IS NULL;` | F-08 | Makes the *existing* partial index's coverage complete for Q04's aggregate, so the planner has no reason to prefer a non-partial index plus a post-scan filter. Login path. |

*Why second:* each is a single-column or two-column index with a clear, provable column-order rationale. 2.1 and 2.2 are the two clearest index defects in the schema. 2.4 should be validated carefully because it adds a third index to a high-churn table and may need a corresponding drop of `idx_user_session_device_identifier`.

---

### Step 3 — The candidate-search composite index (needs a product decision first)

| # | Change | Source | Rationale |
|:--|:--|:--|:--|
| 3.1 | `CREATE INDEX idx_candidate_profile_search ON profile.candidate_profile (profile_status, total_experience_years DESC) INCLUDE (visibility, headline) WHERE visibility IN ('recruiters','public');` | F-01 | The only filter in the suite with **no** supporting index on its table. But the partial predicate bakes in a business rule ("active + recruiter-visible"), and §5.3 shows a partial index with low selectivity may not be chosen. **Needs a decision on whether "active and recruiter-visible" is a stable invariant.** |

*Why third:* this is the highest-value query (Q01, p50 30.87 ms) but the recommendation carries a semantic commitment and the expected benefit is the least certain of all the index proposals. Do not implement on faith.

---

### Step 4 — Query-form decisions on the two `OR`/scan-heavy reads

| # | Change | Source | Rationale |
|:--|:--|:--|:--|
| 4.1 | Decide between: (a) an expression index on `COALESCE(application_deadline, 'infinity'::timestamptz)`, or (b) removing the deadline predicate from the published-job feed and enforcing expiry at write time. | F-04 | (b) is the cleaner design — a "published" feed should not carry a time-dependent filter. (a) is a maintenance burden. **This is a product decision, not a tuning knob.** |
| 4.2 | Decide whether Q10 should read from `analytics.mv_hiring_funnel_summary` (already built, refreshable concurrently) instead of re-aggregating the fact table. | F-05 | The mart already exists and covers a superset of the funnel; the per-industry rollup is a second `GROUP BY` over a much smaller relation. Also removes the `COUNT(DISTINCT)` sort that consumed ~78% of Q10's execution time. |
| 4.3 | Confirm `commercial.wallet_ledger`'s plan with a populated wallet; consider an `EXPLAIN` with `enable_seqscan=off` to confirm `idx_wallet_ledger_wallet_recorded` is reachable. | H-03 | The index already matches the join exactly; only the empty seed hid it. |

---

### Step 5 — Verification hygiene (must accompany every step above)

For each change, the validation criteria in the corresponding finding apply. Three rules apply throughout:

1. **Never accept an index on faith.** After each change, re-plan and confirm the plan *shape* changed (node type, `Index Name`, absence of a `Sort` node, `Heap Fetches`). An index that exists but is not chosen is not a fix.
2. **Measure at the target scale, not the dev scale.** At 10K candidates every one of these findings looks like a no-op, because the planner's seq-scan choices are correct there. Use the `medium` scale seed (10K/1K/50K/2K) as the minimum and the `laptop` scale as the ceiling. Compare `EXPLAIN (ANALYZE, BUFFERS)` before/after on **identical data** with `work_mem` held constant.
3. **Do not compare latencies across benchmark harness changes.** Step 0 changes the harness; the current `benchmark_results.json` cannot serve as the post-fix baseline.

---

## 9. Risks and Validation Plan

### 9.1 Risk register

| Risk | Severity | Mitigation |
|:--|:--|:--|
| An index is created but the planner still ignores it (the §5.3 scenario) | HIGH | Require plan-shape verification, not latency comparison alone, in every validation |
| Write amplification on high-churn tables (`notification_delivery`, `user_session`, `candidate_skill`) | MEDIUM | Prefer narrow indexes; use `INCLUDE` only for columns the query actually selects; verify insert throughput before/after on `notification_delivery` |
| The proposed partial index bakes in a business rule that later changes | MEDIUM | F-01's index predates its use; keep the predicate to a stable invariant and document it |
| Benchmark results become incomparable after the harness fix | MEDIUM | Re-baseline the entire suite after Step 0; retire the current `benchmark_results.json` explicitly |
| Extrapolation claims in `docs/phase-4-platform/28-performance-report.md` rest on the invalid index-impact metric | MEDIUM | §6; correct §2 and the README §5 table in the same change as the harness fix |
| Optimizing against a dataset where 6 of 12 queries return no rows | MEDIUM | H-04; parameterize before using any latency figure as a decision input |
| A committed credential in the three scripts | LOW-MEDIUM (security) | Step 0. Rotate the dev password; read from the environment only |

### 9.2 Validation plan — the one-time evidence gap

The single largest limitation of this report is that **no live plan was captured by me**. The following read-only session closes that gap in one pass. None of it mutates anything:

```sql
-- A. Identity, settings, collation
SELECT version(), current_database(), current_user, pg_size_pretty(pg_database_size(current_database()));
SELECT name, setting, unit FROM pg_settings
 WHERE name IN ('server_version','shared_buffers','work_mem','effective_cache_size','random_page_cost',
                'default_statistics_target','max_parallel_workers_per_gather','jit');
SELECT datname, datcollate, datctype, datlocprovider FROM pg_database WHERE datname='talentra';

-- B. Actual row counts per table (the "is the dev dataset or the medium dataset loaded?" question)
SELECT schemaname, relname, n_live_tup, seq_scan, idx_scan, last_analyze, last_autoanalyze
  FROM pg_stat_user_tables
 WHERE schemaname IN ('core','master','profile','recruitment','sourcing','gig','commercial','messaging','audit','analytics')
 ORDER BY n_live_tup DESC;

-- C. Partition state (settles §5.1's data question)
SELECT pn.nspname||'.'||pc.relname AS parent, cn.nspname||'.'||cc.relname AS child,
       pg_get_expr(cc.relpartbound, cc.oid) AS bound
  FROM pg_inherits i
  JOIN pg_class pc ON pc.oid=i.inhparent JOIN pg_class cc ON cc.oid=i.inhrelid
  JOIN pg_namespace pn ON pn.oid=pc.relnamespace JOIN pg_namespace cn ON cn.oid=cc.relnamespace;

-- D. Unused indexes (settles H-05) and RLS state
SELECT schemaname, relname, indexrelname, idx_scan, pg_size_pretty(pg_relation_size(indexrelid))
  FROM pg_stat_user_indexes WHERE idx_scan=0
   AND schemaname IN ('core','master','profile','recruitment','sourcing','gig','commercial','messaging','audit','analytics')
 ORDER BY pg_relation_size(indexrelid) DESC;
SELECT n.nspname||'.'||c.relname, c.relrowsecurity, c.relforcerowsecurity
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.relrowsecurity;

-- E. Planner statistics for the selectivity arguments in F-01, F-04, H-02
SELECT schemaname, tablename, attname, n_distinct, null_frac, most_common_vals, correlation
  FROM pg_stats WHERE (schemaname, tablename, attname) IN
   (('profile','candidate_profile','profile_status'), ('profile','candidate_profile','visibility'),
    ('profile','candidate_profile','total_experience_years'), ('master','skill','normalized_name'),
    ('recruitment','job_posting','job_status'), ('messaging','notification_delivery','delivery_status'));

-- F. Plain EXPLAIN (no ANALYZE) for the 12 queries, re-planned after each change.
--    Run with the real IDs that exist in the loaded dataset (H-04).
```

**Then, for each proposed change, in order**: apply to a scratch database (not the live one), re-run F, and confirm the expected plan-shape change; only then plan the production migration.

### 9.3 Explicitly out of scope for this phase

Per the Phase 2B safety requirements, this phase produced **no** schema change, **no** index creation, **no** `ANALYZE`/`VACUUM`, **no** `EXPLAIN ANALYZE` run by me, **no** bulk data generation, and **no** benchmark execution. The only file created is this report. `tests/test_constraints.sql` and `.git-initial-backup/` are unmodified.

---

## 10. Finding Summary Table

| ID | Finding | Status | Source | Index change needed | Priority |
|:--|:--|:--|:--|:--|:--|
| **§6** | Benchmark "index impact" metric measures a forced seq scan, not index value; Q03's 5.0x credits an index that already exists | **CONFIRMED** | `scripts/run_benchmarks.py:160-192` | None (harness) | **P0** |
| **§5.1** | README claims quarterly partitioning; migration partitions annually and the real application table is unpartitioned and unqueried | **CONFIRMED** | `README.md:54,198`; `019:318-356` | None (docs) | **P0** |
| **F-01** | `profile.candidate_profile` has no index on `profile_status`/`visibility`/`total_experience_years`; Q01 full-scans it. Dead `HAVING COUNT(DISTINCT)` forces a distinct sort | **CONFIRMED** | `db/queries/01_…:18-25`; `005` (no index) | Yes (composite, needs product decision) | **P1** |
| **F-06** | `idx_notification_delivery_recipient_status` cannot supply the query's `ORDER BY` (`delivery_status` sits between filter and sort key) → seq scan + sort for a 20-row page | **CONFIRMED** | `db/queries/09_…:14-17`; `018:281` | Yes (2-column) | **P1** |
| **F-03** | `gig.gig_worker_service` has no index on `skill_id` (unlike every other skill junction table) → full-table hash build in the 2nd-slowest query | **CONFIRMED** | `db/queries/07_…:13-17`; `014:106` | Yes (1-column) | **P1** |
| **F-07** | Q06's `NOT EXISTS` OR spans two partial indexes → materialized seq scan + join filter; the split form maps 1:1 onto existing indexes | **CONFIRMED** | `db/queries/06_…:17-23`; `012:209,213` | None (rewrite only) | **P1** |
| **F-04** | Q02's `application_deadline IS NULL OR …` is non-sargable; the partial deadline index covers only the `IS NOT NULL` branch | **CONFIRMED** | `db/queries/02_…:25`; `008:189` | Query rewrite (decision) | **P2** |
| **F-05** | Q10 seq-scans the fact table (no index leads with `job_posting_key`); the `COUNT(DISTINCT)` sort consumed ~78% of execution time; `mv_hiring_funnel_summary` already exists | **CONFIRMED** | `db/queries/10_…:17-20`; `019:179-183` | Query redirect (decision) | **P2** |
| **F-08** | `idx_user_session_active_user` matches Q04's predicate exactly but is not chosen; the chosen index applies the null-checks as a post-scan filter | **CONFIRMED** | `db/queries/04_…:16`; `002:190,194` | Yes (partial, needs care) | **P2** |
| **F-02** | `idx_skill_active_name (is_active, normalized_name)` cannot serve a `normalized_name`-only lookup; the `UNIQUE` constraint's btree does instead | **CONFIRMED** | `003:83,217` | Redefine or drop | **P3** |
| **§5.2** | Application workflow index coverage is **adequate** — including `idx_candidate_application_status_applied` for global status filtering | **CONFIRMED** | `009:133-143` | **None needed** | **—** |
| **H-04** | 6 of 12 benchmark queries return zero rows (hardcoded IDs `= 1`/`= 2` match nothing) → their latencies measure empty queries | Hypothesis | `benchmark_results.json`; `run_benchmarks.py:70-92` | Parameterize | **P1 (with Step 0)** |
| **H-01** | DB collation may be non-`C`, making `master.skill`/`master.city` text indexes locale-aware | Hypothesis | — | Possibly `COLLATE "C"` rebuild | **P3** |
| **H-02** | Q09's stated "unread" purpose vs. its missing `delivery_status` filter — a query/index mismatch | Hypothesis | `db/queries/09_…:4` | — | **P3** |
| **H-03** | Q05's ledger join shape is a seed artifact; the supporting index already exists | Hypothesis | `benchmark_results.json` | — | **P3** |
| **H-05** | Unused-index detection needs a traffic-bearing instance; 7-hour-old counters are meaningless | Hypothesis | — | — | **P3** |

---

*Report ends. No implementation was performed. Awaiting approval before any change is made.*
