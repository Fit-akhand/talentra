# Talentra Entity-Relationship (ER) Architecture

> **Partly superseded (2026-10-27).** This diagram was drawn for migrations 001-019. Tables added by 020-027 are not in it. The generated diagrams, one per schema and always current, are in [`09-er-diagram-generated.md`](09-er-diagram-generated.md).
**Database Engine**: PostgreSQL 17  
**Schema Architecture**: 10 Isolated Domain Schemas  
**Notation**: Mermaid Crow's Foot Relational Diagrams  

---

## 1. High-Level Domain Boundary Architecture

```mermaid
erDiagram
    CORE ||--o{ PROFILE : "owns candidate identity"
    CORE ||--o{ RECRUITMENT : "creates organizations and jobs"
    CORE ||--o{ GIG : "operates as gig contractor"
    CORE ||--o{ COMMERCIAL : "holds licences and user sessions"
    CORE ||--o{ MESSAGING : "receives alerts and preferences"
    CORE ||--o{ AUDIT : "logs security events"
    MASTER ||--o{ PROFILE : "classifies skills and education"
    MASTER ||--o{ RECRUITMENT : "standardizes roles and cities"
    MASTER ||--o{ GIG : "standardizes gig services"
    MASTER ||--o{ MESSAGING : "canonical UI languages"
    RECRUITMENT ||--o{ PROFILE : "candidate applications"
    RECRUITMENT ||--o{ GIG : "corporate gig requests"
    COMMERCIAL ||--o{ RECRUITMENT : "wallets and download deductions"
    RECRUITMENT ||--o{ ANALYTICS : "etl application events"
```

---

## 2. Core Identity, Security & RBAC Domain (`core`)

```mermaid
erDiagram
    USER_ACCOUNT {
        bigint id PK
        varchar email UK
        varchar phone_e164
        char phone_country_code
        varchar account_status
        varchar preferred_language
        varchar password_hash
        timestamptz created_at
    }

    ROLE {
        bigint id PK
        varchar code UK
        varchar name
        boolean is_system
    }

    PERMISSION {
        bigint id PK
        varchar permission_key UK
        varchar domain
        varchar action
    }

    ROLE_PERMISSION {
        bigint id PK
        bigint role_id FK
        bigint permission_id FK
    }

    USER_ROLE {
        bigint id PK
        bigint user_account_id FK
        bigint role_id FK
    }

    USER_SESSION {
        bigint id PK
        bigint user_account_id FK
        varchar device_identifier
        varchar session_token_hash UK
        timestamptz started_at
        timestamptz ended_at
        timestamptz revoked_at
    }

    USER_BLOCK {
        bigint id PK
        bigint blocker_user_account_id FK
        bigint blocked_user_account_id FK
        bigint blocked_organization_id FK
        varchar block_reason
    }

    CONSENT_RECORD {
        bigint id PK
        bigint user_account_id FK
        varchar consent_type
        boolean is_granted
        timestamptz granted_at
    }

    USER_ACCOUNT ||--o{ USER_ROLE : "assigned"
    ROLE ||--o{ USER_ROLE : "has"
    ROLE ||--o{ ROLE_PERMISSION : "grants"
    PERMISSION ||--o{ ROLE_PERMISSION : "defines"
    USER_ACCOUNT ||--o{ USER_SESSION : "authorizes"
    USER_ACCOUNT ||--o{ USER_BLOCK : "blocks"
    USER_ACCOUNT ||--o{ CONSENT_RECORD : "records"
```

---

## 3. Candidate Profile & Career Extensions (`profile`)

```mermaid
erDiagram
    CANDIDATE_PROFILE {
        bigint id PK
        bigint user_account_id FK, UK
        varchar headline
        text professional_summary
        numeric total_experience_years
        varchar profile_status
        varchar visibility
    }

    CANDIDATE_SKILL {
        bigint id PK
        bigint candidate_profile_id FK
        bigint skill_id FK
        varchar proficiency_level
        numeric experience_years
        boolean is_primary
    }

    CANDIDATE_LOCATION {
        bigint id PK
        bigint candidate_profile_id FK
        bigint city_id FK
        varchar location_type
    }

    CANDIDATE_WORK_EXPERIENCE {
        bigint id PK
        bigint candidate_profile_id FK
        varchar company_name
        varchar job_title
        date start_date
        date end_date
        boolean is_current
    }

    CANDIDATE_EDUCATION {
        bigint id PK
        bigint candidate_profile_id FK
        bigint qualification_id FK
        varchar institution_name
        varchar field_of_study
        date start_date
        date end_date
    }

    CANDIDATE_DOCUMENT {
        bigint id PK
        bigint candidate_profile_id FK
        varchar document_type
        varchar storage_key
        varchar file_hash_sha256
        varchar parse_status
    }

    CANDIDATE_PROFILE ||--o{ CANDIDATE_SKILL : "declares"
    CANDIDATE_PROFILE ||--o{ CANDIDATE_LOCATION : "resides"
    CANDIDATE_PROFILE ||--o{ CANDIDATE_WORK_EXPERIENCE : "worked_at"
    CANDIDATE_PROFILE ||--o{ CANDIDATE_EDUCATION : "studied_at"
    CANDIDATE_PROFILE ||--o{ CANDIDATE_DOCUMENT : "uploads"
```

---

## 4. Recruitment, Job Postings & Applications (`recruitment`)

```mermaid
erDiagram
    ORGANIZATION {
        bigint id PK
        varchar name
        varchar slug UK
        varchar organization_type
        varchar organization_status
    }

    ORGANIZATION_LOCATION {
        bigint id PK
        bigint organization_id FK
        bigint city_id FK
        varchar location_name
        varchar address_line1
        varchar postal_code
        boolean is_headquarters
    }

    JOB_POSTING {
        bigint id PK
        bigint organization_id FK
        bigint employment_type_id FK
        bigint work_type_id FK
        bigint city_id FK
        varchar title
        varchar job_status
        numeric salary_min
        numeric salary_max
        char currency_code
        timestamptz published_at
    }

    JOB_SKILL_REQUIREMENT {
        bigint id PK
        bigint job_posting_id FK
        bigint skill_id FK
        boolean is_required
        varchar minimum_proficiency_level
        numeric minimum_experience_years
    }

    CANDIDATE_APPLICATION {
        bigint id PK
        bigint candidate_profile_id FK
        bigint job_posting_id FK
        varchar application_status
        varchar application_source
        timestamptz applied_at
        timestamptz last_status_changed_at
    }

    CANDIDATE_APPLICATION_PARTITIONED {
        bigint id PK
        bigint candidate_profile_id FK
        bigint job_posting_id FK
        varchar application_status
        timestamptz applied_at PK
    }

    ORGANIZATION ||--o{ ORGANIZATION_LOCATION : "branches"
    ORGANIZATION ||--o{ JOB_POSTING : "publishes"
    JOB_POSTING ||--o{ JOB_SKILL_REQUIREMENT : "requires"
    JOB_POSTING ||--o{ CANDIDATE_APPLICATION : "receives"
    JOB_POSTING ||--o{ CANDIDATE_APPLICATION_PARTITIONED : "routes_to_partitions"
```

---

## 5. Gig Marketplace Subsystem (`gig`)

```mermaid
erDiagram
    GIG_WORKER_PROFILE {
        bigint id PK
        bigint user_account_id FK, UK
        varchar headline
        numeric hourly_rate
        numeric daily_rate
        char currency_code
        boolean is_available
        numeric average_rating
        varchar verification_status
    }

    GIG_WORKER_SERVICE {
        bigint id PK
        bigint gig_worker_profile_id FK
        bigint skill_id FK
        varchar custom_title
        numeric rate_override
    }

    GIG_WORKER_AVAILABILITY {
        bigint id PK
        bigint gig_worker_profile_id FK
        date available_from
        date available_to
        numeric daily_available_hours
    }

    GIG_REQUEST {
        bigint id PK
        bigint organization_id FK
        varchar title
        varchar pricing_type
        numeric budget_amount
        char currency_code
        date start_date
        date end_date
        varchar request_status
    }

    GIG_APPLICATION {
        bigint id PK
        bigint gig_request_id FK
        bigint gig_worker_profile_id FK
        numeric bid_amount
        varchar application_status
        timestamptz decided_at
    }

    GIG_ASSIGNMENT {
        bigint id PK
        bigint gig_request_id FK
        bigint gig_application_id FK
        bigint gig_worker_profile_id FK
        date assigned_start_date
        date assigned_end_date
        numeric agreed_amount
        varchar assignment_status
        varchar external_handoff_ref
    }

    GIG_EXTERNAL_EARNINGS {
        bigint id PK
        bigint gig_assignment_id FK, UK
        numeric total_earnings
        char currency_code
        timestamptz reconciled_at
    }

    GIG_RATING {
        bigint id PK
        bigint gig_assignment_id FK, UK
        bigint rater_user_account_id FK
        numeric rating_score
        text review_text
    }

    GIG_WORKER_PROFILE ||--o{ GIG_WORKER_SERVICE : "offers"
    GIG_WORKER_PROFILE ||--o{ GIG_WORKER_AVAILABILITY : "declares"
    GIG_REQUEST ||--o{ GIG_APPLICATION : "receives_bids"
    GIG_WORKER_PROFILE ||--o{ GIG_APPLICATION : "submits"
    GIG_APPLICATION ||--|| GIG_ASSIGNMENT : "accepted_into"
    GIG_ASSIGNMENT ||--|| GIG_EXTERNAL_EARNINGS : "reconciles"
    GIG_ASSIGNMENT ||--|| GIG_RATING : "reviewed_by"
```

---

## 6. Commercial Licences, Subscriptions & Append-Only Wallets (`commercial`)

```mermaid
erDiagram
    SUBSCRIPTION_LICENCE {
        bigint id PK
        bigint organization_id FK
        varchar licence_key UK
        varchar licence_name
        integer max_users
        integer max_devices_per_user
        timestamptz valid_from
        timestamptz valid_to
        varchar licence_status
    }

    LICENCE_SEAT_ALLOCATION {
        bigint id PK
        bigint subscription_licence_id FK
        bigint user_account_id FK
        timestamptz allocated_at
        timestamptz revoked_at
    }

    WALLET {
        bigint id PK
        bigint organization_id FK
        numeric balance
        char currency_code
    }

    WALLET_LEDGER {
        bigint id PK
        bigint wallet_id FK
        varchar entry_type
        numeric amount
        char currency_code
        numeric balance_after
        varchar reference_type
        bigint correction_of_ledger_id FK
        varchar notes
        bigint created_by_user_account_id FK
        timestamptz recorded_at
    }

    CANDIDATE_PROFILE_DOWNLOAD_HISTORY {
        bigint id PK
        bigint organization_id FK
        bigint downloader_user_account_id FK
        bigint candidate_profile_id FK
        numeric credit_deduction_amount
        bigint wallet_ledger_id FK
        timestamptz downloaded_at
    }

    SUBSCRIPTION_LICENCE ||--o{ LICENCE_SEAT_ALLOCATION : "allocates_seats"
    WALLET ||--o{ WALLET_LEDGER : "tracks_financial_movements"
    WALLET_LEDGER ||--o{ WALLET_LEDGER : "correction_of"
    WALLET_LEDGER ||--o{ CANDIDATE_PROFILE_DOWNLOAD_HISTORY : "billed_via"
```

---

## 7. Messaging & Multilingual UI Translations (`messaging`)

```mermaid
erDiagram
    UI_TRANSLATION {
        bigint id PK
        varchar string_key
        varchar language_code FK
        text translated_text
        boolean is_verified
    }

    NOTIFICATION_TEMPLATE {
        bigint id PK
        varchar template_code UK
        varchar channel
        varchar default_language_code
        text body_template
        boolean is_active
    }

    NOTIFICATION_DELIVERY {
        bigint id PK
        bigint recipient_user_account_id FK
        bigint notification_template_id FK
        varchar channel
        varchar subject
        varchar body_snippet
        varchar delivery_status
        timestamptz sent_at
        timestamptz read_at
    }

    NOTIFICATION_TEMPLATE ||--o{ NOTIFICATION_DELIVERY : "dispatches"
```

---

## 8. Analytics Star Schema Marts (`analytics`)

```mermaid
erDiagram
    DIM_DATE {
        integer date_key PK
        date calendar_date UK
        integer calendar_year
        smallint calendar_quarter
        smallint calendar_month
        varchar day_name
        boolean is_weekend
    }

    DIM_CANDIDATE {
        bigint candidate_key PK
        bigint candidate_profile_id
        varchar current_city_name
        numeric total_experience_years
        timestamptz valid_from
        timestamptz valid_to
        boolean is_current
    }

    DIM_ORGANIZATION {
        bigint organization_key PK
        bigint organization_id
        varchar organization_name
        varchar industry_name
        timestamptz valid_from
        timestamptz valid_to
        boolean is_current
    }

    DIM_JOB_POSTING {
        bigint job_posting_key PK
        bigint job_posting_id UK
        bigint organization_key FK
        varchar job_title
        varchar industry_name
        varchar work_type_code
    }

    FACT_APPLICATION_EVENT {
        bigint id PK
        integer date_key FK
        bigint job_posting_key FK
        bigint candidate_key FK
        bigint organization_key FK
        bigint candidate_application_id
        varchar previous_status
        varchar new_status
        numeric status_cycle_time_hours
        timestamptz event_timestamp
    }

    DIM_DATE ||--o{ FACT_APPLICATION_EVENT : "calendar_dimension"
    DIM_JOB_POSTING ||--o{ FACT_APPLICATION_EVENT : "job_dimension"
    DIM_CANDIDATE ||--o{ FACT_APPLICATION_EVENT : "candidate_dimension"
    DIM_ORGANIZATION ||--o{ FACT_APPLICATION_EVENT : "organization_dimension"
```
