# Talentra: Job Search and Demand Management Database

PostgreSQL schema, test suite, data generator and design documentation for **Talentra**, a platform that unites permanent and contract recruitment with an on-demand gig marketplace. It was built to the *Talentra Database Design Hackathon* docket and is organised by the phases and steps of the Talencia Global Data-Driven Development Lifecycle.

| | |
|:--|:--|
| Engine | PostgreSQL 17 (target, used by CI and `docker-compose.yml`). Developed and verified locally on 16.15; see *Status* |
| Schema | 39 migrations, 10 bounded schemas, 113 base tables and 9 partitions |
| Tests | 40 suites: 35 SQL suites, a concurrency suite, a golden-dataset KPI suite, a benchmark-harness suite, an identifier-crypto suite and an NFR measurement run |
| Documentation | `docs/`, one folder per lifecycle phase; start at [`docs/README.md`](docs/README.md) |

## Status, stated plainly

- **Verified (2026-10-28, PostgreSQL 17.11 in Docker):** all 39 migrations apply to an empty database; all 40 suites pass; the data validator passes 15 of 15 on a freshly seeded database; generated documents are identical on 16.15 and 17.11. Earlier, on 16.15: backup and restore round-trips with identical row counts and schema objects, and the docket's laptop scale (1M candidates, 5M applications, 11 GB) was loaded, validated, benchmarked, backed up and restored (see [`benchmarks/results/scale_comparison.md`](benchmarks/results/scale_comparison.md)).
- **Not verified:** the CI workflow has not run on GitHub; the laptop-scale run was on 16.15 and before migrations 029 to 039; the 10M / 100M figures are a projection from two measured sizes, not a measurement.
- **Known open items**, all listed in [`docs/lifecycle/step-map.md`](docs/lifecycle/step-map.md): no human has approved anything. Targets, retention periods and the column classification were set by the assistant under the owner's delegation and are recorded in [`docs/lifecycle/decision-log.md`](docs/lifecycle/decision-log.md); the tax-identifier encryption has no consuming application yet and the seed data uses a public development key; the CI workflow has not run on GitHub; availability, backup scheduling and notification sending need an operator.

## Layout

```
db/
  migrations/     001-039, applied in order
  queries/        12 fixed benchmark queries
  kpi/            16 KPI definitions (SQL), executed by tests and the KPI generator
  seeds/          reference data and the golden dataset
tests/            SQL suites, concurrency suite, golden-dataset KPI suite, benchmark-harness suite
scripts/
  generate_data.py       synthetic data (dev / medium / laptop scale, reproducible with --seed)
  validate_data.py       data-quality validator
  run_all_tests.py       runs every suite against any PostgreSQL
  run_benchmarks.py      latency profile with p50/p95/p99 and cache-hit ratio
  backup_restore.sh      backup, restore, verify, time against the RTO
  lifecycle/             generators for the documents under docs/
docs/                    one folder per lifecycle phase, plus gate-reviews and source
.github/workflows/ci.yml migrations, tests, seed, validate, docs-up-to-date check on PostgreSQL 17
```

## What the database enforces

- **Identity and access.** One identity table feeds candidates, employers, recruiters, consultants and gig workers. Five `NOLOGIN` roles and row-level security on twelve tables isolate tenants and candidates: a recruiter sees only their organisation's jobs, wallet and applications; a blocked organisation cannot see the candidate; the organisation context is honoured only for active members. The application sets who is acting with `set_config('app.current_user_id', ...)` per transaction; with nothing set, a session sees only published jobs. Login order: look the credential up with `core.find_credential_for_login`, verify the hash in the application, set `app.current_user_id`, then call `core.create_session_with_device_limit`.
- **Credentials.** Password hashes must be argon2id or bcrypt and session tokens must be SHA-256 hex, by `CHECK`. Support staff see accounts only through a masking view.
- **No double-booking, no over-limit logins.** A `btree_gist` exclusion constraint rejects overlapping active gig assignments and overlapping subscription periods. Device limits are enforced at login under a row lock, and the refused attempt is audited. Both are proven under 10 parallel connections.
- **Append-only history.** The wallet ledger, audit log, download and view history, application status history and error log reject `UPDATE`, `DELETE` and `TRUNCATE`, and the application role has no privilege to attempt them. A correction is a new row that points at the original.
- **State machines.** Legal status moves live in `master.status_transition`; 12 entities (applications, jobs, accounts, gigs, payments, invoices, subscriptions, sourcing requests, tickets) reject any other move.
- **Lifecycle.** Every business table carries `created_at/by` and `updated_at/by`, filled by one trigger. Nine entities are soft-deleted and exposed through `active_<table>` views. `audit.entity_lifecycle_policy` records how each table's rows leave, with proposed retention. `core.erase_user_account` implements the right to erasure.
- **Classification.** Every column has a class (public, internal, personal, sensitive) and a protection status in `audit.column_classification`; a test fails when a new column has none.
- **Analytics.** `analytics.refresh_reporting_marts()` loads the star schema from the operational tables, incrementally and idempotently, then refreshes the aggregates.

## Run it

You need PostgreSQL 16 or later with the `btree_gist` extension, `psql`, and Python 3.9+ with `psycopg2-binary` and `cryptography`. Docker is optional.

```bash
# 1. A database. With Docker (copy .env.example to .env and set POSTGRES_PASSWORD first):
docker compose up -d
# ...or point the standard libpq variables at any PostgreSQL you own:
export PGHOST=127.0.0.1 PGPORT=5432 PGUSER=talentra_admin PGDATABASE=talentra PGPASSWORD=...
```

```bash
# 2. Apply every migration, in order
for f in db/migrations/*.sql; do psql -v ON_ERROR_STOP=1 -q -f "$f"; done
```

```bash
# 3. Run every test suite (SQL suites roll back; the Python suites use their own scratch database)
python3 scripts/run_all_tests.py
```

```bash
# 4. Seed realistic data: dev (500 candidates), medium (10,000), laptop (1,000,000)
python3 scripts/generate_data.py --scale medium
python3 scripts/validate_data.py
```

Seeding a database that already holds candidates is refused, because a second run used to double everything. Re-create the database, or pass `--append` if you want a second copy.

```bash
# 5. Benchmarks, backup/restore, and regenerating the generated documents
python3 scripts/run_benchmarks.py
scripts/backup_restore.sh
scripts/lifecycle/regenerate.sh
```

To run the tests against the Docker container instead of a local `psql`, use `python3 scripts/run_all_tests.py --docker`.

## Performance

Measured on one machine (macOS, 10 CPUs), PostgreSQL 16.15 with default settings, p50 over 10 timed runs. Two datasets, 100x apart: **medium** (10,000 candidates, 50,000 applications) and the docket's **laptop scale** (1,000,000 candidates, 100,000 jobs, 5,000,000 applications, 11 GB). Full table, method, cost of the fixes and a projection to the 10M / 100M target: [`benchmarks/results/scale_comparison.md`](benchmarks/results/scale_comparison.md).

| Query | Medium | Laptop, as first written | Laptop, now |
|:--|--:|--:|--:|
| 01 Candidate multi-criteria search | 6.2 ms | 491 ms | 0.5 ms |
| 02 Job feed matching | 1.4 ms | 50 ms | 0.4 ms |
| 10 Time-to-hire KPI | 26 ms | 3,268 ms | 0.07 ms |
| 07 Gig worker availability | 1.5 ms | 13.5 ms | 13.7 ms |
| 11 Gig revenue and ratings | 0.2 ms | 8.6 ms | 8.7 ms |
| the other 7 queries | 0.1 to 0.3 ms | 0.1 to 1 ms | 0.1 to 1 ms |

Three queries missed their proposed targets at laptop scale and were fixed by migration 028: Queries 01 and 02 by choosing the 50 rows to return before aggregating (Query 01 also needed one partial index), Query 10 by reading a summary that `analytics.refresh_reporting_marts()` rebuilds (about 3 s at this scale), so it is as fresh as the last refresh. Queries 01 and 02 return the same rows in the same order as before. The first thing expected to degrade at the full 10M / 100M target is the cost of rebuilding that summary, which grows with the number of events. The load of the laptop dataset takes 24 minutes; backup is 71 s and restore 224 s against a 900 s objective. The first version of these tables was measured on a dataset where five of the twelve queries returned no rows, and has been replaced.

## Design notes

**Why a single database and not services.** Hiring credits, wallet debits and application state must change together or not at all. In one PostgreSQL database that is one transaction. The concurrency suite shows it holding under contention: 10 parallel logins against a 2-device limit grant exactly 2, and 10 parallel wallet debits never overdraw.

**Where the gig marketplace lives.** Gigs have their own schema (profiles, availability, requests, assignments, ratings) instead of sharing the job and application tables, because their rules differ: a priced window instead of a vacancy, bids that flow one way, fulfilment handed to an external system, and a calendar that must never overlap. The cost is that reporting across both has to join two models; the analytics schema does that join once.

**Partitioning.** `recruitment.candidate_application_partitioned` is range-partitioned by year on `applied_at`. The authoritative table is the unpartitioned `candidate_application`; the partitioned one is the scale-out path and no benchmark query uses it yet.

**What to read next.** [`docs/lifecycle/step-map.md`](docs/lifecycle/step-map.md) for the status of all 46 lifecycle steps and 8 gates; [`docs/phase-2-model/11-rule-compliance.md`](docs/phase-2-model/11-rule-compliance.md) for the docket's ten rule groups with every deviation and its reason; [`docs/phase-2-model/12-threat-model.md`](docs/phase-2-model/12-threat-model.md) for the security design.
