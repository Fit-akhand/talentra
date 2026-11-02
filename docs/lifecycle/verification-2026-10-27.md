# Verification Record: 2026-10-27

**Lifecycle steps:** 14, 15, 20, 21, 23, 24, 26, 28, 44. **Gates touched:** G3, G4.
The Phase 3 gate review recorded every suite as unverified because no database was reachable. This record is what happened when they were run, what the run found, and what was done about it. It was updated after the rebuild (migrations 020 to 027); the first run's findings are kept, with their outcome.

## Environment

| Item | Value |
|:--|:--|
| Engine | PostgreSQL **16.15** (Homebrew), throwaway cluster, trust authentication, loopback only |
| Declared target | PostgreSQL **17** (`docker-compose.yml`, CI). The Docker daemon was not available, so **17 was not exercised locally**. |
| Host | macOS, 10 CPUs |
| Isolation | Everything ran against disposable databases; the project's own container and volume were never touched |

## Results after the rebuild

| Check | Command | Result |
|:--|:--|:--|
| Migrations on an empty database | `psql -v ON_ERROR_STOP=1 -f` per file | **28 of 28 apply** (92 tables and 3 partitions at 019; 100 and 3 from 022 on; 028 adds a materialised view and an index) |
| All test suites | `python3 scripts/run_all_tests.py` | **28 of 28 pass**: 25 SQL, concurrency, golden-dataset KPIs, benchmark harness. Run on an empty database, on a dev seed and on a medium seed |
| Golden dataset | `python3 tests/test_golden_kpis.py` | **All 16 KPIs return the hand-computed answer.** Changing one expected value makes it fail (checked) |
| Data validator | `python3 scripts/validate_data.py` | **15 of 15 pass** on a fresh seed, and still pass after the whole test suite has run against the same database |
| Seeding | `python3 scripts/generate_data.py` | dev 0.5 s, medium 8 s. Same seed gives the same shape (checked by comparing status distributions on two fresh databases). A second run is **refused** (exit 2) and changes nothing |
| Coverage of the schema by seed data | row counts after a medium seed | **every base table except `audit.system_error_log` holds rows**; that one is written by the application |
| Backup and restore | `scripts/backup_restore.sh` | medium scale: **102 tables compared, 0 count mismatches, function / trigger / policy / index / constraint counts equal**; restore 1 s against a 900 s objective |
| Benchmarks | `python3 scripts/run_benchmarks.py` | **12 of 12 queries return real rows** on 10,000 candidates, 1,000 jobs, 50,000 applications. Slowest: Query 10 at 26 ms p50 |

## Laptop scale (docket section 6: 1M candidates, 100K jobs, 5M applications)

Loaded, validated, benchmarked, backed up and restored at the docket's laptop scale on 2026-10-27. Full comparison with the medium dataset, the before and after of migration 028, and the projection to 10M / 100M: [`benchmarks/results/scale_comparison.md`](../../benchmarks/results/scale_comparison.md).

| Measure | Result |
|:--|:--|
| Dataset | 1,000,000 candidates; 100,000 jobs; 4,999,836 applications; 9,636,883 status events; 100,000 gig workers; 1,022,500 accounts; **11 GB**; every base table populated except `audit.system_error_log` |
| Load time | `generate_data.py --scale laptop`: **1,414 s (23.6 min)**, on a default-configuration PostgreSQL |
| Validator | **15 of 15 pass** at this scale |
| Benchmarks, before migration 028 | Query 01 candidate search **491 ms**; Query 02 job feed **50 ms**; Query 10 time-to-hire KPI **3,268 ms**; all others under 14 ms. Three queries missed their proposed targets |
| Benchmarks, after migration 028 | Query 01 **0.5 ms**, Query 02 **0.4 ms**, Query 10 **0.07 ms**; every query under 14 ms and none misses a proposed target |
| Migration 028 on the 11 GB database | applied in **4.7 s** |
| Backup and restore | 103 tables, **0 row-count mismatches**, schema-object counts equal; backup 71 s, **restore 224 s** against a 900 s objective |

What this settles: the docket required measurement at laptop scale before any projection. The earlier extrapolation had no measured basis beyond a 500-candidate dataset. It now has two measured sizes 100x apart.

## Defects from the first run, and their outcome

| ID | Finding | Outcome |
|:--|:--|:--|
| V-01 | `test_benchmark_harness.py` failed. Three causes: the report said `**not**` in bold, which broke a text match; the test double replaced "no row" with a default row; a read-only check matched `REVOKE` inside `revoked_at` | All three fixed; suite green |
| V-02 | Seeding twice doubled the data | Generator refuses to seed a populated database; `--append` is the explicit opt-in |
| V-03 | The concurrency suite left committed rows that made the validator fail | It now creates and drops its own scratch database |
| V-04 | A database password was hard-coded as a fallback in four scripts | Removed. It remains in git history, so **rotate it** |
| V-05 | `run_all_tests.py` only worked through one named Docker container | Works against any PostgreSQL through the libpq variables; `--docker` is optional |
| V-06 | "No `ERROR:` in the output" cannot detect a suite that asserts nothing | The runner also fails on `[FAIL]` and `FAIL:` markers. New suites assert a count or a state, and the typo guard and the golden suite were each shown to fail when broken on purpose |
| V-07 | `validate_data.py` printed "PostgreSQL 17" whatever it was connected to | Removed |

## Further findings made while rebuilding

| Finding | How it was found | Outcome |
|:--|:--|:--|
| 91 of 92 tables lacked the docket's audit columns, soft delete and retention | Generated entity catalogue | Migration 020 |
| No roles, no row-level security, empty permission tables, plaintext accepted as a password hash | Requirement register and threat model | Migration 021 |
| The docket's rule groups were reported under a different numbering ("RG7" meant ledgers) | Reading the docket against `11-rule-compliance.md` | Compliance table rewritten with the docket's numbering |
| Three money columns had no currency; user-entered text had no language | Checking each rule group against the live schema | Migration 026 |
| `active_<table>` views had gone stale (missing columns added later) | The new stale-view test | `audit.refresh_active_views()` and a test |
| `master.job_role` was empty, so every job had a NULL role | Listing empty tables after a seed | Migration 027 |
| The star schema was loaded by nothing but the data generator | Writing the KPI catalogue | Migration 023 |
| Query 10 averaged the wrong interval and took 71 ms | Reconciling KPI-003 with the golden dataset | Rewritten: correct and 26 ms |
| `backup_restore.sh` hid restore errors, counted 7 tables, included backup time in the recovery time | Reading it | Rewritten |
| **A SECURITY DEFINER login lookup was executable by every role, so the read-only role could fetch password hashes; the visibility function revealed who had blocked whom** | Reviewing my own migration after the access tests passed | `EXECUTE` revoked from PUBLIC, granted to the application role only; tests added |
| Test fixtures with hard-coded ids (1001, 2001, ...) collided with generated ids | Running the suite on a medium seed | Fixtures use ids above 90,000,000 |

## Not verified

- PostgreSQL 17 locally. The CI workflow targets 17 and has **not run**.
- Behaviour with a real application: nothing here sets `app.current_user_id` except the tests.
- The 10M-profile / 100M-application projection in the performance report remains a model.
- Human-reviewed classification, approved NFR targets and approved retention periods: none exist.
- Tax-identifier encryption: blocked on human decisions.

## Reproduce

```bash
export PGHOST=127.0.0.1 PGPORT=5544 PGUSER=talentra_admin
initdb -D ./pgdata -U talentra_admin --auth=trust -E UTF8 && pg_ctl -D ./pgdata -o "-p 5544 -c listen_addresses=127.0.0.1" start
createdb talentra
for f in db/migrations/*.sql; do psql -d talentra -v ON_ERROR_STOP=1 -q -f "$f"; done
python3 scripts/generate_data.py --scale medium
python3 scripts/run_all_tests.py && python3 scripts/validate_data.py
python3 scripts/run_benchmarks.py && scripts/backup_restore.sh
```
