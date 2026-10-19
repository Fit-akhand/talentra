# Talentra Database Performance & Benchmark Suite

**Database Engine**: PostgreSQL 17  
**Execution Timestamp**: 2026-10-17T18:31:04Z  
**Sample Count**: 10 timed iterations per query (+ 2 warmup runs)  

## 1. Fixed Query Latency Profile

| Query | Purpose / Workload | p50 (ms) | p95 (ms) | p99 (ms) | Mean (ms) | Buffer Hit Ratio |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| `01_candidate_multicriteria_search.sql` | Find active candidates matching required skills, minimum experience, and location with visibility restrictions. | **30.874** | **34.21** | 35.051 | 31.179 | 100.0% |
| `02_job_feed_matching.sql` | Candidate job recommendation feed matching active jobs by role, work arrangement, location, and salary filter. | **13.29** | **15.439** | 15.449 | 13.589 | 100.0% |
| `03_recruiter_pipeline_funnel.sql` | Recruiter dashboard aggregation displaying applicants by stage for an active job requirement. | **1.007** | **1.951** | 2.327 | 1.15 | 100.0% |
| `04_concurrent_session_validation.sql` | Evaluate user active devices and session limits against licence entitlements during login. | **1.17** | **2.149** | 2.591 | 1.303 | 100.0% |
| `05_wallet_ledger_reconciliation.sql` | Verify cached wallet balance matches the append-only ledger transaction history exactly. | **0.985** | **2.026** | 2.454 | 1.194 | 100.0% |
| `06_sourcing_outreach_unblocked.sql` | Find candidate candidates for outreach excluding any candidate who has blocked the recruiter or organization. | **2.12** | **3.102** | 3.586 | 2.264 | 100.0% |
| `07_non_overlapping_gig_worker_search.sql` | Find available gig workers with matching skill whose calendar has availability and NO overlapping active assignments. | **11.07** | **12.02** | 12.144 | 10.831 | 100.0% |
| `08_profile_download_audit_log.sql` | Retrieve append-only history of candidate profile downloads by recruiters with billing deductions. | **1.234** | **2.126** | 2.443 | 1.34 | 100.0% |
| `09_high_volume_notification_write.sql` | Fast paginated retrieval of unread and recent notifications for a user. | **0.831** | **2.025** | 2.483 | 1.036 | 100.0% |
| `10_analytics_time_to_hire_kpi.sql` | Compute average cycle times and conversion drop-offs across hiring stages by industry. | **3.257** | **5.489** | 5.758 | 3.65 | 100.0% |
| `11_gig_revenue_and_rating_summary.sql` | Aggregate total platform earnings, completed projects, and average rating per currency and status. | **1.534** | **3.833** | 3.868 | 1.989 | 100.0% |
| `12_multilingual_ui_translation_lookup.sql` | Bulk fetch interface translations for a given language code with fallback to default English. | **1.16** | **2.362** | 2.896 | 1.356 | 100.0% |

## 2. Targeted Index Optimization Impact

| Query | Target Index Structure | With Index (ms) | Without Index / SeqScan (ms) | Speedup Factor |
| :--- | :--- | :---: | :---: | :---: |
| `01_candidate_multicriteria_search.sql` | Candidate Skill & Location Index | **29.21 ms** | 27.79 ms | **0.95x** |
| `03_recruiter_pipeline_funnel.sql` | Candidate Application Job Status Index | **1.21 ms** | 6.07 ms | **5.0x** |
| `07_non_overlapping_gig_worker_search.sql` | Gig Availability & Non-Overlap GiST Index | **10.73 ms** | 4.96 ms | **0.46x** |
