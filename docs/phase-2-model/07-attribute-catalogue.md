# Talentra: Attribute Catalogue and Data Dictionary (Steps 07, 10, 19)

**Phase:** 2 Model | **Steps:** 07 Attributes Discovery, 10 Data Dictionary v1, 19 Data Dictionary v2
**Generated** by `scripts/lifecycle/gen_model_catalogues.py`. Do not hand-edit.

Everything here is read from the database, so this dictionary cannot drift from the schema: structure from the catalog, class and protection from `audit.column_classification` (Rule Group 6), definitions from `COMMENT ON` statements. A column with no comment has no written business definition yet; that is a documentation gap, shown below, not hidden.

**Totals:** 1304 columns across 113 base tables.

| Measure | Count |
|:--|--:|
| Columns with a written definition (`COMMENT ON`) | 1304 of 1304 |
| Nullable columns | 449 |
| Nullable columns with a written justification (RG5) | 449 of 449 |
| Classified `internal` | 1085 |
| Classified `personal` | 97 |
| Classified `public` | 114 |
| Classified `sensitive` | 8 |

Rule Group 5 asks for a written justification of every nullable column. Every column has a definition and every nullable column says what NULL means (migration 033; `tests/test_column_definitions.sql` fails otherwise).

## `analytics.dim_candidate`

Candidate dimension with Type-2 slowly changing tracking of career experience and locations

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `candidate_key` | bigint | no | - | PK | internal | grants_only | Surrogate key of this version of the candidate (Type 2): a candidate whose city or experience changes gets a new key. |
| 2 | `candidate_profile_id` | bigint | no | - | - | internal | grants_only | Id of the candidate in profile.candidate_profile, shared by every version of the candidate. |
| 3 | `current_city_name` | character varying(100) | yes | - | - | internal | grants_only | City of the candidate's current location in this version. NULL when no current location is recorded. |
| 4 | `total_experience_years` | numeric(4,1) | yes | - | - | internal | grants_only | Total years of work experience in this version of the candidate. NULL when the candidate recorded none. |
| 5 | `profile_completeness_percentage` | numeric(5,2) | yes | - | - | internal | grants_only | Profile completeness, 0 to 100, in this version. NULL when it has not been computed. |
| 6 | `primary_skill_name` | character varying(120) | yes | - | - | internal | grants_only | Name of the candidate's primary skill in this version. NULL when the candidate has listed no skill. |
| 7 | `valid_from` | timestamp with time zone | no | - | - | internal | grants_only | Start of the period in which this version was current. |
| 8 | `valid_to` | timestamp with time zone | yes | - | - | internal | grants_only | End of the period in which this version was current. NULL for the current version. |
| 9 | `is_current` | boolean | no | true | - | internal | grants_only | True when current. Default true. |

## `analytics.dim_date`

Pre-populated calendar date dimension for analytical slice-and-dice

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `date_key` | integer | no | - | PK | internal | grants_only | Calendar day as the integer YYYYMMDD (for example 20261028); the key facts join to. |
| 2 | `calendar_date` | date | no | - | UQ | internal | grants_only | Calendar date of calendar. |
| 3 | `day_of_month` | integer | no | - | - | internal | grants_only | Day of the month, 1 to 31. |
| 4 | `day_name` | character varying(10) | no | - | - | internal | grants_only | English name of the weekday, padded by the database to nine characters. |
| 5 | `day_of_week` | integer | no | - | - | internal | grants_only | ISO weekday, 1 (Monday) to 7 (Sunday). |
| 6 | `month_number` | integer | no | - | - | internal | grants_only | Month of the year, 1 to 12. |
| 7 | `month_name` | character varying(15) | no | - | - | internal | grants_only | English name of the month, padded by the database. |
| 8 | `quarter_number` | integer | no | - | - | internal | grants_only | Calendar quarter, 1 to 4. |
| 9 | `year_number` | integer | no | - | - | internal | grants_only | Calendar year. |
| 10 | `is_weekend` | boolean | no | - | - | internal | grants_only | True when weekend. Default None. |

## `analytics.dim_job_posting`

Analytical job posting dimension incorporating role, arrangement, and salary tiers

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `job_posting_key` | bigint | no | - | PK | internal | grants_only | Surrogate key of the job in the star schema. |
| 2 | `job_posting_id` | bigint | no | - | UQ | internal | grants_only | Id of the job in recruitment.job_posting. |
| 3 | `organization_key` | bigint | no | - | FK to analytics.dim_organization | internal | grants_only | Reference to analytics.dim_organization (organization key). Required. |
| 4 | `job_title` | character varying(200) | no | - | - | internal | grants_only | Title of the job as last loaded (Type 1: the latest value wins). |
| 5 | `job_role_name` | character varying(120) | yes | - | - | internal | grants_only | Name of the job's role. NULL when the job has no role. |
| 6 | `industry_name` | character varying(120) | yes | - | - | internal | grants_only | Name of the job's industry. NULL when the job has none. |
| 7 | `employment_type_code` | character varying(30) | yes | - | - | internal | grants_only | Employment type code (for example full_time). NULL when the job has none. |
| 8 | `work_type_code` | character varying(30) | yes | - | - | internal | grants_only | Work arrangement code (on_site, remote, hybrid). NULL when the job has none. |
| 9 | `currency_code` | character(3) | yes | - | - | internal | grants_only | ISO 4217 currency of salary_min and salary_max. NULL when the job discloses no salary. |
| 10 | `salary_min` | numeric(14,2) | yes | - | - | internal | grants_only | Lowest salary offered, in currency_code. NULL when the job discloses no salary. |
| 11 | `salary_max` | numeric(14,2) | yes | - | - | internal | grants_only | Highest salary offered, in currency_code. NULL when the job discloses no salary. |
| 12 | `published_date_key` | integer | yes | - | FK to analytics.dim_date | internal | grants_only | Reference to analytics.dim_date (published date key). NULL when there is none. |

## `analytics.dim_organization`

Organization dimension tracking corporate profile shifts over time

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `organization_key` | bigint | no | - | PK | internal | grants_only | Surrogate key of this version of the organisation (Type 2). |
| 2 | `organization_id` | bigint | no | - | - | internal | grants_only | Id of the organisation in recruitment.organization, shared by every version. |
| 3 | `organization_name` | character varying(200) | no | - | - | internal | grants_only | Name in this version. |
| 4 | `organization_type` | character varying(30) | no | - | - | internal | grants_only | Type in this version (for example employer, agency). |
| 5 | `country_code` | character varying(3) | yes | - | - | internal | grants_only | ISO 3166 alpha-3 code of the organisation's country. NULL when no country is recorded. |
| 6 | `industry_name` | character varying(120) | yes | - | - | internal | grants_only | The industry in which the organisation posts most jobs. NULL when it has posted none with an industry. |
| 7 | `valid_from` | timestamp with time zone | no | - | - | internal | grants_only | Start of the period in which this version was current. |
| 8 | `valid_to` | timestamp with time zone | yes | - | - | internal | grants_only | End of the period in which this version was current. NULL for the current version. |
| 9 | `is_current` | boolean | no | true | - | internal | grants_only | True when current. Default true. |

## `analytics.fact_application_event`

Fact table tracking hiring pipeline state changes and stage cycle times

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `candidate_application_id` | bigint | no | - | - | internal | grants_only | Application the event belongs to (recruitment.candidate_application). |
| 3 | `date_key` | integer | no | - | FK to analytics.dim_date | internal | grants_only | Reference to analytics.dim_date (date key). Required. |
| 4 | `job_posting_key` | bigint | no | - | FK to analytics.dim_job_posting | internal | grants_only | Reference to analytics.dim_job_posting (job posting key). Required. |
| 5 | `candidate_key` | bigint | no | - | FK to analytics.dim_candidate | internal | grants_only | Reference to analytics.dim_candidate (candidate key). Required. |
| 6 | `organization_key` | bigint | no | - | FK to analytics.dim_organization | internal | grants_only | Reference to analytics.dim_organization (organization key). Required. |
| 7 | `previous_status` | character varying(20) | yes | - | - | internal | grants_only | Status the application left. NULL for the first event, when it was created. |
| 8 | `new_status` | character varying(20) | no | - | - | internal | grants_only | Status the application entered. |
| 9 | `status_cycle_time_hours` | numeric(10,2) | yes | - | - | internal | grants_only | Hours the application spent in previous_status. NULL for the first event, which has no previous status. |
| 10 | `is_terminal_state` | boolean | no | false | - | internal | grants_only | True when terminal state. Default false. |
| 11 | `event_timestamp` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the status change happened (UTC). |
| 12 | `source_history_id` | bigint | yes | - | UQ | internal | grants_only | recruitment.application_status_history.id this event was loaded from. NULL only for rows loaded before migration 023. |

## `analytics.fact_gig_performance`

Fact table tracking completed gig assignments, earnings reconciliation, and satisfaction

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `gig_assignment_id` | bigint | no | - | UQ | internal | grants_only | Finished assignment this row summarises (gig.gig_assignment). |
| 3 | `organization_key` | bigint | no | - | FK to analytics.dim_organization | internal | grants_only | Reference to analytics.dim_organization (organization key). Required. |
| 4 | `completion_date_key` | integer | yes | - | FK to analytics.dim_date | internal | grants_only | Reference to analytics.dim_date (completion date key). NULL when there is none. |
| 5 | `agreed_amount` | numeric(14,2) | no | - | - | internal | grants_only | Price agreed for the assignment, in currency_code. |
| 6 | `actual_reconciled_earnings` | numeric(14,2) | no | - | - | internal | grants_only | Earnings the fulfilment system reported, in currency_code. 0 when none have been reconciled. |
| 7 | `currency_code` | character(3) | no | - | - | internal | grants_only | ISO 4217 currency of the amount(s) in this row, three capital letters. |
| 8 | `duration_days` | integer | no | - | - | internal | grants_only | Number of days. |
| 9 | `client_rating` | numeric(3,2) | yes | - | - | internal | grants_only | Requester's overall rating, 1 to 5. NULL when the assignment was not rated. |
| 10 | `assignment_status` | character varying(20) | no | - | - | internal | grants_only | Final status of the assignment: completed or terminated. |

## `analytics.fact_wallet_transaction`

Fact table analyzing credit spend velocity, recharge rates, and monetized features

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `wallet_id` | bigint | no | - | - | internal | grants_only | Wallet the entry belongs to (commercial.wallet). |
| 3 | `organization_key` | bigint | no | - | FK to analytics.dim_organization | internal | grants_only | Reference to analytics.dim_organization (organization key). Required. |
| 4 | `date_key` | integer | no | - | FK to analytics.dim_date | internal | grants_only | Reference to analytics.dim_date (date key). Required. |
| 5 | `entry_type` | character varying(20) | no | - | - | internal | grants_only | credit, debit, correction_credit or correction_debit. |
| 6 | `amount` | numeric(14,2) | no | - | - | internal | grants_only | Amount of the entry, always positive, in currency_code; entry_type gives the direction. |
| 7 | `currency_code` | character(3) | no | - | - | internal | grants_only | ISO 4217 currency of the amount(s) in this row, three capital letters. |
| 8 | `reference_type` | character varying(40) | no | - | - | internal | grants_only | What the entry paid for or came from (recharge, profile_download, ...). |
| 9 | `recorded_timestamp` | timestamp with time zone | no | - | - | internal | grants_only | When the entry was written to the ledger (UTC). |
| 10 | `source_wallet_ledger_id` | bigint | yes | - | UQ | internal | grants_only | commercial.wallet_ledger.id this row was loaded from. NULL only for rows loaded before migration 023. |

## `audit.action_catalogue`

Every action code that may appear in audit.audit_event, with the sensitive-action class (1-14) it evidences. Domain-ledger rows name the append-only table that already records the action.

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `code` | character varying(80) | no | - | UQ | internal | grants_only | Stable machine-readable code (lower case), unique within the table. |
| 3 | `sensitive_class` | integer | no | - | - | internal | grants_only | Which of the 14 sensitive action classes this action evidences (docs/phase-1-discover/05-audit-event-matrix.md). |
| 4 | `trail` | character varying(14) | no | 'audit_event'::character varying | - | internal | grants_only | One of: audit_event, domain_ledger. |
| 5 | `trail_table` | character varying(100) | yes | - | - | internal | grants_only | Nullable: set only when trail = domain_ledger, naming the append-only table that is the trail. |
| 6 | `description` | character varying(300) | no | - | - | internal | grants_only | What the action means, in one line. |
| 7 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 8 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 9 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Account that created the row, taken from the session. NULL when the system created it (seed, migration, scheduled job). |
| 10 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Account that last changed the row, taken from the session. NULL when the system changed it. |

## `audit.audit_event`

Append-only trail of sensitive actions. Actions come from audit.action_catalogue (14 classes). Written by audit.log_change() triggers and by the login, revocation, erasure and impersonation functions. Never UPDATE or DELETE; TRUNCATE is blocked.

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `actor_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Reference to core.user_account (actor user account). NULL when there is none. |
| 3 | `impersonator_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Reference to core.user_account (impersonator user account). NULL when there is none. |
| 4 | `action` | character varying(80) | no | - | FK to audit.action_catalogue | internal | grants_only | Reference to audit.action_catalogue (action). Required. |
| 5 | `entity_schema` | character varying(50) | no | - | - | internal | grants_only | Schema of the table the action concerned. |
| 6 | `entity_name` | character varying(80) | no | - | - | internal | grants_only | Table the action concerned. |
| 7 | `entity_id` | bigint | yes | - | - | internal | grants_only | Primary key of the row the action concerned. NULL for actions with no row, such as a failed login. |
| 8 | `old_values_json` | jsonb | yes | - | - | internal | grants_only | Row as it was before the change, secrets removed. NULL for events that create or only observe (a login, an insert). |
| 9 | `new_values_json` | jsonb | yes | - | - | internal | grants_only | Row as it is after the change, secrets removed. NULL for events that delete or only observe. |
| 10 | `client_ip` | character varying(45) | yes | - | - | personal | grants_only | Address the request came from. NULL for actions not made through a request. Personal data. |
| 11 | `user_agent` | character varying(500) | yes | - | - | personal | grants_only | Client software string. NULL when not available. Personal data. |
| 12 | `recorded_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | Instant (UTC) at which this row's recorded happened. |
| 13 | `organization_id` | bigint | yes | - | FK to recruitment.organization | internal | grants_only | Nullable: the organisation the event belongs to, when it belongs to one. Platform-level events (a login, a role change) have none. |

## `audit.column_classification`

Docket Rule Group 6: class and protection of every column. Completeness is asserted by tests/test_classification.sql.

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `schema_name` | character varying(63) | no | - | - | internal | grants_only | Schema of the classified column. |
| 3 | `table_name` | character varying(63) | no | - | - | internal | grants_only | Table of the classified column. |
| 4 | `column_name` | character varying(63) | no | - | - | internal | grants_only | The classified column. |
| 5 | `data_class` | character varying(10) | no | - | - | internal | grants_only | One of: public, internal, personal, sensitive. |
| 6 | `protection` | character varying(20) | no | - | - | internal | grants_only | One of: none, grants_only, rls, masked_view, hashed, external_reference, open_risk. |
| 7 | `basis` | character varying(10) | no | 'pattern'::character varying | - | internal | grants_only | One of: pattern, reviewed. |
| 8 | `note` | character varying(300) | yes | - | - | internal | grants_only | Nullable: only rows that need an explanation carry one. |
| 9 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 10 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 11 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 12 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `audit.entity_lifecycle_policy`

One row per base table: soft/hard/append-only/reference/derived, plus retention. Completeness is asserted by tests/test_lifecycle.sql.

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `schema_name` | character varying(63) | no | - | - | internal | grants_only | Schema of the table this policy describes. |
| 3 | `table_name` | character varying(63) | no | - | - | internal | grants_only | Table this policy describes. |
| 4 | `delete_mode` | character varying(12) | no | - | - | internal | grants_only | One of: soft, hard, append_only, reference, derived. |
| 5 | `retention_days` | integer | yes | - | - | internal | grants_only | NULL = no retention limit defined. Counted from last activity for personal data, from creation for records. |
| 6 | `retention_basis` | character varying(200) | yes | - | - | internal | grants_only | Why the retention period is what it is. NULL when no retention limit is set. |
| 7 | `is_retention_approved` | boolean | no | false | - | internal | grants_only | TRUE once approved. The periods were approved by delegated decision (DEC-23); core.user_account stays FALSE on purpose, so dormant accounts  |
| 8 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 9 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 10 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 11 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 12 | `purge_column` | character varying(63) | yes | - | - | internal | grants_only | Nullable: the timestamp column the retention period is counted from. NULL means rows of this table are not purged by the scheduled job (fina |
| 13 | `retention_approved_by` | character varying(200) | yes | - | - | internal | grants_only | Nullable: who approved the retention period, with the decision reference. NULL while unapproved. |

## `audit.maintenance_run`

One row per scheduled job execution, written when it finishes. Append-only: the data behind "when did the marts last refresh" and "when was the last backup verified".

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `job_name` | character varying(60) | no | - | - | internal | grants_only | Which scheduled job ran: refresh_marts, purge_expired_data, erase_inactive_accounts or backup_restore_check. |
| 3 | `run_status` | character varying(10) | no | - | - | internal | grants_only | One of: succeeded, failed, skipped. |
| 4 | `started_at` | timestamp with time zone | no | - | - | internal | grants_only | Instant (UTC) at which this row's started happened. |
| 5 | `finished_at` | timestamp with time zone | no | clock_timestamp() | - | internal | grants_only | Instant (UTC) at which this row's finished happened. |
| 6 | `rows_affected` | bigint | yes | - | - | internal | grants_only | Nullable: jobs that do not touch rows (a mart refresh, a backup check) report none. |
| 7 | `detail_json` | jsonb | yes | - | - | internal | grants_only | Nullable: per-table counts for a purge, the reason for a skip. |
| 8 | `error_message` | character varying(500) | yes | - | - | internal | grants_only | Nullable: set only when run_status is failed. |

## `audit.system_error_log`

System and operational error occurrences for monitoring and diagnostics

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `error_code` | character varying(50) | no | - | - | internal | grants_only | Short stable code for the kind of error, for example INTEGRATION_DEAD_LETTER. |
| 3 | `error_severity` | character varying(20) | no | 'error'::character varying | - | internal | grants_only | One of: debug, info, warning, error, critical, fatal. |
| 4 | `error_message` | text | no | - | - | internal | grants_only | What went wrong, in words. |
| 5 | `stack_trace` | text | yes | - | - | internal | grants_only | Stack trace when the error came from application code. NULL for errors raised inside the database. |
| 6 | `context_json` | jsonb | yes | - | - | personal | grants_only | Structured detail of the error (ids, parameters), no personal data. NULL when the message says everything. |
| 7 | `user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Reference to core.user_account (user account). NULL when there is none. |
| 8 | `recorded_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | Instant (UTC) at which this row's recorded happened. |

## `commercial.candidate_profile_download_history`

Append-only record of recruiters downloading candidate profiles with associated credit deductions

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | rls | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `organization_id` | bigint | no | - | FK to recruitment.organization | internal | rls | Reference to recruitment.organization (organization). Required. |
| 3 | `downloader_user_account_id` | bigint | no | - | FK to core.user_account | internal | rls | Reference to core.user_account (downloader user account). Required. |
| 4 | `candidate_profile_id` | bigint | no | - | FK to profile.candidate_profile | internal | rls | Reference to profile.candidate_profile (candidate profile). Required. |
| 5 | `credit_deduction_amount` | numeric(14,2) | no | 0.00 | - | internal | rls | Credit charged for this download, in currency_code. 0 when the download was free (for example within a plan quota). |
| 6 | `currency_code` | character(3) | no | 'USD'::bpchar | - | internal | rls | ISO 4217 currency of the amount(s) in this row, three capital letters. |
| 7 | `wallet_ledger_id` | bigint | yes | - | FK to commercial.wallet_ledger | internal | rls | Reference to commercial.wallet_ledger (wallet ledger). NULL when there is none. |
| 8 | `downloaded_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | Instant (UTC) at which this row's downloaded happened. |

## `commercial.credit_price`

What one unit of a chargeable action costs in each currency. Seed amounts are placeholders (DEC-29) for the commercial owner to replace.

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `reference_type` | character varying(40) | no | - | - | internal | grants_only | The chargeable action; one of the wallet ledger reference types that spend credit. |
| 3 | `currency_code` | character(3) | no | - | - | internal | grants_only | ISO 4217 currency of amount, three capital letters; the wallet charged must be in this currency. |
| 4 | `amount` | numeric(14,2) | no | - | - | internal | grants_only | Credit charged per action, in currency_code, greater than zero. |
| 5 | `is_active` | boolean | no | true | - | internal | grants_only | False withdraws the price; the action then cannot be charged in that currency. |
| 6 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 7 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 8 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Account that created the row, taken from the session. NULL when the system created it (seed, migration, scheduled job). |
| 9 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Account that last changed the row, taken from the session. NULL when the system changed it. |

## `commercial.invoice`

Billing invoices with verifiable subtotal and tax amounts

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | rls | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `organization_id` | bigint | no | - | FK to recruitment.organization | internal | rls | Reference to recruitment.organization (organization). Required. |
| 3 | `payment_order_id` | bigint | yes | - | FK to commercial.payment_order | internal | rls | Reference to commercial.payment_order (payment order). NULL when there is none. |
| 4 | `invoice_number` | character varying(60) | no | - | UQ | internal | rls | Human-readable invoice number, unique, issued in sequence per organisation. |
| 5 | `subtotal_amount` | numeric(14,2) | no | - | - | internal | rls | Amount before tax, in currency_code. |
| 6 | `tax_amount` | numeric(14,2) | no | 0.00 | - | internal | rls | Tax charged, in currency_code. 0 when the sale is untaxed. |
| 7 | `total_amount` | numeric(14,2) | no | - | - | internal | rls | Subtotal plus tax, in currency_code. A CHECK enforces the sum. |
| 8 | `currency_code` | character(3) | no | 'USD'::bpchar | - | internal | rls | ISO 4217 currency of the amount(s) in this row, three capital letters. |
| 9 | `invoice_status` | character varying(20) | no | 'issued'::character varying | - | internal | rls | One of: draft, issued, paid, void, uncollectible. |
| 10 | `issued_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | Instant (UTC) at which this row's issued happened. |
| 11 | `paid_at` | timestamp with time zone | yes | - | - | internal | rls | Nullable: NULL until the event this timestamp records has happened. |
| 12 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was created (UTC). Set by trigger and never changed. |
| 13 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was last changed (UTC). Set by trigger. |
| 14 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 15 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `commercial.licence_seat_allocation`

Active seat assignments mapping users to corporate subscription licences

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | rls | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `subscription_licence_id` | bigint | no | - | FK to commercial.subscription_licence | internal | rls | Reference to commercial.subscription_licence (subscription licence). Required. |
| 3 | `user_account_id` | bigint | no | - | FK to core.user_account | internal | rls | Reference to core.user_account (user account). Required. |
| 4 | `allocated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: NULL until the action named by the column has been taken, or when a system job took it. |
| 5 | `allocated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | Instant (UTC) at which this row's allocated happened. |
| 6 | `revoked_at` | timestamp with time zone | yes | - | - | internal | rls | Nullable: NULL until the event this timestamp records has happened. |
| 7 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was created (UTC). Set by trigger and never changed. |
| 8 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was last changed (UTC). Set by trigger. |
| 9 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 10 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `commercial.payment_order`

Payment gateway transactions and references; never stores card or bank numbers

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | rls | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `organization_id` | bigint | no | - | FK to recruitment.organization | internal | rls | Reference to recruitment.organization (organization). Required. |
| 3 | `user_account_id` | bigint | no | - | FK to core.user_account | internal | rls | Reference to core.user_account (user account). Required. |
| 4 | `gateway_provider` | character varying(50) | no | 'stripe'::character varying | - | internal | rls | Payment gateway that handled the order (for example razorpay, stripe). |
| 5 | `gateway_order_id` | character varying(255) | no | - | UQ | sensitive | external_reference | The gateway's reference for the order. A reference only: no card or bank data is stored. Sensitive. |
| 6 | `order_amount` | numeric(14,2) | no | - | - | internal | rls | Amount to be charged, in currency_code. |
| 7 | `currency_code` | character(3) | no | 'USD'::bpchar | - | internal | rls | ISO 4217 currency of the amount(s) in this row, three capital letters. |
| 8 | `order_status` | character varying(20) | no | 'created'::character varying | - | internal | rls | One of: created, authorized, captured, failed, cancelled, refunded. |
| 9 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was created (UTC). Set by trigger and never changed. |
| 10 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was last changed (UTC). Set by trigger. |
| 11 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 12 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 13 | `idempotency_key` | character varying(100) | yes | - | - | internal | rls | Nullable: a key the caller supplies so that retrying the same request cannot create a second order. Unique per organisation when present. |

## `commercial.payment_refund`

Partial or full refunds referencing original payment orders

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | rls | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `payment_order_id` | bigint | no | - | FK to commercial.payment_order | internal | rls | Reference to commercial.payment_order (payment order). Required. |
| 3 | `refund_amount` | numeric(14,2) | no | - | - | internal | rls | Amount returned to the payer, in currency_code. |
| 4 | `currency_code` | character(3) | no | 'USD'::bpchar | - | internal | rls | ISO 4217 currency of the amount(s) in this row, three capital letters. |
| 5 | `gateway_refund_ref` | character varying(255) | no | - | UQ | sensitive | external_reference | The gateway's reference for the refund. Sensitive. |
| 6 | `refund_reason` | character varying(500) | yes | - | - | internal | rls | Why the refund was made, in words. NULL when none was given. |
| 7 | `refund_status` | character varying(20) | no | 'completed'::character varying | - | internal | rls | Status of the refund at the gateway (for example processed, pending, failed). |
| 8 | `processed_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | Instant (UTC) at which this row's processed happened. |
| 9 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was created (UTC). Set by trigger and never changed. |
| 10 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was last changed (UTC). Set by trigger. |
| 11 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 12 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `commercial.subscription`

Active subscription periods per licence enforcing strictly non-overlapping active ranges

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `subscription_licence_id` | bigint | no | - | FK to commercial.subscription_licence | internal | grants_only | Reference to commercial.subscription_licence (subscription licence). Required. |
| 3 | `subscription_plan_id` | bigint | no | - | FK to commercial.subscription_plan | internal | grants_only | Reference to commercial.subscription_plan (subscription plan). Required. |
| 4 | `period_start` | timestamp with time zone | no | - | - | internal | grants_only | Start of the paid period (inclusive). |
| 5 | `period_end` | timestamp with time zone | no | - | - | internal | grants_only | End of the paid period (exclusive). Active periods of one licence may not overlap. |
| 6 | `auto_renew` | boolean | no | true | - | internal | grants_only | True when the subscription renews itself at period_end unless cancelled. |
| 7 | `subscription_status` | character varying(20) | no | 'active'::character varying | - | internal | grants_only | One of: active, cancelled, expired. |
| 8 | `cancelled_at` | timestamp with time zone | yes | - | - | internal | grants_only | Nullable: NULL until the event this timestamp records has happened. |
| 9 | `cancellation_reason` | character varying(500) | yes | - | - | internal | grants_only | Why it was cancelled. NULL unless the subscription was cancelled. |
| 10 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 11 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 12 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 13 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `commercial.subscription_licence`

Corporate subscription licences specifying positive maximum users and device limits per user

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | rls | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `organization_id` | bigint | no | - | FK to recruitment.organization | internal | rls | Reference to recruitment.organization (organization). Required. |
| 3 | `licence_key` | character varying(64) | no | - | UQ | internal | rls | The licence's unique key, shown to the customer. Sensitive in the sense of a credential; kept out of the audit log. |
| 4 | `licence_name` | character varying(100) | no | - | - | internal | rls | Product name on the licence. |
| 5 | `max_users` | integer | no | - | - | internal | rls | Seats: the most users who may hold a seat at once. A positive integer. |
| 6 | `max_devices_per_user` | integer | no | - | - | internal | rls | The most devices one user may be logged in on at once. A positive integer; the login function enforces it. |
| 7 | `valid_from` | timestamp with time zone | no | - | - | internal | rls | Start of the licence (inclusive). |
| 8 | `valid_to` | timestamp with time zone | no | - | - | internal | rls | End of the licence (inclusive of the instant; not before valid_from). |
| 9 | `licence_status` | character varying(20) | no | 'active'::character varying | - | internal | rls | One of: active, expired, suspended, cancelled. |
| 10 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was created (UTC). Set by trigger and never changed. |
| 11 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was last changed (UTC). Set by trigger. |
| 12 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 13 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `commercial.subscription_plan`

Catalog of commercial subscription plans, tiers, and entitled quotas

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `plan_code` | character varying(50) | no | - | UQ | internal | grants_only | Stable code of the plan, unique. |
| 3 | `name` | character varying(100) | no | - | - | internal | grants_only | Plan name shown to customers. |
| 4 | `tier` | character varying(30) | no | 'standard'::character varying | - | internal | grants_only | One of: free, standard, premium, enterprise. |
| 5 | `billing_interval` | character varying(20) | no | 'monthly'::character varying | - | internal | grants_only | One of: monthly, quarterly, semi_annual, annual. |
| 6 | `price_amount` | numeric(14,2) | no | - | - | internal | grants_only | Price per billing interval, in currency_code. |
| 7 | `currency_code` | character(3) | no | 'USD'::bpchar | - | internal | grants_only | ISO 4217 currency of the amount(s) in this row, three capital letters. |
| 8 | `job_postings_quota` | integer | no | 5 | - | internal | grants_only | Job postings included per period. |
| 9 | `profile_downloads_quota` | integer | no | 50 | - | internal | grants_only | Profile downloads included per period. |
| 10 | `outreach_credits_quota` | integer | no | 100 | - | internal | grants_only | Outreach messages included per period. |
| 11 | `is_active` | boolean | no | true | - | internal | grants_only | True when active. Default true. |
| 12 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 13 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 14 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 15 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `commercial.wallet`

Prepaid credit wallet held by organizations for postings, downloads, and outreach

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | rls | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `organization_id` | bigint | no | - | FK to recruitment.organization | internal | rls | Reference to recruitment.organization (organization). Required. |
| 3 | `balance` | numeric(14,2) | no | 0.00 | - | internal | rls | Current credit, in currency_code, never negative. Must equal balance_after of the latest ledger entry; the reconciliation KPI (KPI-007) chec |
| 4 | `currency_code` | character(3) | no | 'USD'::bpchar | - | internal | rls | ISO 4217 currency of the amount(s) in this row, three capital letters. |
| 5 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was created (UTC). Set by trigger and never changed. |
| 6 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was last changed (UTC). Set by trigger. |
| 7 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 8 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `commercial.wallet_ledger`

Strictly append-only financial ledger tracking credit and debit movements with explicit correction references

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | rls | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `wallet_id` | bigint | no | - | FK to commercial.wallet | internal | rls | Reference to commercial.wallet (wallet). Required. |
| 3 | `entry_type` | character varying(20) | no | - | - | internal | rls | One of: credit, debit, correction_credit, correction_debit. |
| 4 | `amount` | numeric(14,2) | no | - | - | internal | rls | Amount of this entry, always positive, in currency_code; entry_type gives the direction. |
| 5 | `currency_code` | character(3) | no | 'USD'::bpchar | - | internal | rls | ISO 4217 currency of the amount(s) in this row, three capital letters. |
| 6 | `balance_after` | numeric(14,2) | no | - | - | internal | rls | Wallet balance immediately after this entry, never negative. |
| 7 | `reference_type` | character varying(40) | no | - | - | internal | rls | One of: recharge, profile_download, outreach_fee, job_posting_fee, gig_commission, correction. |
| 8 | `reference_id` | bigint | yes | - | - | internal | rls | Id of the thing the entry paid for (for example the payment order). NULL when there is none, such as a correction. |
| 9 | `correction_of_ledger_id` | bigint | yes | - | FK to commercial.wallet_ledger | internal | rls | Reference to commercial.wallet_ledger (correction of ledger). NULL when there is none. |
| 10 | `notes` | character varying(500) | yes | - | - | internal | rls | Free-text note. NULL when none. |
| 11 | `created_by_user_account_id` | bigint | no | - | FK to core.user_account | internal | rls | Account that created the row, taken from the session. NULL when the system created it (seed, migration, scheduled job). |
| 12 | `recorded_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | Instant (UTC) at which this row's recorded happened. |

## `core.consent_record`

Auditable records of user consent for legal and privacy regulations

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | rls | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `user_account_id` | bigint | no | - | FK to core.user_account | internal | rls | Reference to core.user_account (user account). Required. |
| 3 | `consent_type` | character varying(50) | no | - | - | internal | rls | One of: terms_of_service, privacy_policy, marketing_communications, third_party_recruiter_sharing, background_verification. |
| 4 | `consent_version` | character varying(20) | no | - | - | internal | rls | Version of the terms or policy the user responded to. |
| 5 | `is_granted` | boolean | no | true | - | internal | rls | True when granted. Default true. |
| 6 | `client_ip` | character varying(45) | yes | - | - | personal | rls | Address the consent was given from. NULL when not captured. Personal data. |
| 7 | `user_agent` | character varying(500) | yes | - | - | personal | rls | Client software the consent was given from. NULL when not captured. Personal data. |
| 8 | `granted_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | Instant (UTC) at which this row's granted happened. |
| 9 | `revoked_at` | timestamp with time zone | yes | - | - | internal | rls | Nullable: NULL until the event this timestamp records has happened. |
| 10 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was created (UTC). Set by trigger and never changed. |
| 11 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was last changed (UTC). Set by trigger. |
| 12 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 13 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `core.identity_verification`

Outcome of a national-identity check done by an external service (boundary identity_verification). Stores the outcome and an opaque token; the identity number itself never reaches the database.

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | rls | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `user_account_id` | bigint | no | - | FK to core.user_account | internal | rls | Reference to core.user_account (the person being verified). Required. |
| 3 | `provider_code` | character varying(40) | no | - | - | internal | rls | Which verification service handled the check (a code, not a name); the service is the source of truth for the check. |
| 4 | `request_id` | character varying(100) | no | - | - | internal | rls | The service's identifier for this check; with provider_code it makes a repeated callback a no-op. |
| 5 | `verification_status` | character varying(20) | no | 'pending'::character varying | - | internal | rls | pending, verified, rejected or expired; moves only along master.status_transition. |
| 6 | `provider_token_ref` | character varying(200) | yes | - | - | sensitive | external_reference | Opaque reference the service returned for a passed check. Never an identity number. NULL until the check passes. |
| 7 | `requested_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the check was requested (UTC). |
| 8 | `verified_at` | timestamp with time zone | yes | - | - | internal | rls | When the service confirmed the check (UTC). NULL unless the status is verified or has been. |
| 9 | `expires_at` | timestamp with time zone | yes | - | - | internal | rls | When the outcome stops counting (UTC). NULL when the outcome does not expire. |
| 10 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was created (UTC). Set by trigger and never changed. |
| 11 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was last changed (UTC). Set by trigger. |
| 12 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Account that created the row, taken from the session. NULL when the system created it (seed, migration, scheduled job). |
| 13 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Account that last changed the row, taken from the session. NULL when the system changed it. |

## `core.permission`

Granular capability tokens assigned to platform roles

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `code` | character varying(80) | no | - | UQ | internal | grants_only | Stable machine-readable code (lower case), unique within the table. |
| 3 | `name` | character varying(120) | no | - | - | internal | grants_only | Short name shown to administrators. |
| 4 | `module` | character varying(50) | no | - | - | internal | grants_only | Area of the platform the permission belongs to. |
| 5 | `description` | character varying(500) | yes | - | - | internal | grants_only | What the permission allows. NULL when the name says it all. |
| 6 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 7 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 8 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 9 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `core.role`

Named platform roles used by the access-control layer

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `name` | character varying(50) | no | - | UQ | internal | grants_only | Role name, for example candidate, recruiter, admin. |
| 3 | `description` | character varying(500) | yes | - | - | internal | grants_only | What the role is for. NULL when the name says it all. |
| 4 | `is_system_role` | boolean | no | true | - | internal | grants_only | True when system role. Default true. |
| 5 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 6 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 7 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 8 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `core.role_permission`

Mapping defining which permissions belong to which platform roles

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `role_id` | bigint | no | - | FK to core.role | internal | grants_only | Reference to core.role (role). Required. |
| 3 | `permission_id` | bigint | no | - | FK to core.permission | internal | grants_only | Reference to core.permission (permission). Required. |
| 4 | `granted_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | Instant (UTC) at which this row's granted happened. |
| 5 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 6 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 7 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 8 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `core.user_account`

Shared user identity and account lifecycle; excludes domain-specific profiles

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `email` | character varying(254) | no | - | UQ | personal | grants_only | Lowercase account email address, unique within Talentra |
| 3 | `phone_e164` | character varying(16) | yes | - | - | personal | grants_only | Phone number in E.164 format with country code, for example +919812345678. NULL until the user adds one; sign-up needs only an email. |
| 4 | `phone_country_code` | character varying(2) | yes | - | - | internal | grants_only | ISO 3166 alpha-2 country of the phone number. NULL exactly when phone_e164 is NULL (a CHECK keeps the pair together). |
| 5 | `password_hash` | text | yes | - | - | sensitive | hashed | DEPRECATED: use core.user_credential. Kept for backward compatibility; must be NULL or an argon2id/bcrypt hash. |
| 6 | `account_status` | character varying(20) | no | 'active'::character varying | - | internal | grants_only | One of: pending, active, suspended, deactivated. |
| 7 | `preferred_language` | character varying(10) | no | 'en'::character varying | - | internal | grants_only | Language code for the interface (for example en, hi); falls back to en when untranslated. |
| 8 | `email_verified_at` | timestamp with time zone | yes | - | - | internal | grants_only | Nullable: NULL until the event this timestamp records has happened. |
| 9 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 10 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 11 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 12 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 13 | `deleted_at` | timestamp with time zone | yes | - | - | internal | grants_only | Nullable: NULL means the row is live. Set when the row is soft-deleted; default queries use the active_ view. |
| 14 | `deleted_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: NULL while the row is live, and when the deletion was done by a system job (retention). |

## `core.user_block`

Blocking relationship ensuring blocked recruiters/employers cannot view the blocker candidate

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `blocker_user_account_id` | bigint | no | - | FK to core.user_account | internal | grants_only | Reference to core.user_account (blocker user account). Required. |
| 3 | `blocked_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Reference to core.user_account (blocked user account). NULL when there is none. |
| 4 | `blocked_organization_id` | bigint | yes | - | FK to recruitment.organization | internal | grants_only | Reference to recruitment.organization (blocked organization). NULL when there is none. |
| 5 | `block_reason` | character varying(500) | yes | - | - | personal | grants_only | Why the block was made, in the blocker's words. NULL when none was given. |
| 6 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 7 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 8 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 9 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `core.user_credential`

Authentication secrets and credentials separated from the identity record; never stores cleartext

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | rls | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `user_account_id` | bigint | no | - | FK to core.user_account | internal | rls | Reference to core.user_account (user account). Required. |
| 3 | `credential_type` | character varying(30) | no | 'password'::character varying | - | internal | rls | One of: password, api_key, totp_secret, recovery_code, oauth_sub. |
| 4 | `credential_identifier` | character varying(255) | no | - | - | personal | rls | What the user types to authenticate: the email for a password, a key id for an API key. Personal data; kept out of the audit log. |
| 5 | `secret_hash` | text | no | - | - | sensitive | hashed | Hexadecimal hash (SHA-256 unless the column says otherwise); never the original value. |
| 6 | `algorithm` | character varying(50) | no | 'argon2id'::character varying | - | internal | rls | Hashing algorithm of secret_hash, for example argon2id. A CHECK on the hash itself enforces an approved format. |
| 7 | `is_active` | boolean | no | true | - | internal | rls | True when active. Default true. |
| 8 | `expires_at` | timestamp with time zone | yes | - | - | internal | rls | Nullable: NULL until the event this timestamp records has happened. |
| 9 | `last_used_at` | timestamp with time zone | yes | - | - | internal | rls | Nullable: NULL until the event this timestamp records has happened. |
| 10 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was created (UTC). Set by trigger and never changed. |
| 11 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was last changed (UTC). Set by trigger. |
| 12 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 13 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `core.user_device`

Known physical and virtual devices registered per user account

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | rls | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `user_account_id` | bigint | no | - | FK to core.user_account | internal | rls | Reference to core.user_account (user account). Required. |
| 3 | `device_identifier` | character varying(255) | no | - | - | personal | rls | Identifier the client generated for the device. Personal data. |
| 4 | `device_name` | character varying(100) | yes | - | - | personal | rls | Name the user gave the device. NULL when not given. |
| 5 | `device_type` | character varying(30) | no | 'desktop'::character varying | - | internal | rls | One of: desktop, laptop, mobile, tablet, other. |
| 6 | `operating_system` | character varying(50) | yes | - | - | internal | rls | Operating system reported by the client. NULL when not reported. |
| 7 | `is_trusted` | boolean | no | true | - | internal | rls | True when trusted. Default true. |
| 8 | `first_seen_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | Instant (UTC) at which this row's first seen happened. |
| 9 | `last_seen_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | Instant (UTC) at which this row's last seen happened. |
| 10 | `revoked_at` | timestamp with time zone | yes | - | - | internal | rls | Nullable: NULL until the event this timestamp records has happened. |
| 11 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was created (UTC). Set by trigger and never changed. |
| 12 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was last changed (UTC). Set by trigger. |
| 13 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 14 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `core.user_role`

Many-to-many assignment of platform roles to user accounts

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `user_account_id` | bigint | no | - | FK to core.user_account | internal | grants_only | Reference to core.user_account (user account). Required. |
| 3 | `role_id` | bigint | no | - | FK to core.role | internal | grants_only | Reference to core.role (role). Required. |
| 4 | `assigned_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | Instant (UTC) at which this row's assigned happened. |
| 5 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 6 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 7 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 8 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `core.user_session`

Session history with device identifiers and hashed session tokens

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | rls | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `user_account_id` | bigint | no | - | FK to core.user_account | internal | rls | Reference to core.user_account (user account). Required. |
| 3 | `device_identifier` | character varying(255) | no | - | - | personal | rls | Device the session runs on; counted against the licence's device limit while the session is open. |
| 4 | `session_token_hash` | character varying(255) | no | - | UQ | sensitive | hashed | Hash of the session token; raw authentication tokens must never be stored |
| 5 | `started_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | Instant (UTC) at which this row's started happened. |
| 6 | `last_activity_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | Instant (UTC) at which this row's last activity happened. |
| 7 | `ended_at` | timestamp with time zone | yes | - | - | internal | rls | Nullable: NULL until the event this timestamp records has happened. |
| 8 | `revoked_at` | timestamp with time zone | yes | - | - | internal | rls | Nullable: NULL until the event this timestamp records has happened. |
| 9 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was created (UTC). Set by trigger and never changed. |
| 10 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was last changed (UTC). Set by trigger. |
| 11 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 12 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `gig.gig_application`

Applications submitted by gig workers to gig requests

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `gig_request_id` | bigint | no | - | FK to gig.gig_request | internal | grants_only | Reference to gig.gig_request (gig request). Required. |
| 3 | `gig_worker_profile_id` | bigint | no | - | FK to gig.gig_worker_profile | internal | grants_only | Reference to gig.gig_worker_profile (gig worker profile). Required. |
| 4 | `bid_amount` | numeric(14,2) | no | - | - | personal | grants_only | Price the worker offers, in currency_code. |
| 5 | `currency_code` | character(3) | no | 'USD'::bpchar | - | internal | grants_only | ISO 4217 currency of the amount(s) in this row, three capital letters. |
| 6 | `proposed_duration_days` | integer | yes | - | - | internal | grants_only | Days the worker expects the work to take. NULL when the worker gave no estimate. |
| 7 | `pitch` | text | yes | - | - | personal | grants_only | The worker's proposal text. NULL when the worker applied without one. |
| 8 | `application_status` | character varying(20) | no | 'submitted'::character varying | - | internal | grants_only | One of: accepted, rejected, accepted, rejected. |
| 9 | `applied_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | Instant (UTC) at which this row's applied happened. |
| 10 | `decided_at` | timestamp with time zone | yes | - | - | internal | grants_only | Nullable: NULL until the event this timestamp records has happened. |
| 11 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 12 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 13 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 14 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `gig.gig_assignment`

Accepted gig assignments storing external fulfilment references and enforcing non-overlapping active windows

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `gig_request_id` | bigint | no | - | FK to gig.gig_request, UQ | internal | grants_only | Reference to gig.gig_request (gig request). Required. |
| 3 | `gig_application_id` | bigint | no | - | FK to gig.gig_application, UQ | internal | grants_only | Reference to gig.gig_application (gig application). Required. |
| 4 | `gig_worker_profile_id` | bigint | no | - | FK to gig.gig_worker_profile | internal | grants_only | Reference to gig.gig_worker_profile (gig worker profile). Required. |
| 5 | `assigned_start_date` | date | no | - | - | internal | grants_only | Calendar date of assigned start. |
| 6 | `assigned_end_date` | date | no | - | - | internal | grants_only | Calendar date of assigned end. |
| 7 | `agreed_amount` | numeric(14,2) | no | - | - | internal | grants_only | Price agreed for the assignment, in currency_code. |
| 8 | `currency_code` | character(3) | no | 'USD'::bpchar | - | internal | grants_only | ISO 4217 currency of the amount(s) in this row, three capital letters. |
| 9 | `assignment_status` | character varying(20) | no | 'active'::character varying | - | internal | grants_only | One of: active, completed, terminated. |
| 10 | `external_handoff_ref` | character varying(255) | no | - | UQ | internal | grants_only | Reference to this assignment in the fulfilment system, which runs the work. |
| 11 | `external_status` | character varying(50) | no | 'pending_handoff'::character varying | - | internal | grants_only | Status the fulfilment system last reported, as a string; reconciled into assignment_status. |
| 12 | `last_reconciled_at` | timestamp with time zone | yes | - | - | internal | grants_only | Nullable: NULL until the event this timestamp records has happened. |
| 13 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 14 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 15 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 16 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `gig.gig_external_earnings`

Integration boundary table storing reconciled earnings sourced from external fulfilment engine

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `gig_assignment_id` | bigint | no | - | FK to gig.gig_assignment, UQ | internal | grants_only | Reference to gig.gig_assignment (gig assignment). Required. |
| 3 | `estimated_earnings` | numeric(14,2) | no | 0.00 | - | internal | grants_only | Earnings the fulfilment system estimated, in currency_code. |
| 4 | `total_earnings` | numeric(14,2) | no | 0.00 | - | internal | grants_only | Earnings it reported as final, in currency_code. 0 until the work is finished. |
| 5 | `projected_earnings` | numeric(14,2) | no | 0.00 | - | internal | grants_only | Earnings it projects by the end of the assignment, in currency_code. |
| 6 | `currency_code` | character(3) | no | 'USD'::bpchar | - | internal | grants_only | ISO 4217 currency of the amount(s) in this row, three capital letters. |
| 7 | `reconciled_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | Instant (UTC) at which this row's reconciled happened. |
| 8 | `external_sync_hash` | character varying(128) | yes | - | - | internal | grants_only | Hash of the payload last received from the fulfilment system, used to skip unchanged updates. NULL until the first sync. |
| 9 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 10 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 11 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 12 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `gig.gig_rating`

Requester satisfaction rating and feedback on completed gigs

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `gig_assignment_id` | bigint | no | - | FK to gig.gig_assignment, UQ | internal | grants_only | Reference to gig.gig_assignment (gig assignment). Required. |
| 3 | `rater_user_account_id` | bigint | no | - | FK to core.user_account | internal | grants_only | Reference to core.user_account (rater user account). Required. |
| 4 | `rating_score` | numeric(3,2) | no | - | - | internal | grants_only | Overall rating from 1.00 to 5.00. |
| 5 | `quality_score` | numeric(3,2) | yes | - | - | internal | grants_only | Quality of work, 1.00 to 5.00. NULL when the requester gave only an overall score. |
| 6 | `communication_score` | numeric(3,2) | yes | - | - | internal | grants_only | Communication, 1.00 to 5.00. NULL when not scored. |
| 7 | `review_text` | text | yes | - | - | personal | grants_only | Written review. NULL when the requester wrote none. |
| 8 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 9 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 10 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 11 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `gig.gig_request`

Short-duration project requirements with defined price and deliverables

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `organization_id` | bigint | no | - | FK to recruitment.organization | internal | grants_only | Reference to recruitment.organization (organization). Required. |
| 3 | `created_by_user_account_id` | bigint | no | - | FK to core.user_account | internal | grants_only | Account that created the row, taken from the session. NULL when the system created it (seed, migration, scheduled job). |
| 4 | `title` | character varying(200) | no | - | - | internal | grants_only | Short title of the project. |
| 5 | `description` | text | no | - | - | internal | grants_only | What the project is. |
| 6 | `deliverables` | text | no | - | - | internal | grants_only | What the worker must hand over. |
| 7 | `pricing_type` | character varying(20) | no | 'fixed'::character varying | - | internal | grants_only | One of: fixed, hourly_rate, daily_rate. |
| 8 | `budget_amount` | numeric(14,2) | no | - | - | internal | grants_only | Budget in currency_code; pricing_type says whether it is a total, an hourly rate or a daily rate. |
| 9 | `currency_code` | character(3) | no | 'USD'::bpchar | - | internal | grants_only | ISO 4217 currency of the amount(s) in this row, three capital letters. |
| 10 | `start_date` | date | no | - | - | internal | grants_only | Calendar date of start. |
| 11 | `end_date` | date | no | - | - | internal | grants_only | Calendar date of end. |
| 12 | `request_status` | character varying(20) | no | 'open'::character varying | - | internal | grants_only | One of: open, awarded, in_progress, completed, cancelled. |
| 13 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 14 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 15 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 16 | `deleted_at` | timestamp with time zone | yes | - | - | internal | grants_only | Nullable: NULL means the row is live. Set when the row is soft-deleted; default queries use the active_ view. |
| 17 | `deleted_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: NULL while the row is live, and when the deletion was done by a system job (retention). |

## `gig.gig_worker_availability`

Calendar availability windows declared by gig workers

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `gig_worker_profile_id` | bigint | no | - | FK to gig.gig_worker_profile | internal | grants_only | Reference to gig.gig_worker_profile (gig worker profile). Required. |
| 3 | `available_from` | date | no | - | - | internal | grants_only | First day the worker is available (inclusive). |
| 4 | `available_to` | date | no | - | - | internal | grants_only | Last day the worker is available (inclusive); not before available_from. |
| 5 | `daily_available_hours` | numeric(4,1) | no | 8.0 | - | internal | grants_only | Duration in hours. |
| 6 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 7 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 8 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 9 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `gig.gig_worker_preference`

Maintained list of favourite and blacklisted gig workers per organization

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `organization_id` | bigint | no | - | FK to recruitment.organization | internal | grants_only | Reference to recruitment.organization (organization). Required. |
| 3 | `gig_worker_profile_id` | bigint | no | - | FK to gig.gig_worker_profile | internal | grants_only | Reference to gig.gig_worker_profile (gig worker profile). Required. |
| 4 | `preference_type` | character varying(20) | no | - | - | internal | grants_only | One of: favourite, blacklisted. |
| 5 | `reason` | character varying(500) | yes | - | - | personal | grants_only | Why the organisation favourited or blacklisted the worker. NULL when no reason was given. |
| 6 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 7 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 8 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 9 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `gig.gig_worker_profile`

Distinct gig worker profile containing charge rates, verification, and availability

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `user_account_id` | bigint | no | - | FK to core.user_account, UQ | internal | grants_only | Reference to core.user_account (user account). Required. |
| 3 | `headline` | character varying(150) | no | - | - | personal | grants_only | One-line professional headline. |
| 4 | `bio` | text | yes | - | - | personal | grants_only | Longer self-description. NULL when the worker wrote none. |
| 5 | `hourly_rate` | numeric(14,2) | yes | - | - | personal | grants_only | Rate per hour in currency_code. NULL when the worker quotes no hourly rate. |
| 6 | `daily_rate` | numeric(14,2) | yes | - | - | personal | grants_only | Rate per day in currency_code. NULL when the worker quotes no daily rate. |
| 7 | `currency_code` | character(3) | no | 'USD'::bpchar | - | internal | grants_only | ISO 4217 currency of the amount(s) in this row, three capital letters. |
| 8 | `is_available` | boolean | no | true | - | internal | grants_only | True when available. Default true. |
| 9 | `total_completed_gigs` | integer | no | 0 | - | internal | grants_only | Count of assignments completed through the platform; maintained from finished assignments. |
| 10 | `average_rating` | numeric(3,2) | yes | - | - | internal | grants_only | Mean of the ratings received, 1.00 to 5.00. NULL until the first rating. |
| 11 | `verification_status` | character varying(20) | no | 'unverified'::character varying | - | internal | grants_only | One of: unverified, verified, suspended. |
| 12 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 13 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 14 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 15 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 16 | `deleted_at` | timestamp with time zone | yes | - | - | internal | grants_only | Nullable: NULL means the row is live. Set when the row is soft-deleted; default queries use the active_ view. |
| 17 | `deleted_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: NULL while the row is live, and when the deletion was done by a system job (retention). |

## `gig.gig_worker_service`

Service offerings provided by a gig worker linked to canonical master skills

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `gig_worker_profile_id` | bigint | no | - | FK to gig.gig_worker_profile | internal | grants_only | Reference to gig.gig_worker_profile (gig worker profile). Required. |
| 3 | `skill_id` | bigint | no | - | FK to master.skill | internal | grants_only | Reference to master.skill (skill). Required. |
| 4 | `custom_title` | character varying(150) | yes | - | - | personal | grants_only | The worker's own name for this service. NULL to use the skill's name. |
| 5 | `rate_override` | numeric(14,2) | yes | - | - | internal | grants_only | Rate for this service in currency_code, replacing the profile rate. NULL to use the profile rate. |
| 6 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 7 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 8 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 9 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 10 | `currency_code` | character(3) | yes | - | - | internal | grants_only | Nullable: required when rate_override is set (ISO 4217), otherwise NULL. |

## `master.city`

City catalogue associated with a state or province

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | public | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `state_id` | bigint | no | - | FK to master.state | public | grants_only | Reference to master.state (state). Required. |
| 3 | `name` | character varying(100) | no | - | - | public | grants_only | City name in English; the display name in other languages is a translation key in messaging.ui_translation. |
| 4 | `is_active` | boolean | no | true | - | public | grants_only | True when active. Default true. |
| 5 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | public | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 6 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | public | grants_only | When the row was last changed (UTC). Set by trigger. |
| 7 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | public | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 8 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | public | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `master.country`

Country catalogue using ISO alpha-2 and alpha-3 codes

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | public | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `iso_alpha2` | character(2) | no | - | UQ | public | grants_only | ISO 3166-1 alpha-2 code (two capital letters). |
| 3 | `iso_alpha3` | character(3) | no | - | UQ | public | grants_only | ISO 3166-1 alpha-3 code (three capital letters). |
| 4 | `name` | character varying(100) | no | - | UQ | public | grants_only | Country name in English; the display name in other languages is a translation key in messaging.ui_translation. |
| 5 | `phone_calling_code` | character varying(8) | yes | - | - | public | grants_only | International dialling code with a plus sign, for example +91. NULL when none is recorded. |
| 6 | `is_active` | boolean | no | true | - | public | grants_only | True when active. Default true. |
| 7 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | public | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 8 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | public | grants_only | When the row was last changed (UTC). Set by trigger. |
| 9 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | public | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 10 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | public | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `master.employment_type`

Employment arrangements such as full-time, contract, and internship

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | public | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `code` | character varying(30) | no | - | UQ | public | grants_only | Stable machine-readable code (lower case), unique within the table. |
| 3 | `name` | character varying(80) | no | - | UQ | public | grants_only | Employment type name in English; the display name in other languages is a translation key in messaging.ui_translation. |
| 4 | `is_active` | boolean | no | true | - | public | grants_only | True when active. Default true. |
| 5 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | public | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 6 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | public | grants_only | When the row was last changed (UTC). Set by trigger. |
| 7 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | public | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 8 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | public | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `master.enumeration_value`

Every value a CHECK-constrained column accepts, with order and active flag. Mirrors the CHECK constraints (which stay authoritative); display names are messaging.ui_translation rows keyed enum.<schema>.<table>.<column>.<code>.

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | public | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `column_ref` | character varying(150) | no | - | - | public | grants_only | schema.table.column whose CHECK constraint lists this value. |
| 3 | `code` | character varying(80) | no | - | - | public | grants_only | The value as stored in the column. |
| 4 | `sort_order` | integer | no | - | - | public | grants_only | Position when the values are listed, starting at 1; follows the order in the CHECK constraint, which lists them in lifecycle order where the |
| 5 | `is_active` | boolean | no | true | - | public | grants_only | False when the CHECK constraint no longer accepts the value; the row is kept so old data can still be labelled. |
| 6 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | public | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 7 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | public | grants_only | When the row was last changed (UTC). Set by trigger. |
| 8 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | public | grants_only | Account that created the row, taken from the session. NULL when the system created it (seed, migration, scheduled job). |
| 9 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | public | grants_only | Account that last changed the row, taken from the session. NULL when the system changed it. |

## `master.industry`

Industry classification catalogue

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | public | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `name` | character varying(120) | no | - | - | public | grants_only | Industry name in English; the display name in other languages is a translation key in messaging.ui_translation. |
| 3 | `normalized_name` | character varying(120) | no | - | UQ | public | grants_only | Lower-case, trimmed form of name used for matching and uniqueness. |
| 4 | `is_active` | boolean | no | true | - | public | grants_only | True when active. Default true. |
| 5 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | public | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 6 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | public | grants_only | When the row was last changed (UTC). Set by trigger. |
| 7 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | public | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 8 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | public | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `master.job_role`

Canonical job titles, optionally associated with an industry

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | public | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `industry_id` | bigint | yes | - | FK to master.industry | public | grants_only | Reference to master.industry (industry). NULL when there is none. |
| 3 | `name` | character varying(120) | no | - | - | public | grants_only | Job role name in English; the display name in other languages is a translation key in messaging.ui_translation. |
| 4 | `normalized_name` | character varying(120) | no | - | - | public | grants_only | Lower-case, trimmed form of name used for matching and uniqueness. |
| 5 | `description` | character varying(500) | yes | - | - | public | grants_only | What the role does. NULL when the name is enough. |
| 6 | `is_active` | boolean | no | true | - | public | grants_only | True when active. Default true. |
| 7 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | public | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 8 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | public | grants_only | When the row was last changed (UTC). Set by trigger. |
| 9 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | public | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 10 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | public | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `master.language`

Canonical ISO language catalogue used across profiles, postings, and UI translations

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | public | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `code` | character varying(10) | no | - | UQ | public | grants_only | Stable machine-readable code (lower case), unique within the table. |
| 3 | `name` | character varying(100) | no | - | UQ | public | grants_only | Language name in English; the display name in other languages is a translation key in messaging.ui_translation. |
| 4 | `native_name` | character varying(100) | yes | - | - | public | grants_only | The language's name in itself, for example Deutsch. NULL for languages whose native name has not been entered. |
| 5 | `is_active` | boolean | no | true | - | public | grants_only | True when active. Default true. |
| 6 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | public | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 7 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | public | grants_only | When the row was last changed (UTC). Set by trigger. |
| 8 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | public | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 9 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | public | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `master.qualification`

Canonical education and qualification catalogue

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | public | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `name` | character varying(150) | no | - | - | public | grants_only | Qualification name in English; the display name in other languages is a translation key in messaging.ui_translation. |
| 3 | `qualification_level` | character varying(30) | no | - | - | public | grants_only | One of: secondary, higher_secondary, diploma, undergraduate, postgraduate, doctorate, professional, other. |
| 4 | `is_active` | boolean | no | true | - | public | grants_only | True when active. Default true. |
| 5 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | public | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 6 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | public | grants_only | When the row was last changed (UTC). Set by trigger. |
| 7 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | public | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 8 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | public | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `master.skill`

Canonical skill catalogue used by candidate profiles and job requirements

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | public | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `name` | character varying(120) | no | - | - | public | grants_only | Skill name in English; the display name in other languages is a translation key in messaging.ui_translation. |
| 3 | `normalized_name` | character varying(120) | no | - | UQ | public | grants_only | Lower-case, trimmed form of name used for matching and uniqueness. |
| 4 | `description` | character varying(500) | yes | - | - | public | grants_only | What the skill covers. NULL when the name is enough. |
| 5 | `is_active` | boolean | no | true | - | public | grants_only | True when active. Default true. |
| 6 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | public | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 7 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | public | grants_only | When the row was last changed (UTC). Set by trigger. |
| 8 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | public | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 9 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | public | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `master.state`

First-level country administrative divisions

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | public | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `country_id` | bigint | no | - | FK to master.country | public | grants_only | Reference to master.country (country). Required. |
| 3 | `name` | character varying(100) | no | - | - | public | grants_only | State or province name in English; the display name in other languages is a translation key in messaging.ui_translation. |
| 4 | `subdivision_code` | character varying(20) | yes | - | - | public | grants_only | ISO 3166-2 subdivision code. NULL when the state has none. |
| 5 | `is_active` | boolean | no | true | - | public | grants_only | True when active. Default true. |
| 6 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | public | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 7 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | public | grants_only | When the row was last changed (UTC). Set by trigger. |
| 8 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | public | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 9 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | public | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `master.status_machine_exemption`

Status columns deliberately left without transition rules, with the reason. tests/test_state_machines.sql fails for any status column that is neither governed nor listed here.

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | public | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `entity_code` | character varying(60) | no | - | - | public | grants_only | schema.table of the entity whose status column is exempt. |
| 3 | `column_name` | character varying(63) | no | - | - | public | grants_only | The exempt status column. |
| 4 | `exemption` | character varying(20) | no | - | - | public | grants_only | One of: external_driver, append_only_history. |
| 5 | `reason` | character varying(400) | no | - | - | public | grants_only | Why no transition rules apply. |
| 6 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | public | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 7 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | public | grants_only | When the row was last changed (UTC). Set by trigger. |
| 8 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | public | grants_only | Account that created the row, taken from the session. NULL when the system created it (seed, migration, scheduled job). |
| 9 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | public | grants_only | Account that last changed the row, taken from the session. NULL when the system changed it. |

## `master.status_transition`

Allowed moves of a status column. A status with no outgoing row is final. An update to a pair not listed here is rejected by enforce_status_transition.

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `entity_code` | character varying(60) | no | - | - | internal | grants_only | schema.table of the entity the rule governs. |
| 3 | `from_status` | character varying(30) | no | - | - | internal | grants_only | Status the row leaves. |
| 4 | `to_status` | character varying(30) | no | - | - | internal | grants_only | Status the row may enter. |
| 5 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 6 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 7 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 8 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `master.work_type`

Work location arrangements such as remote, hybrid, and on-site

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | public | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `code` | character varying(30) | no | - | UQ | public | grants_only | Stable machine-readable code (lower case), unique within the table. |
| 3 | `name` | character varying(80) | no | - | UQ | public | grants_only | Work arrangement name in English; the display name in other languages is a translation key in messaging.ui_translation. |
| 4 | `is_active` | boolean | no | true | - | public | grants_only | True when active. Default true. |
| 5 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | public | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 6 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | public | grants_only | When the row was last changed (UTC). Set by trigger. |
| 7 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | public | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 8 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | public | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `messaging.community_post`

Developer and job seeker community discussion posts

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `author_user_account_id` | bigint | no | - | FK to core.user_account | internal | grants_only | Reference to core.user_account (author user account). Required. |
| 3 | `title` | character varying(200) | no | - | - | personal | grants_only | Post title. |
| 4 | `content` | text | no | - | - | personal | grants_only | Post body, in the language named by content_language_code. |
| 5 | `topic` | character varying(50) | no | 'general'::character varying | - | internal | grants_only | Topic the post is filed under (for example career, interviews). |
| 6 | `likes_count` | integer | no | 0 | - | internal | grants_only | Number of likes. |
| 7 | `is_pinned` | boolean | no | false | - | internal | grants_only | True when pinned. Default false. |
| 8 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 9 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 10 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 11 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 12 | `deleted_at` | timestamp with time zone | yes | - | - | internal | grants_only | Nullable: NULL means the row is live. Set when the row is soft-deleted; default queries use the active_ view. |
| 13 | `deleted_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: NULL while the row is live, and when the deletion was done by a system job (retention). |
| 14 | `content_language_code` | character varying(10) | yes | - | FK to master.language | internal | grants_only | Nullable: language the post was written in, when known. |

## `messaging.external_reference`

Maps a Talentra row to the same thing in an external system, so a repeated sync updates instead of duplicating. One external id per Talentra row and the reverse.

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `boundary_code` | character varying(40) | no | - | FK to messaging.integration_boundary | internal | grants_only | Which integration boundary the external id belongs to (messaging.integration_boundary.code). |
| 3 | `entity_name` | character varying(100) | no | - | - | internal | grants_only | schema.table of the Talentra row the external id maps to. |
| 4 | `entity_id` | bigint | no | - | - | internal | grants_only | Primary key of that Talentra row. |
| 5 | `external_id` | character varying(200) | no | - | - | internal | grants_only | The other system's identifier for the same thing. |
| 6 | `external_hash` | character(64) | yes | - | - | internal | grants_only | SHA-256 of the payload last received for it, used to skip unchanged records. NULL before the first sync. |
| 7 | `last_synced_at` | timestamp with time zone | yes | - | - | internal | grants_only | When the pair was last synchronised (UTC). NULL before the first sync. |
| 8 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 9 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 10 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Account that created the row, taken from the session. NULL when the system created it (seed, migration, scheduled job). |
| 11 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Account that last changed the row, taken from the session. NULL when the system changed it. |

## `messaging.faq`

Self-service frequently asked questions

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `category` | character varying(50) | no | - | - | internal | grants_only | Group the question is listed under. |
| 3 | `question` | text | no | - | - | internal | grants_only | The question as shown. |
| 4 | `answer` | text | no | - | - | internal | grants_only | The answer as shown. |
| 5 | `sort_order` | integer | no | 1 | - | internal | grants_only | Position when listed; lower comes first. |
| 6 | `is_published` | boolean | no | true | - | internal | grants_only | True when published. Default true. |
| 7 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 8 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 9 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 10 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `messaging.integration_boundary`

Docket section 6: the nine external boundaries and the five answers required of each. The retry policy (attempts, backoff) is data, not code.

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `code` | character varying(40) | no | - | UQ | internal | grants_only | Stable machine-readable code (lower case), unique within the table. |
| 3 | `name` | character varying(100) | no | - | - | internal | grants_only | Boundary name from docket section 6. |
| 4 | `source_of_truth` | character varying(300) | no | - | - | internal | grants_only | Which system is authoritative for the data. |
| 5 | `stored_data` | character varying(500) | no | - | - | internal | grants_only | What Talentra keeps. |
| 6 | `referenced_data` | character varying(500) | no | - | - | internal | grants_only | What Talentra only points to and never copies. |
| 7 | `failure_behaviour` | character varying(500) | no | - | - | internal | grants_only | What happens when the other side is down. |
| 8 | `idempotency_rule` | character varying(300) | no | - | - | internal | grants_only | How a repeated message is recognised. |
| 9 | `audit_rule` | character varying(300) | no | - | - | internal | grants_only | How the exchange is recorded. |
| 10 | `is_optional` | boolean | no | false | - | internal | grants_only | An optional boundary (the docket says to treat geolocation as optional) never blocks the feature that triggered it: a dead letter degrades q |
| 11 | `max_attempts` | integer | no | 3 | - | internal | grants_only | How many times an exchange is tried before it becomes a dead letter. |
| 12 | `base_backoff_seconds` | integer | no | 30 | - | internal | grants_only | Seconds before the second attempt; doubles for each further attempt. |
| 13 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 14 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 15 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Account that created the row, taken from the session. NULL when the system created it (seed, migration, scheduled job). |
| 16 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Account that last changed the row, taken from the session. NULL when the system changed it. |

## `messaging.integration_event`

Every exchange with an external system. Idempotency key makes a replay a no-op; a failed event is retried with exponential backoff up to the boundary's limit, then becomes a dead letter that stays visible until a person requeues or closes it.

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `boundary_id` | bigint | no | - | FK to messaging.integration_boundary | internal | grants_only | Reference to messaging.integration_boundary (boundary). Required. |
| 3 | `direction` | character varying(8) | no | - | - | internal | grants_only | One of: outbound, inbound. |
| 4 | `event_type` | character varying(60) | no | - | - | internal | grants_only | Kind of exchange, for example payment.captured. |
| 5 | `idempotency_key` | character varying(150) | no | - | - | internal | grants_only | Key that makes a replay of the same exchange a no-op, unique per boundary and direction. |
| 6 | `entity_schema` | character varying(63) | yes | - | - | internal | grants_only | Nullable: the local row this exchange is about, when there is one (with entity_name and entity_id). |
| 7 | `entity_name` | character varying(63) | yes | - | - | internal | grants_only | Table of the local row the exchange concerns. NULL when it concerns none. |
| 8 | `entity_id` | bigint | yes | - | - | internal | grants_only | Id of that row. NULL when it concerns none. |
| 9 | `payload_json` | jsonb | yes | - | - | personal | grants_only | Nullable: not every exchange carries a body. Keep personal data and secrets out; reference ids instead. Capped at 64 KB. |
| 10 | `event_status` | character varying(12) | no | 'pending'::character varying | - | internal | grants_only | One of: pending, in_progress, succeeded, failed, dead_letter. |
| 11 | `attempts` | integer | no | 0 | - | internal | grants_only | Attempts made so far; at most the boundary's max_attempts. |
| 12 | `next_attempt_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | Instant (UTC) at which this row's next attempt happened. |
| 13 | `last_error` | character varying(500) | yes | - | - | internal | grants_only | Nullable: the most recent failure message; NULL until something fails. |
| 14 | `response_ref` | character varying(150) | yes | - | - | internal | grants_only | Nullable: the external system's reference for the exchange, set on success. |
| 15 | `completed_at` | timestamp with time zone | yes | - | - | internal | grants_only | Nullable: set when the exchange succeeded; a dead letter has none. |
| 16 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 17 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 18 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Account that created the row, taken from the session. NULL when the system created it (seed, migration, scheduled job). |
| 19 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Account that last changed the row, taken from the session. NULL when the system changed it. |

## `messaging.job_alert_preference`

Candidate saved job searches and notification alert frequencies

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | rls | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `user_account_id` | bigint | no | - | FK to core.user_account | internal | rls | Reference to core.user_account (user account). Required. |
| 3 | `alert_name` | character varying(100) | no | - | - | internal | rls | Name the user gave the saved search. |
| 4 | `keywords` | character varying(255) | yes | - | - | personal | rls | Search words. NULL for a filter-only alert. |
| 5 | `job_role_id` | bigint | yes | - | FK to master.job_role | internal | rls | Reference to master.job_role (job role). NULL when there is none. |
| 6 | `city_id` | bigint | yes | - | FK to master.city | internal | rls | Reference to master.city (city). NULL when there is none. |
| 7 | `work_type_id` | bigint | yes | - | FK to master.work_type | internal | rls | Reference to master.work_type (work type). NULL when there is none. |
| 8 | `minimum_salary` | numeric(14,2) | yes | - | - | internal | rls | Lowest salary the user wants, in currency_code. NULL for no minimum. |
| 9 | `frequency` | character varying(20) | no | 'daily'::character varying | - | internal | rls | One of: instant, daily, weekly. |
| 10 | `is_active` | boolean | no | true | - | internal | rls | True when active. Default true. |
| 11 | `last_dispatched_at` | timestamp with time zone | yes | - | - | internal | rls | Nullable: NULL until the event this timestamp records has happened. |
| 12 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was created (UTC). Set by trigger and never changed. |
| 13 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was last changed (UTC). Set by trigger. |
| 14 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 15 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 16 | `currency_code` | character(3) | yes | - | - | internal | rls | Nullable: required when minimum_salary is set (ISO 4217), otherwise NULL. |

## `messaging.legacy_field_mapping`

Boundary legacy_sync: for every field of the synchronised Talentra tables, which way data flows and who wins a conflict (docket section 6). Legacy field names are assumed; the legacy schema was not available (DEC-32).

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `legacy_entity` | character varying(60) | no | - | - | internal | grants_only | The legacy system's record type (assumed names: candidate, job, application, employer, candidate_skill). |
| 3 | `legacy_field` | character varying(80) | yes | - | - | internal | grants_only | The legacy system's field name (assumed; the legacy schema was not available). NULL for Talentra columns the legacy system has no equivalent |
| 4 | `talentra_table` | character varying(100) | no | - | - | internal | grants_only | schema.table receiving or sending the field. |
| 5 | `talentra_column` | character varying(63) | no | - | - | internal | grants_only | Column in talentra_table. |
| 6 | `direction` | character varying(15) | no | - | - | internal | grants_only | inbound (legacy to Talentra), outbound (Talentra to legacy), bidirectional, or not_synced. |
| 7 | `conflict_rule` | character varying(20) | yes | - | - | internal | grants_only | What wins when both sides changed: legacy_wins, talentra_wins, latest_update_wins, cutover_dependent or manual_review. NULL when the field i |
| 8 | `owner_role` | character varying(30) | no | - | - | internal | grants_only | Role that decides the rule for this field (DEC-30). |
| 9 | `note` | character varying(300) | no | - | - | internal | grants_only | Why the rule is what it is, or why the field is not synced. |
| 10 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 11 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 12 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Account that created the row, taken from the session. NULL when the system created it (seed, migration, scheduled job). |
| 13 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Account that last changed the row, taken from the session. NULL when the system changed it. |

## `messaging.notification_delivery`

High-volume record of notification deliveries across all external and internal channels

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | rls | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `recipient_user_account_id` | bigint | no | - | FK to core.user_account | internal | rls | Reference to core.user_account (recipient user account). Required. |
| 3 | `notification_template_id` | bigint | yes | - | FK to messaging.notification_template | internal | rls | Reference to messaging.notification_template (notification template). NULL when there is none. |
| 4 | `channel` | character varying(20) | no | 'in_app'::character varying | - | internal | rls | One of: in_app, email, sms, whatsapp, push. |
| 5 | `subject` | character varying(255) | yes | - | - | personal | rls | Subject line. NULL for channels with none (SMS, push). |
| 6 | `body_snippet` | character varying(500) | yes | - | - | personal | rls | First part of the message, kept for audit only. NULL when not retained. Personal data. |
| 7 | `external_provider_message_id` | character varying(255) | yes | - | - | internal | rls | The provider's id for the message. NULL until the provider accepts it. |
| 8 | `delivery_status` | character varying(20) | no | 'queued'::character varying | - | internal | rls | One of: queued, sent, delivered, failed, read. |
| 9 | `sent_at` | timestamp with time zone | yes | - | - | internal | rls | Nullable: NULL until the event this timestamp records has happened. |
| 10 | `delivered_at` | timestamp with time zone | yes | - | - | internal | rls | Nullable: NULL until the event this timestamp records has happened. |
| 11 | `read_at` | timestamp with time zone | yes | - | - | internal | rls | Nullable: NULL until the event this timestamp records has happened. |
| 12 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was created (UTC). Set by trigger and never changed. |
| 13 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was last changed (UTC). Set by trigger. |
| 14 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 15 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `messaging.notification_template`

Reusable templates for email, SMS, push, and in-app notifications

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `template_code` | character varying(80) | no | - | UQ | internal | grants_only | Stable code the application uses to pick the template. |
| 3 | `channel` | character varying(20) | no | 'in_app'::character varying | - | internal | grants_only | One of: in_app, email, sms, whatsapp, push. |
| 4 | `default_language_code` | character varying(10) | no | 'en'::character varying | - | internal | grants_only | Language the template is written in; other languages are translations. |
| 5 | `subject_template` | character varying(255) | yes | - | - | internal | grants_only | Subject with {{placeholders}}. NULL for channels with no subject. |
| 6 | `body_template` | text | no | - | - | internal | grants_only | Body with {{placeholders}}. |
| 7 | `is_active` | boolean | no | true | - | internal | grants_only | True when active. Default true. |
| 8 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 9 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 10 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 11 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `messaging.post_reaction`

User reactions to community posts

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `community_post_id` | bigint | no | - | FK to messaging.community_post | internal | grants_only | Reference to messaging.community_post (community post). Required. |
| 3 | `user_account_id` | bigint | no | - | FK to core.user_account | internal | grants_only | Reference to core.user_account (user account). Required. |
| 4 | `reaction_type` | character varying(20) | no | 'like'::character varying | - | internal | grants_only | One of: like, celebrate, support, insightful. |
| 5 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 6 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 7 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 8 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `messaging.referral_event`

Candidate and recruiter peer referral invitations and compensation tracking

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | rls | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `referrer_user_account_id` | bigint | no | - | FK to core.user_account | internal | rls | Reference to core.user_account (referrer user account). Required. |
| 3 | `referred_email` | character varying(254) | no | - | - | personal | rls | Address the invitation went to. Personal data. |
| 4 | `referral_code` | character varying(50) | no | - | - | internal | rls | Code in the invitation, unique. |
| 5 | `referred_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Reference to core.user_account (referred user account). NULL when there is none. |
| 6 | `status` | character varying(20) | no | 'invited'::character varying | - | internal | rls | One of: invited, registered, qualified_hire, reward_paid. |
| 7 | `reward_amount` | numeric(14,2) | yes | 0.00 | - | internal | rls | Reward owed to the referrer, in currency_code. NULL until a reward is earned. |
| 8 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was created (UTC). Set by trigger and never changed. |
| 9 | `qualified_at` | timestamp with time zone | yes | - | - | internal | rls | Nullable: NULL until the event this timestamp records has happened. |
| 10 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was last changed (UTC). Set by trigger. |
| 11 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 12 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 13 | `currency_code` | character(3) | yes | - | - | internal | rls | Nullable: required when reward_amount is set (ISO 4217), otherwise NULL. |

## `messaging.share_event`

A user shared a job through an outbound link (boundary social_sharing). The external post is never stored.

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | rls | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `user_account_id` | bigint | no | - | FK to core.user_account | internal | rls | Reference to core.user_account (who shared). Required. |
| 3 | `job_posting_id` | bigint | no | - | FK to recruitment.job_posting | internal | rls | Reference to recruitment.job_posting (what was shared). Required. |
| 4 | `channel` | character varying(20) | no | - | - | internal | rls | Where the link was shared: whatsapp, linkedin, x, facebook, email or copy_link. |
| 5 | `shared_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the share happened (UTC). |
| 6 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was created (UTC). Set by trigger and never changed. |
| 7 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was last changed (UTC). Set by trigger. |
| 8 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Account that created the row, taken from the session. NULL when the system created it (seed, migration, scheduled job). |
| 9 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Account that last changed the row, taken from the session. NULL when the system changed it. |

## `messaging.support_ticket`

Helpdesk support tickets logged by platform candidates or employers

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | rls | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `ticket_number` | character varying(50) | no | - | UQ | internal | rls | Human-readable ticket number, unique. |
| 3 | `requester_user_account_id` | bigint | no | - | FK to core.user_account | internal | rls | Reference to core.user_account (requester user account). Required. |
| 4 | `category` | character varying(40) | no | - | - | internal | rls | Kind of problem (account, billing, technical, privacy, other). |
| 5 | `subject` | character varying(200) | no | - | - | personal | rls | One-line summary written by the requester. Personal data. |
| 6 | `priority` | character varying(20) | no | 'medium'::character varying | - | internal | rls | One of: low, medium, high, urgent. |
| 7 | `ticket_status` | character varying(20) | no | 'open'::character varying | - | internal | rls | One of: open, in_progress, waiting_on_user, resolved, closed. |
| 8 | `assigned_agent_user_id` | bigint | yes | - | FK to core.user_account | internal | rls | Reference to core.user_account (assigned agent user). NULL when there is none. |
| 9 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was created (UTC). Set by trigger and never changed. |
| 10 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was last changed (UTC). Set by trigger. |
| 11 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 12 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 13 | `deleted_at` | timestamp with time zone | yes | - | - | internal | rls | Nullable: NULL means the row is live. Set when the row is soft-deleted; default queries use the active_ view. |
| 14 | `deleted_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: NULL while the row is live, and when the deletion was done by a system job (retention). |

## `messaging.sync_conflict`

Conflict log for the legacy sync. Holds hashes, not values, because the values may be personal data. A conflict the rule settled is logged as resolved; one that needs a person stays open until a choice is recorded.

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `mapping_id` | bigint | no | - | FK to messaging.legacy_field_mapping | internal | grants_only | Reference to messaging.legacy_field_mapping (the field in conflict). Required. |
| 3 | `entity_id` | bigint | no | - | - | internal | grants_only | Primary key of the Talentra row in conflict. |
| 4 | `legacy_value_sha256` | character(64) | no | - | - | internal | grants_only | SHA-256 of the legacy value; the value itself is not kept because it may be personal data. |
| 5 | `talentra_value_sha256` | character(64) | no | - | - | internal | grants_only | SHA-256 of the Talentra value at the time of the conflict. |
| 6 | `rule_outcome` | character varying(10) | no | - | - | internal | grants_only | What the mapping's rule decided: legacy, talentra or review. |
| 7 | `final_choice` | character varying(10) | yes | - | - | internal | grants_only | What a person chose when the rule said review: legacy or talentra. NULL until chosen, and for conflicts the rule settled. |
| 8 | `detected_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the conflict was found (UTC). |
| 9 | `resolved_at` | timestamp with time zone | yes | - | - | internal | grants_only | When the conflict was settled (UTC). NULL while a review is open. |
| 10 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 11 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 12 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Account that created the row, taken from the session. NULL when the system created it (seed, migration, scheduled job). |
| 13 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Account that last changed the row, taken from the session. NULL when the system changed it. |

## `messaging.ui_translation`

Multilingual UI strings by key and ISO language code

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `string_key` | character varying(150) | no | - | - | internal | grants_only | Key the interface asks for, for example btn.apply_job. Keys are never shown to users. |
| 3 | `language_code` | character varying(10) | no | - | FK to master.language | internal | grants_only | Reference to master.language (language code). Required. |
| 4 | `translated_text` | text | no | - | - | internal | grants_only | The text in language_code. |
| 5 | `is_verified` | boolean | no | true | - | internal | grants_only | True when verified. Default true. |
| 6 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 7 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 8 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 9 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `messaging.user_notification_preference`

Granular delivery channel toggles configured by users per notification category

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | rls | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `user_account_id` | bigint | no | - | FK to core.user_account | internal | rls | Reference to core.user_account (user account). Required. |
| 3 | `notification_category` | character varying(40) | no | - | - | internal | rls | One of: applications, job_alerts, gig_opportunities, marketing, security_alerts. |
| 4 | `channel` | character varying(20) | no | - | - | internal | rls | One of: in_app, email, sms, whatsapp, push. |
| 5 | `is_enabled` | boolean | no | true | - | internal | rls | True when enabled. Default true. |
| 6 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was created (UTC). Set by trigger and never changed. |
| 7 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was last changed (UTC). Set by trigger. |
| 8 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 9 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `messaging.user_privacy_preference`

Candidate privacy and confidentiality controls

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | rls | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `user_account_id` | bigint | no | - | FK to core.user_account, UQ | internal | rls | Reference to core.user_account (user account). Required. |
| 3 | `profile_visibility` | character varying(20) | no | 'recruiters'::character varying | - | internal | rls | One of: private, recruiters, public. |
| 4 | `allow_recruiter_direct_message` | boolean | no | true | - | internal | rls | True when recruiter direct message. Default true. |
| 5 | `show_salary_expectations` | boolean | no | false | - | internal | rls | True when salary expectations. Default false. |
| 6 | `show_current_employer` | boolean | no | true | - | internal | rls | True when current employer. Default true. |
| 7 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was created (UTC). Set by trigger and never changed. |
| 8 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was last changed (UTC). Set by trigger. |
| 9 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 10 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `profile.candidate_activity_log`

What a candidate did and when (login, profile update, resume download). Append-only. Distinct from audit.audit_event, which records sensitive actions by anyone.

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | rls | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `user_account_id` | bigint | no | - | FK to core.user_account | internal | rls | Reference to core.user_account (user account). Required. |
| 3 | `candidate_profile_id` | bigint | yes | - | FK to profile.candidate_profile | internal | rls | Nullable: login and password change happen before or without a profile. |
| 4 | `activity_type` | character varying(30) | no | - | - | internal | rls | One of: login, logout, profile_update, resume_upload, resume_download, password_change, consent_change. |
| 5 | `detail_json` | jsonb | yes | - | - | personal | rls | Nullable: only some activities carry detail (for example which document was downloaded). |
| 6 | `client_ip` | character varying(45) | yes | - | - | personal | rls | Nullable: not available for system-initiated events. Personal data. |
| 7 | `occurred_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | Instant (UTC) at which this row's occurred happened. |

## `profile.candidate_assessment`

Catalogue of platform and third-party standardized skill assessments

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `title` | character varying(150) | no | - | UQ | internal | grants_only | Name of the test. |
| 3 | `assessment_provider` | character varying(50) | no | 'talentra'::character varying | - | internal | grants_only | Company that runs the test. |
| 4 | `skill_id` | bigint | yes | - | FK to master.skill | internal | grants_only | Reference to master.skill (skill). NULL when there is none. |
| 5 | `total_questions` | integer | no | 20 | - | internal | grants_only | Number of questions. |
| 6 | `duration_minutes` | integer | no | 30 | - | internal | grants_only | Time allowed, in minutes. |
| 7 | `passing_percentage` | numeric(5,2) | no | 60.00 | - | internal | grants_only | Percentage from 0 to 100. |
| 8 | `is_active` | boolean | no | true | - | internal | grants_only | True when active. Default true. |
| 9 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 10 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 11 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 12 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `profile.candidate_assessment_score`

Candidate performance and verified scores on standardized assessments

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | rls | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `candidate_profile_id` | bigint | no | - | FK to profile.candidate_profile | internal | rls | Reference to profile.candidate_profile (candidate profile). Required. |
| 3 | `candidate_assessment_id` | bigint | no | - | FK to profile.candidate_assessment | internal | rls | Reference to profile.candidate_assessment (candidate assessment). Required. |
| 4 | `score_obtained` | numeric(5,2) | no | - | - | personal | rls | Points the candidate scored, 0 to max_score. |
| 5 | `max_score` | numeric(5,2) | no | - | - | personal | rls | Points available. |
| 6 | `percentile` | numeric(5,2) | yes | - | - | personal | rls | Rank among all takers, 0 to 100. NULL until the provider reports it. |
| 7 | `is_passed` | boolean | no | false | - | personal | rls | True when passed. Default false. |
| 8 | `attempted_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | personal | rls | Instant (UTC) at which this row's attempted happened. |
| 9 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was created (UTC). Set by trigger and never changed. |
| 10 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was last changed (UTC). Set by trigger. |
| 11 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 12 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `profile.candidate_document`

Candidate document metadata; binary content is stored in object storage

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | rls | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `candidate_profile_id` | bigint | no | - | FK to profile.candidate_profile | internal | rls | Reference to profile.candidate_profile (candidate profile). Required. |
| 3 | `document_type` | character varying(30) | no | 'resume'::character varying | - | internal | rls | One of: resume, cover_letter, certificate, portfolio, other. |
| 4 | `document_status` | character varying(20) | no | 'uploaded'::character varying | - | internal | rls | Lifecycle state; ready should only be set after file validation and security scanning |
| 5 | `original_filename` | character varying(255) | no | - | - | personal | rls | File name as uploaded, 1 to 255 characters, never '.' or '..' and without a slash or backslash. Personal data. |
| 6 | `storage_provider` | character varying(30) | no | - | - | internal | rls | One of: gcs, s3, azure_blob, minio. |
| 7 | `storage_key` | character varying(1024) | no | - | - | personal | rls | Private object-storage key, not a public URL or a signed download URL |
| 8 | `mime_type` | character varying(100) | no | - | - | internal | rls | One of: application/pdf, application/msword, application/vnd.openxmlformats-officedocument.wordprocessingml.document, text/plain, image/jpeg |
| 9 | `file_size_bytes` | bigint | no | - | - | internal | rls | Size in bytes. |
| 10 | `checksum_sha256` | character(64) | yes | - | - | internal | rls | Optional SHA-256 checksum for integrity verification |
| 11 | `is_primary` | boolean | no | false | - | internal | rls | True when primary. Default false. |
| 12 | `uploaded_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | personal | rls | Instant (UTC) at which this row's uploaded happened. |
| 13 | `processed_at` | timestamp with time zone | yes | - | - | internal | rls | Nullable: NULL until the event this timestamp records has happened. |
| 14 | `archived_at` | timestamp with time zone | yes | - | - | internal | rls | Nullable: NULL until the event this timestamp records has happened. |
| 15 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was created (UTC). Set by trigger and never changed. |
| 16 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was last changed (UTC). Set by trigger. |
| 17 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 18 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 19 | `deleted_at` | timestamp with time zone | yes | - | - | internal | rls | Nullable: NULL means the row is live. Set when the row is soft-deleted; default queries use the active_ view. |
| 20 | `deleted_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: NULL while the row is live, and when the deletion was done by a system job (retention). |
| 21 | `resume_template_id` | bigint | yes | - | FK to profile.resume_template | internal | rls | Nullable: set only for resumes built from a template; uploaded files have none. Version history of resumes is the set of resume rows by uplo |

## `profile.candidate_education`

Candidate education history; institution and grade details are personal data

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | rls | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `candidate_profile_id` | bigint | no | - | FK to profile.candidate_profile | internal | rls | Reference to profile.candidate_profile (candidate profile). Required. |
| 3 | `qualification_id` | bigint | no | - | FK to master.qualification | internal | rls | Reference to master.qualification (qualification). Required. |
| 4 | `institution_name` | character varying(200) | no | - | - | personal | rls | School, college or university. |
| 5 | `field_of_study` | character varying(150) | yes | - | - | personal | rls | Subject studied. NULL when not stated. |
| 6 | `start_date` | date | yes | - | - | personal | rls | Date the course started. NULL when the candidate gave only the year of completion. |
| 7 | `end_date` | date | yes | - | - | personal | rls | Date the course ended. NULL while the candidate is still studying, or when not stated. |
| 8 | `grade_value` | character varying(30) | yes | - | - | personal | rls | Grade achieved as written (for example 8.4 or First Class). NULL when not stated. |
| 9 | `grade_scale` | character varying(30) | yes | - | - | personal | rls | What grade_value is out of (for example 10 CGPA). NULL when not stated. |
| 10 | `description` | text | yes | - | - | personal | rls | Extra detail the candidate added. NULL when none. |
| 11 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was created (UTC). Set by trigger and never changed. |
| 12 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was last changed (UTC). Set by trigger. |
| 13 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 14 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `profile.candidate_language`

Languages spoken/written by candidates with proficiency ratings

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | rls | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `candidate_profile_id` | bigint | no | - | FK to profile.candidate_profile | internal | rls | Reference to profile.candidate_profile (candidate profile). Required. |
| 3 | `language_id` | bigint | no | - | FK to master.language | internal | rls | Reference to master.language (language). Required. |
| 4 | `proficiency_level` | character varying(20) | no | 'conversational'::character varying | - | personal | rls | One of: basic, conversational, professional, fluent, native. |
| 5 | `can_read` | boolean | no | true | - | personal | rls | True when read. Default true. |
| 6 | `can_write` | boolean | no | true | - | personal | rls | True when write. Default true. |
| 7 | `can_speak` | boolean | no | true | - | personal | rls | True when speak. Default true. |
| 8 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was created (UTC). Set by trigger and never changed. |
| 9 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was last changed (UTC). Set by trigger. |
| 10 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 11 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `profile.candidate_location`

Candidate current location and preferred work locations

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | rls | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `candidate_profile_id` | bigint | no | - | FK to profile.candidate_profile | internal | rls | Reference to profile.candidate_profile (candidate profile). Required. |
| 3 | `city_id` | bigint | no | - | FK to master.city | internal | rls | Reference to master.city (city). Required. |
| 4 | `location_type` | character varying(20) | no | - | - | personal | rls | One of: current, preferred. |
| 5 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was created (UTC). Set by trigger and never changed. |
| 6 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was last changed (UTC). Set by trigger. |
| 7 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 8 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `profile.candidate_profile`

Candidate-specific professional profile linked to a shared user account

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | rls | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `user_account_id` | bigint | no | - | FK to core.user_account, UQ | internal | rls | Reference to core.user_account (user account). Required. |
| 3 | `headline` | character varying(150) | yes | - | - | personal | rls | One-line headline shown in search results. NULL until the candidate writes one. |
| 4 | `professional_summary` | text | yes | - | - | personal | rls | Candidate-provided professional summary; treat as personal data. NULL until the candidate writes one. |
| 5 | `total_experience_years` | numeric(4,1) | no | 0 | - | personal | rls | Number of years (decimals allowed). |
| 6 | `profile_status` | character varying(20) | no | 'draft'::character varying | - | internal | rls | One of: draft, active, paused. |
| 7 | `visibility` | character varying(20) | no | 'recruiters'::character varying | - | personal | rls | One of: private, recruiters, public. |
| 8 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was created (UTC). Set by trigger and never changed. |
| 9 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was last changed (UTC). Set by trigger. |
| 10 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 11 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 12 | `deleted_at` | timestamp with time zone | yes | - | - | internal | rls | Nullable: NULL means the row is live. Set when the row is soft-deleted; default queries use the active_ view. |
| 13 | `deleted_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: NULL while the row is live, and when the deletion was done by a system job (retention). |
| 14 | `summary_language_code` | character varying(10) | yes | - | FK to master.language | internal | rls | Nullable: language the professional summary was written in, when known. |

## `profile.candidate_profile_completion`

Computed profile completeness scores encouraging candidate profile richness

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | rls | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `candidate_profile_id` | bigint | no | - | FK to profile.candidate_profile, UQ | internal | rls | Reference to profile.candidate_profile (candidate profile). Required. |
| 3 | `total_score_percentage` | numeric(5,2) | no | 0.00 | - | internal | rls | Percentage from 0 to 100. |
| 4 | `has_headline` | boolean | no | false | - | internal | rls | True when headline. Default false. |
| 5 | `has_summary` | boolean | no | false | - | internal | rls | True when summary. Default false. |
| 6 | `has_skills` | boolean | no | false | - | internal | rls | True when skills. Default false. |
| 7 | `has_education` | boolean | no | false | - | internal | rls | True when education. Default false. |
| 8 | `has_experience` | boolean | no | false | - | internal | rls | True when experience. Default false. |
| 9 | `has_resume` | boolean | no | false | - | internal | rls | True when resume. Default false. |
| 10 | `has_projects` | boolean | no | false | - | internal | rls | True when projects. Default false. |
| 11 | `last_calculated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | Instant (UTC) at which this row's last calculated happened. |
| 12 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was created (UTC). Set by trigger and never changed. |
| 13 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was last changed (UTC). Set by trigger. |
| 14 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 15 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `profile.candidate_project`

Candidate professional and gig projects, detailing their role, duration, and outcome

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | rls | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `candidate_profile_id` | bigint | no | - | FK to profile.candidate_profile | internal | rls | Reference to profile.candidate_profile (candidate profile). Required. |
| 3 | `title` | character varying(200) | no | - | - | personal | rls | Project name. |
| 4 | `candidate_role` | character varying(150) | no | - | - | personal | rls | The candidate's role in the project. |
| 5 | `project_type` | character varying(20) | no | 'personal'::character varying | - | personal | rls | One of: personal, academic, professional, open_source, gig. |
| 6 | `start_date` | date | yes | - | - | personal | rls | Date the project started. NULL when the candidate gave no dates. |
| 7 | `end_date` | date | yes | - | - | personal | rls | Date the project ended. NULL while it is ongoing, or when no dates were given. |
| 8 | `is_ongoing` | boolean | no | false | - | personal | rls | True when ongoing. Default false. |
| 9 | `project_url` | character varying(2048) | yes | - | - | personal | rls | Absolute URL of the project (repository, demo, publication). NULL when none is public. |
| 10 | `description` | text | yes | - | - | personal | rls | What the project was. NULL when not described. |
| 11 | `outcome` | text | yes | - | - | personal | rls | What it achieved. NULL when not stated. |
| 12 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was created (UTC). Set by trigger and never changed. |
| 13 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was last changed (UTC). Set by trigger. |
| 14 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 15 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `profile.candidate_search_history`

A candidate's job searches, for "recent searches" and alert suggestions. Hard-deleted on request or after retention.

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | rls | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `candidate_profile_id` | bigint | no | - | FK to profile.candidate_profile | internal | rls | Reference to profile.candidate_profile (candidate profile). Required. |
| 3 | `query_text` | character varying(500) | yes | - | - | personal | rls | Nullable: a search can be filters only. |
| 4 | `filters_json` | jsonb | yes | - | - | personal | rls | Nullable: a search can be text only. |
| 5 | `result_count` | integer | no | - | - | internal | rls | Number of result. |
| 6 | `searched_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | Instant (UTC) at which this row's searched happened. |
| 7 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was created (UTC). Set by trigger and never changed. |
| 8 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was last changed (UTC). Set by trigger. |
| 9 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 10 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `profile.candidate_skill`

Candidate skill claims linked to canonical master skills

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | rls | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `candidate_profile_id` | bigint | no | - | FK to profile.candidate_profile | internal | rls | Reference to profile.candidate_profile (candidate profile). Required. |
| 3 | `skill_id` | bigint | no | - | FK to master.skill | internal | rls | Reference to master.skill (skill). Required. |
| 4 | `proficiency_level` | character varying(20) | yes | - | - | personal | rls | Self-assessed level: beginner, intermediate, advanced or expert. NULL when the candidate listed the skill without rating it. |
| 5 | `experience_years` | numeric(4,1) | yes | - | - | personal | rls | Years of experience with the skill, decimals allowed. NULL when the candidate did not say. |
| 6 | `is_primary` | boolean | no | false | - | personal | rls | True when primary. Default false. |
| 7 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was created (UTC). Set by trigger and never changed. |
| 8 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was last changed (UTC). Set by trigger. |
| 9 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 10 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `profile.candidate_work_experience`

Candidate employment history; employer and career details are personal data

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | rls | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `candidate_profile_id` | bigint | no | - | FK to profile.candidate_profile | internal | rls | Reference to profile.candidate_profile (candidate profile). Required. |
| 3 | `job_role_id` | bigint | yes | - | FK to master.job_role | internal | rls | Reference to master.job_role (job role). NULL when there is none. |
| 4 | `employer_name` | character varying(200) | no | - | - | personal | rls | Employer as the candidate wrote it; not linked to an organisation. |
| 5 | `job_title` | character varying(150) | no | - | - | personal | rls | Title held. |
| 6 | `employment_type_id` | bigint | yes | - | FK to master.employment_type | internal | rls | Reference to master.employment_type (employment type). NULL when there is none. |
| 7 | `start_date` | date | no | - | - | personal | rls | Calendar date of start. |
| 8 | `end_date` | date | yes | - | - | personal | rls | Last day in the job. NULL while the candidate still works there (is_current is true). |
| 9 | `is_current` | boolean | no | false | - | personal | rls | True when current. Default false. |
| 10 | `description` | text | yes | - | - | personal | rls | Responsibilities and achievements. NULL when not described. |
| 11 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was created (UTC). Set by trigger and never changed. |
| 12 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was last changed (UTC). Set by trigger. |
| 13 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 14 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `profile.course`

Course catalogue candidates can enrol in. Content lives with the provider; only the reference is stored.

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `code` | character varying(40) | no | - | UQ | internal | grants_only | Stable machine-readable code (lower case), unique within the table. |
| 3 | `title` | character varying(200) | no | - | - | internal | grants_only | Course title. |
| 4 | `provider_name` | character varying(200) | yes | - | - | internal | grants_only | Nullable: in-house courses have no external provider. |
| 5 | `duration_hours` | numeric(6,1) | yes | - | - | internal | grants_only | Nullable: self-paced courses have no fixed duration. NULL means unknown, not zero. |
| 6 | `language_code` | character varying(10) | yes | - | - | internal | grants_only | Nullable: language of instruction when known. |
| 7 | `is_active` | boolean | no | true | - | internal | grants_only | True when active. Default true. |
| 8 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 9 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 10 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 11 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `profile.course_enrolment`

A candidate's enrolment in a course, with outcome.

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | rls | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `candidate_profile_id` | bigint | no | - | FK to profile.candidate_profile | internal | rls | Reference to profile.candidate_profile (candidate profile). Required. |
| 3 | `course_id` | bigint | no | - | FK to profile.course | internal | rls | Reference to profile.course (course). Required. |
| 4 | `enrolment_status` | character varying(20) | no | 'enrolled'::character varying | - | personal | rls | One of: enrolled, in_progress, completed, dropped. |
| 5 | `enrolled_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | personal | rls | Instant (UTC) at which this row's enrolled happened. |
| 6 | `completed_at` | timestamp with time zone | yes | - | - | personal | rls | Set if and only if the status is completed. NULL until the course is completed. |
| 7 | `score_percent` | numeric(5,2) | yes | - | - | personal | rls | Nullable: not every course is scored. NULL is not zero. |
| 8 | `certificate_reference` | character varying(200) | yes | - | - | personal | rls | Nullable: reference at the provider; never the certificate itself. |
| 9 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was created (UTC). Set by trigger and never changed. |
| 10 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was last changed (UTC). Set by trigger. |
| 11 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 12 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `profile.profile_view_history`

Append-only record of recruiters viewing candidate profiles, tracking actor, timestamp, and credit deduction

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | rls | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `candidate_profile_id` | bigint | no | - | FK to profile.candidate_profile | internal | rls | Reference to profile.candidate_profile (candidate profile). Required. |
| 3 | `viewer_user_account_id` | bigint | no | - | FK to core.user_account | internal | rls | Reference to core.user_account (viewer user account). Required. |
| 4 | `organization_id` | bigint | yes | - | FK to recruitment.organization | internal | rls | Reference to recruitment.organization (organization). NULL when there is none. |
| 5 | `view_source` | character varying(30) | no | 'search'::character varying | - | internal | rls | One of: search, direct_link, sourcing, applicant_review. |
| 6 | `credit_deducted` | numeric(14,2) | no | 0.00 | - | internal | rls | Credit charged for the view, in the organisation's wallet currency. 0 when viewing was free. |
| 7 | `viewed_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | personal | rls | Instant (UTC) at which this row's viewed happened. |

## `profile.recruiter_bookmark`

Employer and recruiter candidate shortlists and bookmarks

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | rls | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `organization_id` | bigint | no | - | FK to recruitment.organization | internal | rls | Reference to recruitment.organization (organization). Required. |
| 3 | `user_account_id` | bigint | no | - | FK to core.user_account | internal | rls | Reference to core.user_account (user account). Required. |
| 4 | `candidate_profile_id` | bigint | no | - | FK to profile.candidate_profile | internal | rls | Reference to profile.candidate_profile (candidate profile). Required. |
| 5 | `notes` | text | yes | - | - | personal | rls | The recruiter's private note about the candidate. NULL when none. |
| 6 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was created (UTC). Set by trigger and never changed. |
| 7 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was last changed (UTC). Set by trigger. |
| 8 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 9 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `profile.resume_template`

Layouts a candidate can build a resume from. Display names per UI language live in messaging.ui_translation under key resume_template.<code>.

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `code` | character varying(40) | no | - | UQ | internal | grants_only | Stable machine-readable code (lower case), unique within the table. |
| 3 | `name` | character varying(100) | no | - | - | internal | grants_only | Template name shown in the resume builder. |
| 4 | `description` | character varying(500) | yes | - | - | internal | grants_only | Nullable: optional help text. |
| 5 | `is_active` | boolean | no | true | - | internal | grants_only | True when active. Default true. |
| 6 | `sort_order` | integer | no | 0 | - | internal | grants_only | Position when listed; lower comes first. |
| 7 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 8 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 9 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 10 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `recruitment.application_question_response`

Candidate answers provided to screening questions at application time

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `candidate_application_id` | bigint | no | - | FK to recruitment.candidate_application | internal | grants_only | Reference to recruitment.candidate_application (candidate application). Required. |
| 3 | `job_questionnaire_question_id` | bigint | no | - | FK to recruitment.job_questionnaire_question | internal | grants_only | Reference to recruitment.job_questionnaire_question (job questionnaire question). Required. |
| 4 | `response_text` | text | yes | - | - | personal | grants_only | Answer to a text question. NULL for other question types. |
| 5 | `selected_options_json` | jsonb | yes | - | - | personal | grants_only | JSON array of the choices the applicant ticked. NULL for questions that are not multiple choice. |
| 6 | `numeric_response` | numeric(14,2) | yes | - | - | personal | grants_only | Answer to a numeric question. NULL for other question types. |
| 7 | `boolean_response` | boolean | yes | - | - | personal | grants_only | Answer to a yes/no question. NULL for other types, and for a yes/no question not yet answered. |
| 8 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 9 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 10 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 11 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `recruitment.application_status_history`

Append-only record of application status transitions, including the initial status.

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `candidate_application_id` | bigint | no | - | FK to recruitment.candidate_application | internal | grants_only | Reference to recruitment.candidate_application (candidate application). Required. |
| 3 | `previous_status` | character varying(20) | yes | - | - | internal | grants_only | Stage the application left. NULL on the first history row, written when the application is created. |
| 4 | `new_status` | character varying(20) | no | - | - | internal | grants_only | One of: applied, shortlisted, interviewed, offered, joined, rejected, withdrawn. |
| 5 | `changed_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: NULL until the action named by the column has been taken, or when a system job took it. |
| 6 | `change_reason` | character varying(1000) | yes | - | - | personal | grants_only | Why the stage changed, in the recruiter's words. NULL when none was given. |
| 7 | `changed_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | Instant (UTC) at which this row's changed happened. |

## `recruitment.candidate_application`

A candidate application to a job posting; one application per candidate and job.

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | rls | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `candidate_profile_id` | bigint | no | - | FK to profile.candidate_profile | internal | rls | Reference to profile.candidate_profile (candidate profile). Required. |
| 3 | `job_posting_id` | bigint | no | - | FK to recruitment.job_posting | internal | rls | Reference to recruitment.job_posting (job posting). Required. |
| 4 | `candidate_document_id` | bigint | yes | - | FK to profile.candidate_document | internal | rls | Optional resume/document snapshot reference supplied with the application. |
| 5 | `application_status` | character varying(20) | no | 'applied'::character varying | - | internal | rls | One of: applied, shortlisted, interviewed, offered, joined, rejected, withdrawn. |
| 6 | `cover_letter` | text | yes | - | - | personal | rls | Text the candidate sent with the application. NULL when none. Personal data. |
| 7 | `application_source` | character varying(30) | no | 'direct'::character varying | - | internal | rls | One of: direct, job_alert, referral, campus, other. |
| 8 | `applied_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | Instant (UTC) at which this row's applied happened. |
| 9 | `last_status_changed_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | Instant (UTC) at which this row's last status changed happened. |
| 10 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was created (UTC). Set by trigger and never changed. |
| 11 | `created_by_user_account_id` | bigint | no | - | FK to core.user_account | internal | rls | Account that created the row, taken from the session. NULL when the system created it (seed, migration, scheduled job). |
| 12 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was last changed (UTC). Set by trigger. |
| 13 | `updated_by_user_account_id` | bigint | no | - | FK to core.user_account | internal | rls | Account that last changed the row, taken from the session. NULL when the system changed it. |

## `recruitment.candidate_application_partitioned`

Range-partitioned candidate application table designed for high throughput at 100M application scale

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `candidate_profile_id` | bigint | no | - | - | internal | grants_only | Reference to profile.candidate_profile (candidate profile). Required. |
| 3 | `job_posting_id` | bigint | no | - | - | internal | grants_only | Reference to recruitment.job_posting (job posting). Required. |
| 4 | `candidate_document_id` | bigint | yes | - | - | internal | grants_only | Document (profile.candidate_document) the candidate attached as their resume. NULL when the application was made with the profile alone. |
| 5 | `application_status` | character varying(20) | no | 'applied'::character varying | - | internal | grants_only | One of: applied, shortlisted, interviewed, offered, joined, rejected, withdrawn. |
| 6 | `cover_letter` | text | yes | - | - | personal | grants_only | Text the candidate sent with the application. NULL when none. Personal data. |
| 7 | `application_source` | character varying(30) | no | 'direct'::character varying | - | internal | grants_only | One of: direct, job_alert, referral, campus, other. |
| 8 | `applied_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | PK | internal | grants_only | Instant (UTC) at which this row's applied happened. |
| 9 | `last_status_changed_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | Instant (UTC) at which this row's last status changed happened. |
| 10 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 11 | `created_by_user_account_id` | bigint | no | - | - | internal | grants_only | Account that created the row, taken from the session. NULL when the system created it (seed, migration, scheduled job). |
| 12 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 13 | `updated_by_user_account_id` | bigint | no | - | - | internal | grants_only | Account that last changed the row, taken from the session. NULL when the system changed it. |

## `recruitment.company_review_summary`

Aggregated third-party figures about a company, kept with their source and refresh date (boundary company_reviews). Individual reviews are never stored.

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `organization_id` | bigint | no | - | FK to recruitment.organization | internal | grants_only | Reference to recruitment.organization (the company the figures describe). Required. |
| 3 | `source` | character varying(100) | no | - | - | internal | grants_only | Name of the data provider the figures came from; shown with the figures. |
| 4 | `rating_average` | numeric(3,2) | yes | - | - | internal | grants_only | Provider's average rating from 0.00 to 5.00. NULL when the provider gave none. |
| 5 | `review_count` | integer | no | 0 | - | internal | grants_only | Number of reviews behind the rating; zero when unknown. |
| 6 | `salary_median` | numeric(14,2) | yes | - | - | internal | grants_only | Provider's median salary in currency_code. NULL when the provider gave none. |
| 7 | `currency_code` | character(3) | yes | - | - | internal | grants_only | ISO 4217 currency of salary_median. NULL exactly when salary_median is NULL. |
| 8 | `source_url` | character varying(500) | yes | - | - | internal | grants_only | Absolute URL of the provider's page for this company. NULL when the provider gave none. |
| 9 | `refreshed_at` | timestamp with time zone | no | - | - | internal | grants_only | When the figures were last fetched (UTC); the interface labels a figure stale when this is old. |
| 10 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 11 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 12 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Account that created the row, taken from the session. NULL when the system created it (seed, migration, scheduled job). |
| 13 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Account that last changed the row, taken from the session. NULL when the system changed it. |

## `recruitment.job_position`

Granular position seats under a job requirement tracking individual openings to fulfillment

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `job_posting_id` | bigint | no | - | FK to recruitment.job_posting | internal | grants_only | Reference to recruitment.job_posting (job posting). Required. |
| 3 | `position_reference_code` | character varying(50) | no | - | - | internal | grants_only | The employer's code for this vacancy slot, unique within the job. |
| 4 | `position_status` | character varying(20) | no | 'open'::character varying | - | internal | grants_only | One of: open, offered, filled, cancelled. |
| 5 | `filled_by_candidate_profile_id` | bigint | yes | - | FK to profile.candidate_profile | internal | grants_only | Reference to profile.candidate_profile (filled by candidate profile). NULL when there is none. |
| 6 | `filled_at` | timestamp with time zone | yes | - | - | internal | grants_only | Nullable: NULL until the event this timestamp records has happened. |
| 7 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 8 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 9 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 10 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `recruitment.job_posting`

Organization-owned job advertisements and their hiring requirements

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | rls | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `organization_id` | bigint | no | - | FK to recruitment.organization | internal | rls | Reference to recruitment.organization (organization). Required. |
| 3 | `created_by_user_account_id` | bigint | no | - | FK to core.user_account | internal | rls | Account that created the row, taken from the session. NULL when the system created it (seed, migration, scheduled job). |
| 4 | `job_role_id` | bigint | yes | - | FK to master.job_role | internal | rls | Reference to master.job_role (job role). NULL when there is none. |
| 5 | `industry_id` | bigint | yes | - | FK to master.industry | internal | rls | Reference to master.industry (industry). NULL when there is none. |
| 6 | `employment_type_id` | bigint | no | - | FK to master.employment_type | internal | rls | Reference to master.employment_type (employment type). Required. |
| 7 | `work_type_id` | bigint | no | - | FK to master.work_type | internal | rls | Reference to master.work_type (work type). Required. |
| 8 | `city_id` | bigint | yes | - | FK to master.city | internal | rls | Reference to master.city (city). NULL when there is none. |
| 9 | `title` | character varying(200) | no | - | - | public | rls | Job title. |
| 10 | `description` | text | no | - | - | public | rls | Full description, in the language named by description_language_code. |
| 11 | `responsibilities` | text | yes | - | - | public | rls | Duties. NULL when covered by the description. |
| 12 | `qualifications` | text | yes | - | - | public | rls | Required background. NULL when covered by the description. |
| 13 | `job_status` | character varying(20) | no | 'draft'::character varying | - | internal | rls | One of: closed, filled, cancelled. |
| 14 | `workplace_location_text` | character varying(200) | yes | - | - | internal | rls | Free-text place, used when no city is chosen. NULL when city_id says it. |
| 15 | `currency_code` | character(3) | yes | - | - | internal | rls | ISO 4217 currency of salary_min and salary_max. NULL exactly when the job discloses no salary (a CHECK keeps salary, currency and period tog |
| 16 | `salary_min` | numeric(14,2) | yes | - | - | internal | rls | Lower compensation bound; requires currency and salary period when supplied. NULL when the job discloses no salary. |
| 17 | `salary_max` | numeric(14,2) | yes | - | - | internal | rls | Upper compensation bound; requires currency and salary period when supplied. NULL when the job discloses no salary. |
| 18 | `salary_period` | character varying(20) | yes | - | - | internal | rls | Period the salary covers: hour, day, week, month or year. NULL exactly when the job discloses no salary. |
| 19 | `minimum_experience_years` | numeric(4,1) | yes | - | - | internal | rls | Least experience, in years, the employer asks for. NULL when no minimum is stated. |
| 20 | `maximum_experience_years` | numeric(4,1) | yes | - | - | internal | rls | Most experience, in years, the employer will consider. NULL when there is no ceiling. |
| 21 | `vacancy_count` | integer | no | 1 | - | internal | rls | Number of vacancy. |
| 22 | `published_at` | timestamp with time zone | yes | - | - | public | rls | Nullable: NULL until the event this timestamp records has happened. |
| 23 | `application_deadline` | timestamp with time zone | yes | - | - | internal | rls | Last moment applications are accepted. NULL for no deadline. |
| 24 | `closed_at` | timestamp with time zone | yes | - | - | internal | rls | Nullable: NULL until the event this timestamp records has happened. |
| 25 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was created (UTC). Set by trigger and never changed. |
| 26 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was last changed (UTC). Set by trigger. |
| 27 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 28 | `deleted_at` | timestamp with time zone | yes | - | - | internal | rls | Nullable: NULL means the row is live. Set when the row is soft-deleted; default queries use the active_ view. |
| 29 | `deleted_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: NULL while the row is live, and when the deletion was done by a system job (retention). |
| 30 | `description_language_code` | character varying(10) | yes | - | FK to master.language | internal | rls | Nullable: language the description was written in, when known. The text is stored once, as entered. |

## `recruitment.job_questionnaire`

Screening questionnaire configured by employers for job applications

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `job_posting_id` | bigint | no | - | FK to recruitment.job_posting, UQ | internal | grants_only | Reference to recruitment.job_posting (job posting). Required. |
| 3 | `created_by_user_account_id` | bigint | no | - | FK to core.user_account | internal | grants_only | Account that created the row, taken from the session. NULL when the system created it (seed, migration, scheduled job). |
| 4 | `title` | character varying(200) | no | - | - | internal | grants_only | Name of the screening questionnaire. |
| 5 | `instructions` | text | yes | - | - | internal | grants_only | Text shown above the questions. NULL when none. |
| 6 | `is_mandatory` | boolean | no | true | - | internal | grants_only | True when mandatory. Default true. |
| 7 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 8 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 9 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `recruitment.job_questionnaire_question`

Individual questions within an application screening questionnaire

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `job_questionnaire_id` | bigint | no | - | FK to recruitment.job_questionnaire | internal | grants_only | Reference to recruitment.job_questionnaire (job questionnaire). Required. |
| 3 | `question_text` | text | no | - | - | internal | grants_only | The question as shown to the applicant. |
| 4 | `question_type` | character varying(30) | no | 'text'::character varying | - | internal | grants_only | One of: text, single_choice, multiple_choice, boolean, numeric. |
| 5 | `options_json` | jsonb | yes | - | - | internal | grants_only | JSON array of the choices for a multiple-choice question. NULL for free-text, numeric and yes/no questions. |
| 6 | `is_required` | boolean | no | true | - | internal | grants_only | True when required. Default true. |
| 7 | `sort_order` | integer | no | 1 | - | internal | grants_only | Position when listed; lower comes first. |
| 8 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 9 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 10 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 11 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `recruitment.job_skill_requirement`

Normalized required and optional skills associated with a job posting

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `job_posting_id` | bigint | no | - | FK to recruitment.job_posting | internal | grants_only | Reference to recruitment.job_posting (job posting). Required. |
| 3 | `skill_id` | bigint | no | - | FK to master.skill | internal | grants_only | Reference to master.skill (skill). Required. |
| 4 | `is_required` | boolean | no | true | - | internal | grants_only | True when required. Default true. |
| 5 | `minimum_proficiency_level` | character varying(20) | yes | - | - | internal | grants_only | Lowest acceptable level for the skill: beginner, intermediate, advanced or expert. NULL when any level will do. |
| 6 | `minimum_experience_years` | numeric(4,1) | yes | - | - | internal | grants_only | Least years of experience with the skill. NULL when the job sets none. |
| 7 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 8 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 9 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 10 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `recruitment.organization`

Employer and recruitment organizations using the Talentra platform

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `name` | character varying(200) | no | - | - | public | grants_only | Legal or trading name. |
| 3 | `slug` | character varying(120) | no | - | UQ | public | grants_only | Globally unique URL-safe organization identifier |
| 4 | `organization_type` | character varying(30) | no | 'employer'::character varying | - | internal | grants_only | One of: employer, recruitment_agency, consultancy, educational_institution, other. |
| 5 | `description` | text | yes | - | - | public | grants_only | About the organisation. NULL when none. |
| 6 | `website_url` | character varying(2048) | yes | - | - | public | grants_only | Absolute URL of the organisation's website. NULL when it has none or has not given it. |
| 7 | `contact_email` | character varying(254) | yes | - | - | personal | grants_only | Public contact address. NULL when none. Personal data in the case of sole traders. |
| 8 | `contact_phone_e164` | character varying(16) | yes | - | - | personal | grants_only | Contact phone in E.164 format. NULL when the organisation gave only an email. |
| 9 | `country_id` | bigint | yes | - | FK to master.country | internal | grants_only | Reference to master.country (country). NULL when there is none. |
| 10 | `organization_status` | character varying(20) | no | 'pending'::character varying | - | internal | grants_only | One of: pending, active, suspended, closed. |
| 11 | `created_by_user_account_id` | bigint | no | - | FK to core.user_account | internal | grants_only | User account that initially created the organization |
| 12 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 13 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 14 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 15 | `deleted_at` | timestamp with time zone | yes | - | - | internal | grants_only | Nullable: NULL means the row is live. Set when the row is soft-deleted; default queries use the active_ view. |
| 16 | `deleted_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: NULL while the row is live, and when the deletion was done by a system job (retention). |

## `recruitment.organization_hierarchy`

Organizational hierarchy linking parent holding corporations, divisions, and client entities

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `parent_organization_id` | bigint | no | - | FK to recruitment.organization | internal | grants_only | Reference to recruitment.organization (parent organization). Required. |
| 3 | `child_organization_id` | bigint | no | - | FK to recruitment.organization | internal | grants_only | Reference to recruitment.organization (child organization). Required. |
| 4 | `relationship_type` | character varying(30) | no | 'subsidiary'::character varying | - | internal | grants_only | One of: subsidiary, branch, client, vendor, franchise. |
| 5 | `is_active` | boolean | no | true | - | internal | grants_only | True when active. Default true. |
| 6 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 7 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 8 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 9 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `recruitment.organization_identifier`

Legal registration and tax identifiers per jurisdiction for employer verification

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `organization_id` | bigint | no | - | FK to recruitment.organization | internal | grants_only | Reference to recruitment.organization (organization). Required. |
| 3 | `country_id` | bigint | no | - | FK to master.country | internal | grants_only | Reference to master.country (country). Required. |
| 4 | `identifier_type` | character varying(30) | no | - | - | internal | grants_only | One of: gstin, cin, ein, vat, pan, company_number, other. |
| 6 | `verification_status` | character varying(20) | no | 'unverified'::character varying | - | internal | grants_only | One of: unverified, pending, verified, rejected. |
| 7 | `verified_at` | timestamp with time zone | yes | - | - | internal | grants_only | Nullable: NULL until the event this timestamp records has happened. |
| 8 | `verified_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: NULL until the action named by the column has been taken, or when a system job took it. |
| 9 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 10 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 11 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 12 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 13 | `identifier_ciphertext` | bytea | no | - | - | sensitive | encrypted | AES-256-GCM output: 12-byte random nonce, ciphertext, 16-byte tag. Sensitive. The key is never in the database. Bound by AAD to organization |
| 14 | `identifier_bidx` | bytea | no | - | - | sensitive | encrypted | HMAC-SHA-256 (32 bytes) of the canonical identifier under a key separate from the encryption key. Makes the identifier unique and findable b |
| 15 | `identifier_key_version` | smallint | no | 1 | - | internal | grants_only | Version of the key pair that produced the ciphertext and the blind index; lets keys be rotated row by row. Always set. |

## `recruitment.organization_location`

Physical offices and branches for employer and recruitment organizations

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `organization_id` | bigint | no | - | FK to recruitment.organization | internal | grants_only | Reference to recruitment.organization (organization). Required. |
| 3 | `city_id` | bigint | no | - | FK to master.city | internal | grants_only | Reference to master.city (city). Required. |
| 4 | `location_name` | character varying(150) | no | - | - | internal | grants_only | Name of the site, for example Corporate HQ. |
| 5 | `address_line1` | character varying(255) | no | - | - | internal | grants_only | First line of the address. |
| 6 | `address_line2` | character varying(255) | yes | - | - | internal | grants_only | Second line. NULL when there is none. |
| 7 | `postal_code` | character varying(20) | no | - | - | internal | grants_only | Postal or ZIP code as written locally. |
| 8 | `is_headquarters` | boolean | no | false | - | internal | grants_only | True when headquarters. Default false. |
| 9 | `is_active` | boolean | no | true | - | internal | grants_only | True when active. Default true. |
| 10 | `latitude` | numeric(9,6) | yes | - | - | internal | grants_only | Degrees north, six decimals. NULL when not geocoded. |
| 11 | `longitude` | numeric(9,6) | yes | - | - | internal | grants_only | Degrees east, six decimals. NULL when not geocoded. |
| 12 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 13 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 14 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 15 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 16 | `place_reference` | character varying(200) | yes | - | - | internal | grants_only | The mapping service's identifier for the place. NULL until the address has been geocoded, or when the service was unavailable. |
| 17 | `geocoded_at` | timestamp with time zone | yes | - | - | internal | grants_only | When latitude, longitude and place_reference were obtained (UTC). NULL while the location is stored as text only. |

## `recruitment.organization_member`

Organization-specific memberships and roles for shared user accounts

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `organization_id` | bigint | no | - | FK to recruitment.organization | internal | grants_only | Reference to recruitment.organization (organization). Required. |
| 3 | `user_account_id` | bigint | no | - | FK to core.user_account | internal | grants_only | Reference to core.user_account (user account). Required. |
| 4 | `organization_role` | character varying(30) | no | 'recruiter'::character varying | - | internal | grants_only | Organization-scoped role; distinct from platform-wide core.role |
| 5 | `membership_status` | character varying(20) | no | 'invited'::character varying | - | internal | grants_only | One of: invited, active, suspended, removed. |
| 6 | `invited_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: NULL until the action named by the column has been taken, or when a system job took it. |
| 7 | `invited_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | Instant (UTC) at which this row's invited happened. |
| 8 | `joined_at` | timestamp with time zone | yes | - | - | internal | grants_only | Nullable: NULL until the event this timestamp records has happened. |
| 9 | `removed_at` | timestamp with time zone | yes | - | - | internal | grants_only | Nullable: NULL until the event this timestamp records has happened. |
| 10 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 11 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 12 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 13 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `recruitment.recruiter_client_mapping`

Effective-dated mapping specifying which recruiters are authorized to act on behalf of client accounts

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `recruiter_user_account_id` | bigint | no | - | FK to core.user_account | internal | grants_only | Reference to core.user_account (recruiter user account). Required. |
| 3 | `agency_organization_id` | bigint | yes | - | FK to recruitment.organization | internal | grants_only | Reference to recruitment.organization (agency organization). NULL when there is none. |
| 4 | `client_organization_id` | bigint | no | - | FK to recruitment.organization | internal | grants_only | Reference to recruitment.organization (client organization). Required. |
| 5 | `effective_from` | date | no | - | - | internal | grants_only | First day the recruiter acts for the client. |
| 6 | `effective_to` | date | yes | - | - | internal | grants_only | Last day the recruiter acts for the client. NULL while the mapping is open-ended. |
| 7 | `is_active` | boolean | no | true | - | internal | grants_only | True when active. Default true. |
| 8 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 9 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 10 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 11 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `sourcing.consultant_sourcing_request`

Consultant requests to source for a specific job and employer acceptance/decline decisions

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `job_posting_id` | bigint | no | - | FK to recruitment.job_posting | internal | grants_only | Reference to recruitment.job_posting (job posting). Required. |
| 3 | `consultant_user_account_id` | bigint | no | - | FK to core.user_account | internal | grants_only | Reference to core.user_account (consultant user account). Required. |
| 4 | `request_status` | character varying(20) | no | 'requested'::character varying | - | internal | grants_only | One of: accepted, declined, accepted, declined. |
| 5 | `proposal_notes` | text | yes | - | - | personal | grants_only | The consultant's pitch for taking the job. NULL when none. |
| 6 | `decided_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: NULL until the action named by the column has been taken, or when a system job took it. |
| 7 | `decided_at` | timestamp with time zone | yes | - | - | internal | grants_only | Nullable: NULL until the event this timestamp records has happened. |
| 8 | `decision_reason` | character varying(500) | yes | - | - | personal | grants_only | Why the employer accepted or declined. NULL until decided, and when no reason was given. |
| 9 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 10 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 11 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 12 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `sourcing.job_consultant_policy`

Policy configuring whether external recruitment consultants may source candidates for a job requirement

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | grants_only | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `job_posting_id` | bigint | no | - | FK to recruitment.job_posting, UQ | internal | grants_only | Reference to recruitment.job_posting (job posting). Required. |
| 3 | `is_open_to_consultants` | boolean | no | false | - | internal | grants_only | True when open to consultants. Default false. |
| 4 | `max_consultants` | integer | yes | - | - | internal | grants_only | The most consultants who may work the job at once. NULL for no limit. |
| 5 | `bounty_amount` | numeric(14,2) | yes | - | - | internal | grants_only | Fee paid to the consultant for a hire, in currency_code. NULL when unpaid. |
| 6 | `currency_code` | character(3) | yes | 'USD'::bpchar | - | internal | grants_only | ISO 4217 currency of bounty_amount. NULL when no bounty currency is given; it should be set whenever bounty_amount is. |
| 7 | `terms_and_conditions` | text | yes | - | - | internal | grants_only | Commercial terms for consultants. NULL when the standard terms apply. |
| 8 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was created (UTC). Set by trigger and never changed. |
| 9 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | grants_only | When the row was last changed (UTC). Set by trigger. |
| 10 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 11 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | grants_only | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `sourcing.outreach_batch`

Bulk sourcing candidate outreach campaigns initiated by employers or agencies

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | rls | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `organization_id` | bigint | no | - | FK to recruitment.organization | internal | rls | Reference to recruitment.organization (organization). Required. |
| 3 | `created_by_user_account_id` | bigint | no | - | FK to core.user_account | internal | rls | Account that created the row, taken from the session. NULL when the system created it (seed, migration, scheduled job). |
| 4 | `campaign_name` | character varying(150) | no | - | - | internal | rls | Internal name of the campaign. |
| 5 | `job_posting_id` | bigint | yes | - | FK to recruitment.job_posting | internal | rls | Reference to recruitment.job_posting (job posting). NULL when there is none. |
| 6 | `channel` | character varying(20) | no | 'email'::character varying | - | internal | rls | One of: email, sms, in_app, whatsapp. |
| 7 | `subject` | character varying(200) | yes | - | - | personal | rls | Subject line for channels that have one. NULL for SMS and in-app. |
| 8 | `message_body` | text | no | - | - | personal | rls | The message sent. |
| 9 | `total_recipients` | integer | no | 0 | - | internal | rls | Number of recipients in the batch. |
| 10 | `total_credits_deducted` | numeric(14,2) | no | 0.00 | - | internal | rls | Credit charged for the whole batch, in the organisation's wallet currency. |
| 11 | `status` | character varying(20) | no | 'draft'::character varying | - | internal | rls | One of: draft, queued, processing, completed, cancelled. |
| 12 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was created (UTC). Set by trigger and never changed. |
| 13 | `completed_at` | timestamp with time zone | yes | - | - | internal | rls | Nullable: NULL until the event this timestamp records has happened. |
| 14 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was last changed (UTC). Set by trigger. |
| 15 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `sourcing.outreach_recipient`

Target candidate tracking per bulk outreach campaign

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | rls | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `outreach_batch_id` | bigint | no | - | FK to sourcing.outreach_batch | internal | rls | Reference to sourcing.outreach_batch (outreach batch). Required. |
| 3 | `candidate_profile_id` | bigint | no | - | FK to profile.candidate_profile | internal | rls | Reference to profile.candidate_profile (candidate profile). Required. |
| 4 | `delivery_status` | character varying(20) | no | 'pending'::character varying | - | internal | rls | One of: pending, sent, delivered, opened, responded, bounced, blocked. |
| 5 | `sent_at` | timestamp with time zone | yes | - | - | internal | rls | Nullable: NULL until the event this timestamp records has happened. |
| 6 | `delivered_at` | timestamp with time zone | yes | - | - | internal | rls | Nullable: NULL until the event this timestamp records has happened. |
| 7 | `response_recorded_at` | timestamp with time zone | yes | - | - | internal | rls | Nullable: NULL until the event this timestamp records has happened. |
| 8 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was created (UTC). Set by trigger and never changed. |
| 9 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was last changed (UTC). Set by trigger. |
| 10 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 11 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |

## `sourcing.sourcing_submission`

Candidate submissions made by approved freelance recruiters or consultants

| # | Column | Type | Null | Default | Key | Class | Protection | Definition |
|--:|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `id` | bigint | no | - | PK | internal | rls | Surrogate primary key (64-bit identity). Never reused, never shown to users. |
| 2 | `consultant_sourcing_request_id` | bigint | yes | - | FK to sourcing.consultant_sourcing_request | internal | rls | Reference to sourcing.consultant_sourcing_request (consultant sourcing request). NULL when there is none. |
| 3 | `job_posting_id` | bigint | no | - | FK to recruitment.job_posting | internal | rls | Reference to recruitment.job_posting (job posting). Required. |
| 4 | `candidate_profile_id` | bigint | no | - | FK to profile.candidate_profile | internal | rls | Reference to profile.candidate_profile (candidate profile). Required. |
| 5 | `submitted_by_user_account_id` | bigint | no | - | FK to core.user_account | internal | rls | Reference to core.user_account (submitted by user account). Required. |
| 6 | `candidate_application_id` | bigint | yes | - | FK to recruitment.candidate_application | internal | rls | Reference to recruitment.candidate_application (candidate application). NULL when there is none. |
| 7 | `submission_status` | character varying(20) | no | 'submitted'::character varying | - | internal | rls | One of: submitted, shortlisted, accepted, rejected, hired. |
| 8 | `consultant_notes` | text | yes | - | - | personal | rls | The consultant's note about the candidate. NULL when none. |
| 9 | `client_feedback` | text | yes | - | - | personal | rls | The employer's feedback to the consultant. NULL until given. |
| 10 | `created_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was created (UTC). Set by trigger and never changed. |
| 11 | `updated_at` | timestamp with time zone | no | CURRENT_TIMESTAMP | - | internal | rls | When the row was last changed (UTC). Set by trigger. |
| 12 | `created_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
| 13 | `updated_by_user_account_id` | bigint | yes | - | FK to core.user_account | internal | rls | Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user. |
