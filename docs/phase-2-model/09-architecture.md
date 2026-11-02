# Talentra Database Architecture Dossier
**System Engine**: PostgreSQL 17  
**Architecture Paradigm**: Database-First Modular Monolith  
**Schema Count**: 10 Isolated Domain Schemas  
**Table Count**: 95 Operational, Dimensional, and Partitioned Tables (92 standalone + 3 partition tables)  

---

## 1. Architectural Philosophy: The Modular Monolith

Talentra rejected the premature distributed microservices pattern in favor of a **Database-First Modular Monolith** implemented on PostgreSQL 17. 

```
                                +-----------------------------------+
                                |     Application / API Layer       |
                                +-----------------------------------+
                                                  |
                     =============================v=============================
                                     TALENTRA MODULAR MONOLITH
                     ===========================================================
                      [core]          [master]        [profile]    [recruitment]
                     Identity &      Canonical       Candidate      Full-Time
                       RBAC          Taxonomies       Profiles        Jobs
                     -----------------------------------------------------------
                      [gig]          [sourcing]      [commercial]   [messaging]
                    Marketplace      Consultants     Licences &     Localized UI
                    Assignments       Outreach        Ledgers       & Alerts
                     -----------------------------------------------------------
                      [audit]                         [analytics]
                     Append-Only                     Star Schema OLAP
                     Compliance                       Marts & MVs
                     ===========================================================
                                                  |
                                    PostgreSQL 17 Storage Engine
```

### 1.1 Why Modular Monolith Over Distributed Microservices?
1. **Atomic Cross-Domain Invariants**: When a recruiter hires a candidate, multiple operations must succeed atomically: transitioning the candidate application stage, debiting corporate credits from `commercial.wallet_ledger`, incrementing filled headcount on `recruitment.job_posting`, and logging compliance to `audit.audit_event`. In a microservice mesh, this requires error-prone Two-Phase Commit (2PC) or asynchronous Saga orchestrators that risk split-brain financial anomalies. In Talentra, a single ACID transaction guarantees atomic consistency across these writes. *(No benchmark measures this cross-domain transaction. Note also that `recruitment.job_posting` currently tracks `vacancy_count` only and has no filled-headcount counter.)*
2. **Unified Talent Graph**: The same individual professional can simultaneously be a full-time candidate (`profile.candidate_profile`), an active contractor (`gig.gig_worker_profile`), and an applicant across multiple enterprise pipelines. Schema-level isolation within a single relational engine permits zero-copy join queries while maintaining strict logical boundaries.
3. **Operational Simplicity & Cost**: Eliminates Kafka event bus latency, distributed tracing overhead, network serialization costs, and eventual consistency lag.

---

## 2. Domain Schema Breakdown

Talentra organizes its data assets into **10 domain schemas**, eliminating monolithic naming collisions and establishing explicit bounded contexts.

| Schema | Domain Scope | Key Operational Tables | Cross-Schema Boundaries |
| :--- | :--- | :--- | :--- |
| `core` | Identity, Security, Access Control | `user_account`, `role`, `permission`, `user_session`, `user_block`, `consent_record` | References no other schema; foundation for all user IDs. |
| `master` | Canonical Reference Taxonomies | `country`, `state`, `city`, `skill`, `language`, `qualification`, `job_role`, `employment_type`, `industry`, `work_type` | Zero outbound FKs; read-only reference data for all domains. |
| `profile` | Candidate CV & Career History | `candidate_profile`, `candidate_skill`, `candidate_location`, `candidate_work_experience`, `candidate_education` | FKs to `core.user_account` and `master.*`. |
| `recruitment` | Full-Time Jobs & Applications | `organization`, `organization_location`, `job_posting`, `candidate_application`, `candidate_application_partitioned` | FKs to `profile.candidate_profile`, `core.user_account`, `master.*`. |
| `gig` | Flexible Marketplace & Contracts | `gig_worker_profile`, `gig_worker_service`, `gig_worker_availability`, `gig_request`, `gig_application`, `gig_assignment` | Bridges `core.user_account` with `master.skill` and external fulfillment. |
| `sourcing` | Agency & Outreach Workflows | `job_consultant_policy`, `consultant_sourcing_request`, `sourcing_submission`, `outreach_batch`, `outreach_recipient` | Restricts consultant visibility; interacts with `recruitment` and `profile`. |
| `commercial` | Licences, Billing & Ledger | `subscription_licence`, `licence_seat_allocation`, `subscription_plan`, `subscription`, `wallet`, `wallet_ledger`, `invoice`, `payment_order`, `payment_refund`, `candidate_profile_download_history` | Governs seat allocations and tracks immutable financial movements. |
| `messaging` | Communications & Localization | `ui_translation`, `notification_template`, `user_notification_preference`, `job_alert_preference`, `notification_delivery` | High-frequency write log; multilingual UI fallback engine. |
| `audit` | Compliance & System Logs | `audit_event`, `system_error_log` | Strictly append-only compliance logs with anti-tamper triggers. |
| `analytics` | Business Intelligence & Reporting | `dim_date`, `dim_candidate`, `dim_organization`, `dim_job_posting`, `fact_application_event`, `mv_hiring_funnel_summary` | OLAP Star Schema fed by transactional change streams. |

---

## 3. Subsystem Deep Dives

### 3.1 The Gig Marketplace Integration
A central architectural decision in Talentra is the **first-class integration of the Gig Marketplace** (`gig` schema) directly alongside full-time hiring (`recruitment` schema):
* **Why not a separate database or application?** Corporate enterprises increasingly deploy hybrid workforce strategies. A hiring manager evaluating a Java backend position may choose between an immediate 3-month contractor or a permanent hire. Having gig profiles and full-time profiles in the same engine allows unified skill search queries (`master.skill`) and seamless cross-hiring without data sync latency.
* **Temporal Overlap Prevention**: The gig marketplace enforces calendar availability through PostgreSQL's native `btree_gist` exclusion constraint:
  ```sql
  CONSTRAINT ex_gig_assignment_no_overlap
  EXCLUDE USING gist (
      gig_worker_profile_id WITH =,
      daterange(assigned_start_date, assigned_end_date, '[]') WITH &&
  )
  WHERE (assignment_status = 'active');
  ```
  This guarantees that no worker can be booked on overlapping active assignments, eliminating double-booking races at the database hardware layer.

### 3.2 Licensing, Seat Allocations & Concurrent Session Locking
Enterprise clients purchase multi-seat subscription licences (`commercial.subscription_licence`) with strict device entitlements (e.g., maximum 3 concurrent devices per recruiter).
* **The Locking Mechanism**: Session creation is executed via `core.create_session_with_device_limit(...)`.
* **Pessimistic Concurrency**: During login, the function acquires a row-level lock (`SELECT ... FOR UPDATE`) on the `core.user_account` row of the user being logged in, serializing concurrent login attempts. The licence seat allocation is read to derive the device entitlement, but it is not the locked resource.
* **Atomic Session Verification**: It computes:
  $$\text{Active Sessions} = \text{Count}(\text{user\_session where ended\_at IS NULL and revoked\_at IS NULL})$$
* **Limit Enforcement & Non-Blocking Audit**: If active sessions exceed `max_devices_per_user`, session creation is rejected, and an auditable event is recorded directly in `audit.audit_event` before returning `NULL`, ensuring security monitoring cannot be circumvented.

### 3.3 High-Velocity Declarative Range Partitioning
The application pipeline experiences massive write velocity ($>50\text{M}$ rows at scale).
* **Partition Key**: `recruitment.candidate_application_partitioned` is partitioned by `RANGE (applied_at)` into **annual** partitions — one per calendar year (`candidate_application_y2025`, `candidate_application_y2026`, `candidate_application_y2027`).
* **Constraint Compliance**: The primary key compound constraint `(id, applied_at)` satisfies PostgreSQL partition routing requirements.
* **Partition Pruning**: Queries filtering on `applied_at` prune partitions outside the requested range. *No benchmark query in `db/queries/` currently targets the partitioned table, so this behaviour is not exercised by the measured suite and no pruning percentage is claimed.*
* **Rolling Retention Lifecycle (future)**: Older partitions can be detached (`ALTER TABLE ... DETACH PARTITION`) and archived to cold columnar storage. *No archival pipeline is implemented in this repository.*

### 3.4 Append-Only Financial Ledgers
In accordance with Rule Group 7 and Rule Group 10:
* `commercial.wallet_ledger` is strictly append-only.
* Direct `UPDATE` and `DELETE` operations are intercepted and terminated by `commercial.prevent_ledger_tampering()` trigger:
  ```sql
  CREATE TRIGGER trg_prevent_wallet_ledger_tampering
  BEFORE UPDATE OR DELETE ON commercial.wallet_ledger
  FOR EACH ROW EXECUTE FUNCTION commercial.prevent_ledger_tampering();
  ```
* **Correction Accounting**: Balance errors cannot overwrite historical entries. A correction is applied by inserting a new entry of type `'correction_credit'` or `'correction_debit'` that explicitly references the flawed entry via `correction_of_ledger_id`.
* **Reconciliation Invariant**:
  $$\text{Wallet Balance} \equiv \sum \text{Credits} - \sum \text{Debits}$$
  *The wallet balance (`commercial.wallet.balance`) is a stored column. The schema records ledger entries immutably but does not itself derive or enforce the balance, so reconciliation is **checked** by `scripts/validate_data.py` and benchmark Query 05 rather than guaranteed by a constraint.*

### 3.5 Analytical Star Schema & SCD Type-2
Transactional schemas optimize for low-latency writes ($O(1)$ PK lookups). Reporting queries demand high-throughput analytical scans.
* **Separation of Concerns**: Analytical queries never scan operational `recruitment.candidate_application` or `profile.candidate_profile`.
* **Slowly Changing Dimensions (SCD Type-2)**: `analytics.dim_candidate` and `analytics.dim_organization` preserve point-in-time accuracy using `valid_from`, `valid_to`, and `is_current` columns.
* **Pre-aggregated Materialized Views**: High-overhead funnel conversions are pre-aggregated into `analytics.mv_hiring_funnel_summary` and `analytics.mv_gig_fulfilment_summary`, refreshed by the `analytics.refresh_reporting_marts()` procedure (`REFRESH MATERIALIZED VIEW CONCURRENTLY`). *No scheduler invokes it automatically, and the analytics fact tables are populated only by the synthetic data loader (`scripts/generate_data.py`); `analytics.fact_gig_performance` and `analytics.fact_wallet_transaction` have no populating code at all.*

---

## 4. PostgreSQL 17 Engine Configuration

For production deployment supporting 1M+ candidate profiles and 5M+ applications, the following PostgreSQL 17 engine parameters are **proposed**:

> *These settings are **not applied** by this repository. There is no `postgresql.conf`, no init directory, and no `command:` override in `docker-compose.yml`, so the running container uses stock PostgreSQL 17 defaults. The benchmark artifact in `benchmarks/results/` was produced against stock defaults.*

```ini
# Memory Configuration (16 GB Dedicated Host)
shared_buffers = 4GB                  # 25% of total RAM
effective_cache_size = 12GB           # 75% of total RAM
work_mem = 64MB                       # Per-operation sort/hash memory
maintenance_work_mem = 1GB            # Vacuum and index build buffer

# Checkpoint & WAL Configuration
wal_buffers = 16MB
checkpoint_completion_target = 0.9
max_wal_size = 16GB
min_wal_size = 2GB

# Concurrency & Optimizer
max_connections = 200
random_page_cost = 1.1                # Calibrated for NVMe SSD storage
effective_io_concurrency = 200        # Concurrent asynchronous SSD I/O
default_statistics_target = 100       # Accurate histogram sampling for query planner
```

---

## 5. Architectural Invariant Summary

1. **Surrogate Key Uniformity**: All *operational* tables use `BIGINT GENERATED ALWAYS AS IDENTITY` primary keys named `id`; the four `analytics.dim_*` dimensions use surrogate `*_key` keys, and `recruitment.candidate_application_partitioned` uses the compound `(id, applied_at)` primary key PostgreSQL requires for partition routing.
2. **Domain Isolation**: Cross-schema foreign keys are used deliberately for referential integrity (e.g. `recruitment.candidate_application` → `profile.candidate_profile`); schemas are logically separated by ownership, not by physical FK isolation.
3. **UTC Strictness**: No column uses a timezone-naive `TIMESTAMP`; all instant-valued timestamps are `TIMESTAMPTZ` normalized to UTC. Calendar-date fields (employment and assignment windows, `analytics.dim_date.calendar_date`) are `DATE` by design.
4. **Anti-Sentinel Discipline**: Missing data is represented strictly as SQL `NULL`. No dummy strings (`'NA'`, `'NONE'`, `'UNKNOWN'`) or sentinel numbers (`-1`, `0`, `9999`) exist in any schema.
