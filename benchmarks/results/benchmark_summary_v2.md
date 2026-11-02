# Talentra Database Performance & Benchmark Suite

**Database Engine**: PostgreSQL 16.15 (Homebrew)  
**Dataset**: 10,000 candidate profiles, 1,000 job postings, 50,000 applications  
**Host**: macOS-27.0.1-arm64-arm-64bit, 10 CPUs  
**Methodology Version**: 2.0 (`v2`)  
**Generated At (UTC)**: 2026-10-26T22:54:23Z  
**Sample Count**: 10 timed iterations per query (+ 2 warmup runs)  
**Supersedes**: `benchmarks/results/benchmark_results.json (methodology v1, unlabelled 'index_impact' metric); the v1 artifact is retained unmodified as historical evidence`  

> **How to read this report**
>
> * Section 1 is the **baseline** measurement (`measurement_role: baseline`): the query running against the current schema under the default planner configuration. These numbers are the reference point, not the result of an index change.
> * Section 2 is a **diagnostic** planner-method comparison (`measurement_role: diagnostic`). It compares the default plan with a plan where the planner has been denied every index access path. It measures the cost of that denial, and it does **not** attribute any speedup to a named index.
> * Section 3 lists the benchmark cases whose result set was empty or which were skipped. Their latencies are **not** workload measurements.

## 1. Baseline Latency Profile (measurement_role: baseline)

| Query | Purpose / Workload | Result Validity | Rows | p50 (ms) | p95 (ms) | p99 (ms) | Mean (ms) | Buffer Hit Ratio |
| :--- | :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| `01_candidate_multicriteria_search.sql` | Find active candidates matching required skills, minimum experience, and location with visibility restrictions. | valid_non_empty | 50 | **0.983** | **1.049** | 1.071 | 0.992 | 100.0% |
| `02_job_feed_matching.sql` | Candidate job recommendation feed matching active jobs by role, work arrangement, location, and salary filter. | valid_non_empty | 50 | **0.358** | **0.369** | 0.37 | 0.36 | 100.0% |
| `03_recruiter_pipeline_funnel.sql` | Recruiter dashboard aggregation displaying applicants by stage for an active job requirement. | valid_non_empty | 7 | **0.246** | **0.279** | 0.289 | 0.249 | 100.0% |
| `04_concurrent_session_validation.sql` | Evaluate user active devices and session limits against licence entitlements during login. | valid_non_empty | 1 | **0.146** | **0.152** | 0.154 | 0.146 | 100.0% |
| `05_wallet_ledger_reconciliation.sql` | Verify cached wallet balance matches the append-only ledger transaction history exactly. | valid_non_empty | 1 | **0.13** | **0.135** | 0.136 | 0.131 | 100.0% |
| `06_sourcing_outreach_unblocked.sql` | Find candidate candidates for outreach excluding any candidate who has blocked the recruiter or organization. | valid_non_empty | 50 | **0.352** | **0.437** | 0.452 | 0.369 | 100.0% |
| `07_non_overlapping_gig_worker_search.sql` | Find available gig workers with matching skill whose calendar has availability and NO overlapping active assignments. | valid_non_empty | 25 | **1.49** | **1.546** | 1.559 | 1.5 | 100.0% |
| `08_profile_download_audit_log.sql` | Retrieve append-only history of candidate profile downloads by recruiters with billing deductions. | valid_non_empty | 8 | **0.164** | **0.166** | 0.166 | 0.162 | 100.0% |
| `09_high_volume_notification_write.sql` | Fast paginated retrieval of unread and recent notifications for a user. | valid_non_empty | 6 | **0.082** | **0.083** | 0.084 | 0.082 | 100.0% |
| `10_analytics_time_to_hire_kpi.sql` | Average time from application to joining, and how many applications reached each stage, by industry. | valid_non_empty | 12 | **0.062** | **0.072** | 0.072 | 0.065 | 100.0% |
| `11_gig_revenue_and_rating_summary.sql` | Aggregate total platform earnings, completed projects, and average rating per currency and status. | valid_non_empty | 2 | **0.217** | **0.223** | 0.224 | 0.217 | 100.0% |
| `12_multilingual_ui_translation_lookup.sql` | Bulk fetch interface translations for a given language code with fallback to default English. | valid_non_empty | 4 | **0.107** | **0.11** | 0.11 | 0.106 | 100.0% |

## 2. Diagnostic: Cost of Disabling Index Access Paths (measurement_role: diagnostic)

This section is not an index-benefit measurement. Each row compares the default planner configuration with the same query run under `enable_indexscan = off; enable_bitmapscan = off; enable_indexonlyscan = off;`. The second configuration is a deliberately crippled plan; it is not equivalent to "the schema without the index", and it credits no index with a speedup. The ratio is *disabled latency divided by default latency*: values above 1.0 mean the crippled plan was slower.

| Query | Indexes Observed in Baseline Plan | Default Plan (ms) | Index Access Paths Disabled (ms) | Disabled / Default Ratio |
| :--- | :--- | :---: | :---: | :---: |
| `01_candidate_multicriteria_search.sql` | `idx_candidate_profile_search_order`, `idx_candidate_skill_profile_primary`, `pk_skill` | 1.001 ms | 44.57 ms | 44.53 |
| `03_recruiter_pipeline_funnel.sql` | `idx_candidate_application_job_status` | 0.295 ms | 1.65 ms | 5.59 |
| `07_non_overlapping_gig_worker_search.sql` | `ex_gig_assignment_no_overlap`, `idx_gig_worker_availability_profile_dates`, `pk_gig_worker_profile` | 1.505 ms | 1.406 ms | 0.93 |

## 3. Invalid or Skipped Benchmark Cases

No query returned an empty result set and no case was skipped in this run.

