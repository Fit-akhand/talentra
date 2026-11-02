# Test Automation: data quality, business rules and NFRs (Steps 26, 27, 28)

**Phase:** 4 Platform. Hand-written; the numbers in it are copied from generated results named in each section, which are the source of truth. The older reports in this folder (`28-performance-report.md`, `28-query-performance-validation.md`) are kept as history and carry their own supersession banners.

## 1. What runs, and what it catches

| Stage | Command | Catches | Evidence it works |
|:--|:--|:--|:--|
| Migrations on an empty database | `for f in db/migrations/*.sql; do psql -v ON_ERROR_STOP=1 -f $f; done` | A migration that does not apply, or depends on something not yet created | 39 of 39 apply on PostgreSQL 17.11 |
| SQL suites (34) | `scripts/run_all_tests.py` | A constraint, trigger, policy or function that stopped doing its job. Each suite rolls back | Several suites were shown to fail when the rule they test was broken on purpose (typo guard, golden suite, state machines, enumerations) |
| Concurrency suite | `tests/test_concurrency.py` (own scratch database) | Races: device limit, overlapping gig bookings, wallet debits, the wallet function under 40 simultaneous callers | 4 tests; stable over repeated runs |
| Golden-dataset KPIs | `tests/test_golden_kpis.py` | A KPI query that no longer returns the hand-computed answer | 16 of 16 |
| Identifier crypto | `tests/test_identifier_crypto.py` | A change that breaks canonical forms, the blind index or the AEAD binding | |
| NFR measurements | `scripts/run_nfr_checks.py` (called by `run_all_tests.py`) | Write latency, 500-session concurrency, master lookups and a 50,000-application pipeline slower than their targets | See section 4 |
| Data-quality validator | `scripts/validate_data.py` | Bad data in a seeded database: formats, references, ledgers, hashes | 15 of 15 |
| Table scorecard | `scripts/lifecycle/gen_quality_scorecard.py` | A table without a key, definition, classification, lifecycle policy, indexed foreign key or seed rows | 113 of 113 tables at 7 of 7 ([`26-table-quality.md`](26-table-quality.md)) |
| Test tags | `scripts/lifecycle/tag_tests.py --check` | A test that names no requirement, or a requirement with no test | |
| Generated documents | `scripts/lifecycle/regenerate.sh` then `git diff` | A document that no longer matches the database | |
| Load test | `scripts/run_load_test.py` (weekly or on demand in CI) | Errors, wallet drift or device-limit breaches under a mixed concurrent workload; where latency starts to rise | See section 5 |

`.github/workflows/ci.yml` runs all of the above except the load test on every push; the load test runs weekly and on demand. **The workflow has not run on GitHub**: everything above was run locally against PostgreSQL 17.11 in Docker, with the same commands.

## 2. Step 26: data quality

Two layers. The validator (15 checks across the ten rule groups) judges the **data** after a seed. The scorecard judges each **table's design** against seven properties read from the catalog. They overlap deliberately only where a design defect shows up as bad data. Writing the scorecard found 41 tables whose foreign keys led no index and 5 tables with no seed rows; migration 039 and the seed fixed the first, the seed the second, and three exemptions are recorded (DEC-33: audit actor columns, master references and the analytics schema do not need an index; the maintenance log and the sync-conflict log are written by jobs, not by a seed).

## 3. Step 27: business rules

Every rule in [`18-business-rules-catalogue.md`](../phase-3-prove/18-business-rules-catalogue.md) names its test file, the generator checks the file exists, and `tag_tests.py --check` checks the other direction. The four-row device decision table (BR-002) is tested in full.

## 4. Step 28: NFRs

Source: [`benchmarks/results/nfr_results.md`](../../benchmarks/results/nfr_results.md) (PostgreSQL 17.11, loopback, default configuration).

| NFR | Result | Target |
|:--|:--|:--|
| NFR-003 single-row write with trigger and commit | p95 0.63 ms | 50 ms |
| NFR-005 concurrent logins | 500 of 500 users in 1.1 s; one user, 500 attempts, 2-device limit: exactly 2 succeed | 0 breaches |
| NFR-006 master lookup | p95 0.19 ms | 5 ms |
| NFR-009 pipeline funnel over 50,009 applications | p95 7.7 ms | 25 ms |

The twelve benchmark queries ([`benchmarks/results/benchmark_summary_v2.md`](../../benchmarks/results/benchmark_summary_v2.md) at 10,000 candidates; [`benchmark_summary_v2_laptop.md`](../../benchmarks/results/benchmark_summary_v2_laptop.md) at the docket's 1,000,000) all return real rows; the slowest at the laptop scale is the gig availability search at 14 ms. Backup and restore at 11 GB: 71 s and 224 s against a 900 s objective ([`scale_comparison.md`](../../benchmarks/results/scale_comparison.md)). Those two laptop-scale results are from PostgreSQL 16.15 before migrations 029 to 039 and have not been repeated.

## 5. Load test

Source: [`benchmarks/results/load_test.md`](../../benchmarks/results/load_test.md). Mix: search 25%, job feed 25%, funnel 10%, application insert 15%, wallet debit 10%, login 15%, from 1, 8, 32 and 64 concurrent clients on the medium dataset, one funded wallet per client.

| Clients | ops/s | errors | worst p95 |
|--:|--:|--:|--:|
| 1 | about 1,800 | 0 | 0.8 ms |
| 8 | about 8,400 | 0 | 1.9 ms |
| 32 | about 10,800 | 0 | 7.0 ms |
| 64 | about 10,500 | 0 | 18.5 ms |

Throughput stops rising between 32 and 64 clients (the machine has 10 CPUs and the client is Python), and latency climbs steeply there; every p95 stays under its target at every level. After the run no wallet differs from its ledger and no user exceeds the device limit.

**Limits.** The client and the server share a machine. Queries run as the table owner, so row-level-security cost is not in the numbers. One wallet per client hides the worst case, a single organisation's wallet debited by many callers at once; the first, hot-wallet version of this test showed its p95 rising to 162 ms at 64 callers, because the wallet row lock serialises them. That is the intended behaviour (it is what prevents an overdraft) and the cost of it. No test was run at 500 simultaneous connections; the server allows 100.

## 6. Not done

- **A run at 500 simultaneous connections** and **a soak test** (hours at a steady rate). Both need a larger server than the one used.
- **A repeat of the laptop-scale run** on the current schema.
- **The 3-year volume** (100 million applications) generated and measured; it is modelled in [`13-volume-sheet.md`](../phase-3-prove/13-volume-sheet.md).
- **Step 25, ingestion**, which the docket puts out of scope.
