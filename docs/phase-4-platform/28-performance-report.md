# Talentra Performance Benchmark & Extrapolation Report

> **Superseded measurements (2026-10-27).** The latencies in this report come from the 2026-10-17 run (methodology v1), made when five of the twelve queries returned no rows and Query 10 measured the wrong interval. They are kept as history. The current measurements are in [`benchmarks/results/benchmark_summary_v2.md`](../../benchmarks/results/benchmark_summary_v2.md): all twelve queries return real results on 10,000 candidates / 1,000 jobs / 50,000 applications, and the artifact now records the engine version and dataset size it was measured on. The extrapolation model in sections 3 to 5 is superseded by the measured comparison at laptop scale and the projection built on it in [`benchmarks/results/scale_comparison.md`](../../benchmarks/results/scale_comparison.md).

**Database Engine**: PostgreSQL 17
**Benchmark Suite**: 12 Fixed Enterprise Queries (`db/queries/`)
**Measurement Run**: 2026-10-17T18:31:04Z, 10 timed iterations + 2 warmup runs, via `scripts/run_benchmarks.py`
**Environment**: Stock PostgreSQL 17 defaults in the `postgres:17` container (`docker-compose.yml` sets no `command:` override, mounts no config, and creates no init directory)
**Hardware Profile**: Dedicated 16 GB Host, NVMe SSD Storage
**Data Scales**:
* **Laptop / Medium Scale (Direct Measurement)**: 10,000 Candidates, 1,000 Jobs, 50,000 Applications, 2,000 Gig Workers — *the `medium` seed preset; the benchmark artifact does not itself record row counts*
* **Full-Scale Target (Extrapolation Projection)**: 10,000,000 Candidates, 1,000,000 Jobs, 100,000,000 Applications

> **How to read this report.** §1–§2 report **measured** results from a single historical run against a small seeded dataset on a **default-configuration** server. §3–§5 are a **mathematical model** and a set of **proposed** mitigations; they are not measurements, and the latency figures they derive are projections, not observations. The two are kept separate deliberately — the extrapolation in §3 assumes a production tuning profile (`shared_buffers = 4 GB`, `effective_cache_size = 12 GB`, `work_mem = 64 MB`) that this repository does not apply.

---

## 1. Executive Performance Summary & Baseline Latency Profile

The 12 fixed benchmark queries were profiled on PostgreSQL 17 across 10 timed iterations following a 2-run warmup phase. Latencies were measured with microsecond accuracy via `scripts/run_benchmarks.py`, capturing p50 (median), p95, p99, mean execution times, and PostgreSQL buffer cache hit ratios.

| Query ID | Workload Domain | Primary Operations & Purpose | p50 (ms) | p95 (ms) | p99 (ms) | Mean (ms) | Buffer Cache Hit Ratio | Result Validity |
| :---: | :--- | :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| **Q01** | `profile` / `master` | Multicriteria Candidate Search (Skills + Experience + City + Visibility) | **30.87** | 34.21 | 35.05 | 31.42 | **100.0%** | valid (non-empty) |
| **Q02** | `recruitment` / `master` | Candidate Job Feed Matching (Role + City + Arrangement + Salary Bounds) | **13.29** | 15.44 | 15.45 | 13.58 | **100.0%** | valid (non-empty) |
| **Q03** | `recruitment` | Recruiter Pipeline Funnel Aggregation (Application Stages & Pipeline Hours) | **1.01** | 1.95 | 2.33 | 1.15 | **100.0%** | **empty result** |
| **Q04** | `core` / `commercial` | Concurrent Session Device Limit Validation at Login | **1.17** | 2.15 | 2.59 | 1.34 | **100.0%** | **empty result** |
| **Q05** | `commercial` | Wallet Ledger Balance Reconciliation (Sum Credits - Sum Debits == Balance) | **0.98** | 2.03 | 2.45 | 1.12 | **100.0%** | **empty result** |
| **Q06** | `sourcing` / `core` | Sourcing Outreach Filter with Candidate-Blocked Recruiter Exclusion | **2.12** | 3.10 | 3.59 | 2.31 | **100.0%** | valid (non-empty) |
| **Q07** | `gig` / `master` | Non-Overlapping Gig Worker Matching (Availability + Calendar GiST Exclusion) | **11.07** | 12.02 | 12.14 | 11.23 | **100.0%** | valid (non-empty) |
| **Q08** | `commercial` / `profile` | Append-Only Candidate Profile Download Audit History Retrieval | **1.23** | 2.13 | 2.44 | 1.38 | **100.0%** | **empty result** |
| **Q09** | `messaging` | High-Volume Notification Delivery Retrieval (User In-App Inbox Feed) | **0.83** | 2.02 | 2.48 | 1.05 | **100.0%** | **empty result** |
| **Q10** | `analytics` | Analytics Funnel Conversion & Time-to-Hire KPI by Industry | **3.26** | 5.49 | 5.76 | 3.65 | **100.0%** | valid (non-empty) |
| **Q11** | `gig` / `analytics` | Gig Revenue, Fulfilled Volume, and Average Client Rating Summary | **1.53** | 3.83 | 3.87 | 1.84 | **100.0%** | valid (non-empty) |
| **Q12** | `messaging` / `master` | Multilingual UI Translation Resolution with Dynamic English Fallback | **1.16** | 2.36 | 2.90 | 1.32 | **100.0%** | valid (non-empty) |

### Key Baseline Takeaways
* **Sub-Millisecond Critical Paths (caveat required)**: Authentication checks (Q04: 1.17 ms), Financial reconciliations (Q05: 0.98 ms), and Notification reads (Q09: 0.83 ms) execute in under 1.5 ms — **but all three of these cases returned zero rows in this run**, so those figures measure the cost of an empty result set rather than the described workload. They are not evidence of sub-millisecond critical-path performance. The remaining seven workloads that did return rows (Q01 30.87 ms, Q02 13.29 ms, Q06 2.12 ms, Q07 11.07 ms, Q10 3.26 ms, Q11 1.53 ms, Q12 1.16 ms) are the usable baseline figures.
* **100% Buffer Hit Ratio**: Every query in this run reported a 100.0% buffer hit ratio (`shared_read_blocks = 0`), meaning the measured working set was served entirely from shared buffers with no disk reads. *This is a property of the small seeded dataset under a warm cache, not a statement about production-scale residency: the container runs stock PostgreSQL 17 defaults (no `postgresql.conf`, no init directory, no `command:` override in `docker-compose.yml`), and the benchmark artifact records no server configuration. The 4 GB `shared_buffers` figure below describes a **proposed** production profile, not the environment that produced these numbers.*

---

## 2. Diagnostic: Cost of Disabling Index Access Paths

**This section is a diagnostic comparison of two planner configurations, not a measurement of the benefit of adding an index.** Each critical query was executed twice: once with the default planner configuration, and once with `SET enable_indexscan = off; SET enable_bitmapscan = off; SET enable_indexonlyscan = off;`. The second configuration is a *deliberately crippled plan* in which the planner is forbidden from choosing any index access path. It is **not** equivalent to "the schema without the index", and it credits no index with a speedup.

| Query ID | Indexes Observed in the Baseline Plan | Default Plan (ms) | Index Access Paths Disabled (ms) | Disabled / Default Ratio |
| :---: | :--- | :---: | :---: | :---: |
| **Q03** | `idx_candidate_application_job_status` | **1.21 ms** | **6.07 ms** | **5.02** |
| **Q01** | *(none — baseline plan used sequential scans and hash joins)* | **29.21 ms** | **27.79 ms** | **0.95** |
| **Q07** | *(none — baseline plan used sequential scans)* | **10.73 ms** | **4.96 ms** | **0.46** |

A ratio above 1.0 means the crippled plan was slower than the default plan; a ratio below 1.0 means denying the planner its index access paths was *not* slower — in that case the baseline plan was not using an index in the first place, and the "disabled" leg was simply a different, cheaper plan over a small table.

### Diagnostic Insights
1. **Query 03 (Application Pipeline Funnel)**: The 5.02 ratio is the cost of *forbidding* `idx_candidate_application_job_status`, not the value of adding it. That index **already exists** in the schema (`db/migrations/009_create_candidate_application.sql`) and was **already in use** in the default plan, so this comparison cannot measure the benefit of creating it. A genuine before/after index measurement requires dropping the index and re-measuring, which is outside the scope of a read-only benchmark run and is deferred to a future index-review phase.
2. **Query 01 and Query 07**: Neither baseline plan used an index, so disabling index access paths could not make them meaningfully slower. These rows describe planner-method sensitivity, not index effectiveness.
3. **Exclusion Constraints on Gig Assignments**: The GiST index backing `ex_gig_assignment_no_overlap` is not merely an optimization; it is a hard business constraint preventing double-booking races at the transaction commit boundary. Constraint enforcement is a correctness property and is unaffected by the planner-method comparison above.

---

## 3. Mathematical Extrapolation Model (Scale: 10M Candidates / 100M Applications)

To project operational performance at full production scale (10,000,000 Candidate Profiles, 1,000,000 Job Requirements, and 100,000,000 Applications), we construct a mathematical model based on PostgreSQL 17 relational storage geometry, B-Tree index fanout, and hardware buffer cache sizing.

### 3.1 Storage Footprint Projections

#### 1. Row Size & Table Data Volume ($S_{\text{table}}$)
In PostgreSQL, each tuple has a 23-byte header plus null bitmap and column alignment padding.
* **Candidate Profile** (`profile.candidate_profile`): Average tuple size $\approx 220\text{ bytes}$.
  $$\text{Table Size}_{10\text{M Candidates}} = 10\text{M} \times 220\text{ B} \approx 2.2\text{ GB}$$
* **Candidate Skills** (`profile.candidate_skill`): Average 6 skills per candidate $\Rightarrow 60\text{M rows} \times 48\text{ B} \approx 2.88\text{ GB}$.
* **Candidate Applications** (`recruitment.candidate_application`): Average tuple size $\approx 110\text{ bytes}$.
  $$\text{Table Size}_{100\text{M Applications}} = 100\text{M} \times 110\text{ B} \approx 11.0\text{ GB}$$
* **Audit Events** (`audit.audit_event`): $250\text{M events} \times 180\text{ B} \approx 45.0\text{ GB}$.
* **Total Raw Table Data**: $\approx 61.08\text{ GB}$.

#### 2. Index Footprint ($S_{\text{index}}$)
A standard B-Tree index page is $8\text{ KB}$. With an index entry size of $\approx 16\text{ bytes}$ (key + tuple ID) and average page fill factor of $70\%$:
$$\text{Tuples per Index Page} = \frac{8192 \times 0.70}{16} \approx 358\text{ entries/page}$$
* For $100\text{M}$ applications, a single B-Tree index on `(job_posting_id, application_status)` requires:
  $$\text{Index Size} = \frac{100,000,000}{358} \times 8192\text{ B} \approx 2.28\text{ GB}$$
* With 3 indexes per major table, total index footprint at 100M scale $\approx 28.5\text{ GB}$.
* **Total Database Storage Footprint**: $\approx 89.58\text{ GB}$.

---

### 3.2 B-Tree Index Depth Growth ($O(\log N)$)

B-Tree index depth determines the number of page reads required to locate a leaf tuple pointer.
$$\text{Depth } D = \left\lceil \log_{B} \left(\frac{N}{F \cdot B}\right) \right\rceil + 1$$
Where:
* $N$ = Total rows
* $B$ = Fanout factor ($\approx 350$)
* $F$ = Leaf page fill factor ($0.70$)

| Entity Table | Row Count ($N$) | B-Tree Fanout ($B$) | Calculated Index Depth | Leaf Pages Read per Point Lookup |
| :--- | :---: | :---: | :---: | :---: |
| **Candidate Profile** (Dev Scale) | 500 | 350 | **2 Levels** | 1 root + 1 leaf = 2 reads |
| **Candidate Profile** (Target Scale) | 10,000,000 | 350 | **3 Levels** | 1 root + 1 branch + 1 leaf = 3 reads |
| **Candidate Applications** (Target Scale) | 100,000,000 | 350 | **4 Levels** | 1 root + 2 branch + 1 leaf = 4 reads |

Because B-Tree depth scales logarithmically ($O(\log N)$), expanding the dataset from 50,000 to 100,000,000 rows only adds **1 additional branch page traversal**!

---

### 3.3 Cache Hit Ratio Modeling & The "Cliff Effect"

The performance of an operational database is dictated by the **Buffer Cache Hit Ratio** ($R_{\text{hit}}$):
$$R_{\text{hit}} = \frac{\text{Shared Buffer Hits}}{\text{Shared Buffer Hits} + \text{Disk Reads}}$$

* **Memory Access Latency**: $\approx 0.05\text{ ms}$ (L3 cache / RAM access).
* **NVMe SSD Random Page Read**: $\approx 0.50\text{ ms} - 1.20\text{ ms}$.
* **Effective Query Latency**:
  $$T_{\text{query}} = (\text{Pages}) \times \left[ R_{\text{hit}} \cdot T_{\text{RAM}} + (1 - R_{\text{hit}}) \cdot T_{\text{Disk}} \right]$$

#### The 16 GB Laptop Threshold
*Modelled against a **proposed** development-host profile of `shared_buffers = 4 GB` and `effective_cache_size = 12 GB`. This profile is not applied by this repository — see the environment note in the header.*

* **Working Set $\le 12\text{ GB}$**: 100% of indexes and active table pages reside in memory. $R_{\text{hit}} \approx 99.9\%$. Queries execute in under 3 ms.
* **Working Set $> 16\text{ GB}$ (Target Scale $\approx 89.5\text{ GB}$)**: The working set exceeds host memory by $5.6\times$. $R_{\text{hit}}$ drops to $\approx 35\% - 55\%$. Disk I/O thrashing occurs.

---

## 4. Degradation Proof: Which Query Degrades First and Why?

### 4.1 The Degradation Winner: Query 01 (Candidate Multicriteria Sourcing Search)

**Query 01 will suffer the earliest and most severe performance degradation at scale.**

```sql
SELECT cp.id, cp.headline, cp.total_experience_years, cl.city_id, c.name,
       ARRAY_AGG(s.name ORDER BY cs.is_primary DESC) AS matching_skills
FROM profile.candidate_profile cp
JOIN profile.candidate_skill cs ON cp.id = cs.candidate_profile_id
JOIN master.skill s ON cs.skill_id = s.id
LEFT JOIN profile.candidate_location cl ON cp.id = cl.candidate_profile_id AND cl.location_type = 'current'
LEFT JOIN master.city c ON cl.city_id = c.id
WHERE cp.profile_status = 'active'
  AND cp.visibility IN ('recruiters', 'public')
  AND cp.total_experience_years >= 3.0
  AND s.normalized_name IN ('postgresql', 'python', 'docker')
GROUP BY cp.id, cp.headline, cp.total_experience_years, cl.city_id, c.name
HAVING COUNT(DISTINCT s.id) >= 1
ORDER BY cp.total_experience_years DESC, cp.id DESC
LIMIT 50;
```

### 4.2 Mathematical Root-Cause Analysis

1. **Cartesian Expansion Across Unaligned Junction Tables**:
   At 10M candidates with an average of 6 skills, `profile.candidate_skill` contains **60,000,000 rows**.
   Query 01 filters on three highly popular canonical skills (`'postgresql'`, `'python'`, `'docker'`). In a tech-oriented talent marketplace, these three skills appear on $\approx 35\%$ of all candidate profiles.
   $$\text{Candidate Matches} = 10,000,000 \times 0.35 \approx 3,500,000\text{ matching rows}$$

2. **The Hash Join & Sort Memory Blowout**:
   * Joining 3.5M candidate skills with 10M candidate profiles and candidate locations requires a Hash Aggregate or Sort Aggregate over $3.5\text{M}$ records.
   * Total working memory required for intermediate join tuples:
     $$M_{\text{sort}} = 3,500,000 \times 160\text{ bytes} \approx 560\text{ MB}$$
   * With `work_mem = 64 MB`, the PostgreSQL query planner is forced to spill intermediate hash buckets to **temporary disk files on disk (`external merge disk sort`)**.
   * Spilling 560 MB to disk causes $\sim 70,000$ sequential and random page writes and reads.

3. **Latency Explosion Projection**:
   * **Laptop Scale (10K candidates)**: Intermediate tuples $= 3,500 \times 160\text{ B} = 560\text{ KB} < \text{work\_mem}$. Executes purely in RAM in **30.87 ms**.
   * **Target Scale (10M candidates)**: Intermediate tuples $= 560\text{ MB} > \text{work\_mem}$. Disk sort overhead adds:
     $$T_{\text{disk sort}} \approx \frac{560\text{ MB}}{250\text{ MB/s (SSD Write/Read)}} \approx 2.24\text{ seconds}$$
     **Projected Q01 Latency at 10M Scale: 2,450 ms (an 80x degradation!)**

---

### 4.3 Why Query 03 (Application Funnel) Does NOT Degrade First

In contrast to Q01, Query 03 filters by a single job requirement (`WHERE ca.job_posting_id = 1`):
* Even when `recruitment.candidate_application` reaches 100,000,000 rows, a single job requirement has an average of 100 to 2,000 applicants.
* Thanks to the composite index `idx_candidate_application_job_status (job_posting_id, application_status)`, PostgreSQL executes an **Index Scan**:
  * Traverses 4 B-Tree index levels: 4 page reads.
  * Fetches 500 matching applicant tuples: $\approx 15$ heap page reads.
  * Total pages read: $19\text{ pages} \times 8\text{ KB} = 152\text{ KB}$.
* Since 152 KB easily fits in `work_mem` and `shared_buffers`, **Query 03 scales in $O(\log N)$ time, increasing from 1.01 ms to only $\approx 3.80\text{ ms}$ at 100M rows!**

---

## 5. Architectural Mitigation & Scaling Strategy

To prevent Query 01 degradation when scaling from laptop scale to full production scale, three mitigations are **proposed**. None of them is currently implemented, and none has been measured:

1. **Covering Indexes with INCLUDED Columns** (proposed):
   ```sql
   CREATE INDEX idx_candidate_skill_multisearch
   ON profile.candidate_skill (skill_id, candidate_profile_id)
   INCLUDE (proficiency_level, experience_years);
   ```
   Would enable Index-Only Scans, eliminating random heap page lookups for candidate skills. *This index does not exist in the schema today. The indexes actually present on `profile.candidate_skill` are `idx_candidate_skill_skill_id (skill_id)` and `idx_candidate_skill_profile_primary (candidate_profile_id, is_primary DESC)` (`db/migrations/005_create_candidate_profile.sql:77,80`) — neither is a covering index, and `profile.candidate_profile` carries no index on any of the three columns Query 01 filters on. The benefit of the proposed index is unmeasured.*

2. **Pre-aggregated Sourcing Search Marts** (proposed):
   For candidate discovery, denormalize skill arrays into `analytics.dim_candidate.primary_skill_name` — a column that exists in `analytics.dim_candidate` (`db/migrations/019_create_analytics_marts.sql:59`) — or utilize a materialized search view updated via background CDC (Change Data Capture). *The mart is not populated by any change-stream mechanism today; `analytics` fact tables are written only by the synthetic data loader (`scripts/generate_data.py`).*

3. **Declarative Range Partitioning** (implemented, but not yet on the critical path):
   By routing high-velocity candidate applications into **annual** partitions (`recruitment.candidate_application_partitioned`, partitioned by `RANGE (applied_at)` with one partition per calendar year), a query filtering on `applied_at` scans only the partitions matching the requested year range rather than the full table. Note that the authoritative application table today is the unpartitioned `recruitment.candidate_application`; the partitioned table is the prepared scale-out path and is not yet written to or read by application queries. This mitigation also does not apply to Query 01, which filters `profile.candidate_profile` rather than the application table.
