# Talentra: Medium and Laptop Scale, Before and After Migration 028

Measured on one machine (macOS, 10 CPUs), PostgreSQL 16.15 with default settings (128 MB shared buffers), 10 timed runs after 2 warm-ups, p50 in milliseconds.

| Dataset | Candidates | Jobs | Applications | Application events | Size |
|:--|--:|--:|--:|--:|--:|
| Medium | 10,000 | 1,000 | 50,000 | 96,000 | small |
| Laptop (docket section 6) | 1,000,000 | 100,000 | 5,000,000 | 9,636,883 | 11 GB |

Growth from medium to laptop is **100x** in candidates, jobs and applications. A query that scales with its input should grow about 100x; one that grows more is degrading.

## Latency (p50, ms)

| # | Query | Medium, before 028 | Medium, after | Laptop, before 028 | Laptop, after | Growth before (100x data) | Proposed target (p95) |
|--:|:--|--:|--:|--:|--:|--:|:--|
| 01 | Candidate multi-criteria search | 6.24 | 0.98 | 490.98 | 0.50 | 79x | 50 ms |
| 02 | Job feed matching | 1.41 | 0.36 | 50.23 | 0.37 | 36x | 20 ms |
| 03 | Recruiter pipeline funnel | 0.23 | 0.25 | 1.05 | 1.05 | 5x | - |
| 04 | Device limit at login | 0.16 | 0.15 | 0.15 | 0.14 | 1x | - |
| 05 | Wallet reconciliation | 0.13 | 0.13 | 0.12 | 0.12 | 1x | - |
| 06 | Outreach, blocked candidates removed | 0.34 | 0.35 | 0.38 | 0.38 | 1x | 20 ms |
| 07 | Gig worker availability search | 1.49 | 1.49 | 13.48 | 13.69 | 9x | 20 ms |
| 08 | Profile download history | 0.16 | 0.16 | 0.17 | 0.17 | 1x | - |
| 09 | Notification feed | 0.08 | 0.08 | 0.07 | 0.07 | 1x | 20 ms |
| 10 | Time-to-hire KPI | 26.26 | 0.06 | 3267.83 | 0.07 | 124x | 25 ms |
| 11 | Gig revenue and ratings | 0.22 | 0.22 | 8.55 | 8.69 | 39x | - |
| 12 | UI translation lookup | 0.10 | 0.11 | 0.11 | 0.11 | 1x | - |

## Projection to the docket's full scale (a model built on two measured points)

Full scale is 10 million candidates, 1 million jobs and 100 million applications: **10x** the laptop dataset in candidates and jobs and **20x** in applications. With two measured sizes (medium and laptop, 100x apart) each query's growth is fitted as latency proportional to size^k, where k = log(laptop / medium) / log(100), and extended one decade beyond the larger measurement. It assumes the same query plan, the same data distribution and enough memory for the same access pattern; none is guaranteed, and a plan change would invalidate it.

| Query | k (before 028) | Projected at full scale, before 028 | After 028 |
|:--|--:|:--|:--|
| 01 Candidate multi-criteria search | 0.95 | 4.4 s (candidates x10) | stops after 50 qualifying rows: roughly flat while enough candidates qualify early in the index order |
| 02 Job feed matching | 0.78 | 299 ms (jobs x10) | index-ordered, stops after 50: roughly flat |
| 10 Time-to-hire KPI | 1.05 | 75.3 s (events x20) | the query reads 12 rows; the summary refresh grows with events (about 3.2 s x 20 = roughly a minute per refresh) |
| 11 Gig revenue and ratings | 0.79 | 92 ms (x20) | unchanged |
| 07 Gig worker availability search | 0.48 | 41 ms (workers x10) | unchanged |

**Which query degrades first at full scale, and why.** Before migration 028 it is Query 10 (it re-aggregates every event on each call), then Query 01 (it sorts every matching candidate on disk). After 028 neither is a read-path problem; what degrades first is the **cost of rebuilding the summary and loading the marts**, which grow with the number of events. At 20x the events a full refresh would take about a minute: fine on a schedule, not fine on every request, and the next step would be an incremental summary. Queries 07 and 11 come after that; both are under 15 ms at laptop scale.


## What this shows

1. **The query that degrades first is Query 10**, the time-to-hire KPI: 26 ms to 3,268 ms (124x for 100x the data) because it re-aggregated 9.6 million events on every call. The next is **Query 01**, candidate search: 6 ms to 491 ms (79x), because it aggregated the skills of 313,000 matching candidates and sorted them on disk before keeping 50. Query 02 (job feed) grew 36x for the same reason.
2. **Before migration 028, three queries missed their proposed targets at laptop scale** (01: 514 ms p95 against 50 ms; 02: 51 ms against 20 ms; 10: 3,341 ms against 25 ms). After it, none does.
3. **The fixes are not a new index everywhere.** Query 02 needed only a rewrite. Query 01 needed the rewrite plus one partial index. Query 10 now reads a summary rebuilt by the mart refresh, so it is as fresh as the last refresh. Queries 01 and 02 returned the same rows, in the same order, before and after (compared on the laptop dataset).
4. **Queries 03 to 06, 08, 09 and 12 did not move much**, which is what indexed point lookups should do. Query 07 (gig worker search) grew 9x and Query 11 (gig revenue) 39x; both stay under 15 ms.
5. Cache hit ratio before the fix was 5% (Query 01) and 2% (Query 10): the working set no longer fits in the default 128 MB of shared buffers. The figures are for default settings; tuning memory would help the unrewritten forms and was deliberately not done, so the improvement shown is structural.

## Cost of the fixes

| Item | Cost, laptop scale |
|:--|:--|
| `idx_candidate_profile_search_order` | built inside migration 028; the whole migration applies in under 5 s to the 11 GB database |
| `mv_hiring_funnel_by_industry` | refresh about 3.2 s (concurrent, readers not blocked), run by `analytics.refresh_reporting_marts()` |
| Staleness of Query 10 | up to one refresh interval; no scheduler runs it yet |

## Backup and restore at laptop scale

11 GB database, 103 tables: backup 71 s, **restore 224 s against a 900 s objective**, every table's exact row count equal in the restored copy, and function / trigger / policy / index / constraint counts equal.

## Loading the dataset

`python3 scripts/generate_data.py --scale laptop` took **1,414 s (23.6 min)**: candidates 117 s, applications and their pipeline history 812 s, profile detail 111 s, engagement 85 s, structure and audited actions 79 s, star-schema load 153 s. The validator then passed 15 of 15.

## Provenance

`benchmarks/results/benchmark_results_v2.json` is the medium run and `benchmark_results_v2_laptop.json` the laptop run after migration 028. The before column was recorded from the same protocol before 028 was applied; its raw output was not kept as a JSON artifact, so it is a recorded measurement, not a reproducible file. To reproduce it, check out the commit before 028 and run the benchmark on a laptop-scale load.
