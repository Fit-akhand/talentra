# Talentra Data Dictionary & Column Classification Dossier
**Database Engine**: PostgreSQL 17  
**Schema Count**: 10 Schemas  
**Table Count**: 95 Operational, Dimensional, and Partitioned Tables  
**Compliance Standards**: Rule Group 5 (Nullability & Zero-Sentinel Discipline), Rule Group 6 (PII Sensitivity Classification)

---

## 1. Sensitivity Classification Standard (Rule Group 6)

Every column in Talentra is tagged with one of four sensitivity classifications:
* **`[PUBLIC]`**: Freely queryable, non-identifying operational or reference data (e.g., job titles, canonical skills, city names).
* **`[INTERNAL]`**: Operational metadata and enterprise business logic (e.g., status logs, cycle times, match scores).
* **`[PERSONAL]`**: Candidate biographical and career history (e.g., candidate name, employment dates, degree, headline).
* **`[SENSITIVE]`**: High-risk identifiers, authentication credentials, and financial values (e.g., password hashes, encrypted tax IDs, phone numbers, email addresses, wallet balances).

---

## 2. Nullability Discipline (Rule Group 5)

* **Mandatory Non-Null**: Primary keys, essential foreign keys, status enumerations, audit creation timestamps, and currency companions are strictly `NOT NULL`.
* **Zero-Sentinel Value Rule**: Missing, optional, or unknown attributes must be stored strictly as SQL `NULL`. No dummy text strings (`'NA'`, `'NONE'`, `'NULL'`, `'UNKNOWN'`, `'?'`) or sentinel numbers (`-1`, `0`, `9999`) are permitted.
* Every nullable column has an explicit business justification documented below.

---

## 3. Core Schema (`core`)

### 3.1 `core.user_account`
Central identity registry for all actors (candidates, recruiters, consultants, administrators).

| Column Name | Data Type | Constraints | Nullable? | Nullability Justification (RG5) | Sensitivity (RG6) | Description |
| :--- | :--- | :--- | :---: | :--- | :---: | :--- |
| `id` | `BIGINT` | `PK, IDENTITY` | NO | Primary surrogate key | `[INTERNAL]` | Unique user account surrogate identifier |
| `email` | `VARCHAR(255)` | `UK, CHECK (RFC)`| NO | Primary login and communication identifier | `[SENSITIVE]` | Normalized lowercase RFC-compliant email address |
| `phone_e164` | `VARCHAR(20)` | `CHECK (E.164)` | YES | User may register via email prior to phone verification | `[SENSITIVE]` | International E.164 format telephone number |
| `phone_country_code`| `CHAR(2)` | `FK master.country`| YES | Dependent on whether phone number has been provided | `[SENSITIVE]` | ISO Alpha-2 country code for phone carrier |
| `account_status` | `VARCHAR(20)`| `CHECK (status)` | NO | Account state must always be deterministic | `[INTERNAL]` | Status: `'pending_verification'`, `'active'`, `'suspended'`, `'deactivated'` |
| `preferred_language`| `VARCHAR(10)`| `DEFAULT 'en'` | NO | UI localization requires a fallback language | `[PUBLIC]` | ISO language code for UI translations |
| `password_hash` | `VARCHAR(255)`| `CHECK (Argon2id)`| YES | OAuth / SSO users do not possess a password hash | `[SENSITIVE]` | Argon2id cryptographic password hash |
| `created_at` | `TIMESTAMPTZ` | `DEFAULT now()` | NO | Audit timestamp mandatory | `[INTERNAL]` | Account creation timestamp in UTC |
| `updated_at` | `TIMESTAMPTZ` | `DEFAULT now()` | NO | Audit timestamp mandatory | `[INTERNAL]` | Timestamp of last account modification in UTC |

### 3.2 `core.user_session`
Active authentication sessions and concurrent device management.

| Column Name | Data Type | Constraints | Nullable? | Nullability Justification (RG5) | Sensitivity (RG6) | Description |
| :--- | :--- | :--- | :---: | :--- | :---: | :--- |
| `id` | `BIGINT` | `PK, IDENTITY` | NO | Surrogate primary key | `[INTERNAL]` | Unique session identifier |
| `user_account_id` | `BIGINT` | `FK core.user_account`| NO | Every session must belong to a known user | `[INTERNAL]` | Referenced authenticated user |
| `device_identifier` | `VARCHAR(255)` | `NOT NULL` | NO | Device tracking mandatory for licence compliance | `[INTERNAL]` | Unique client device UUID or hardware token |
| `session_token_hash`| `VARCHAR(255)` | `UK, NOT NULL` | NO | Token hash required for session lookup | `[SENSITIVE]` | SHA-256 cryptographic hash of bearer token |
| `started_at` | `TIMESTAMPTZ` | `DEFAULT now()` | NO | Session start required | `[INTERNAL]` | Timestamp session was established |
| `last_activity_at` | `TIMESTAMPTZ` | `DEFAULT now()` | NO | Required for idle timeout calculation | `[INTERNAL]` | Timestamp of most recent user interaction |
| `ended_at` | `TIMESTAMPTZ` | `CHECK (>= started)` | YES | Active sessions have not yet ended | `[INTERNAL]` | Voluntary logout or session expiry timestamp |
| `revoked_at` | `TIMESTAMPTZ` | `CHECK (>= started)` | YES | Only present if forcibly revoked by admin/device limit | `[INTERNAL]` | Forced session revocation timestamp |

### 3.3 `core.user_block`
Bidirectional communication and outreach block list.

| Column Name | Data Type | Constraints | Nullable? | Nullability Justification (RG5) | Sensitivity (RG6) | Description |
| :--- | :--- | :--- | :---: | :--- | :---: | :--- |
| `id` | `BIGINT` | `PK, IDENTITY` | NO | Surrogate primary key | `[INTERNAL]` | Unique block identifier |
| `blocker_user_account_id`| `BIGINT` | `FK core.user_account`| NO | Blocker identity required | `[INTERNAL]` | User issuing the block |
| `blocked_user_account_id`| `BIGINT` | `FK core.user_account`| YES | Nullable when blocking an entire organization | `[INTERNAL]` | Target individual user being blocked |
| `blocked_organization_id`| `BIGINT` | `FK recruitment.org` | YES | Nullable when blocking a specific user | `[INTERNAL]` | Target organization being blocked |
| `block_reason` | `VARCHAR(500)` | | YES | Candidate may choose not to provide a reason | `[PERSONAL]` | Optional explanation for the block action |
| `created_at` | `TIMESTAMPTZ` | `DEFAULT now()` | NO | Audit timestamp mandatory | `[INTERNAL]` | Timestamp block was enacted |

---

## 4. Master Schema (`master`)

### 4.1 `master.country` / `master.city`
Standardized geographical and sovereign taxonomies.

| Column Name | Data Type | Constraints | Nullable? | Nullability Justification (RG5) | Sensitivity (RG6) | Description |
| :--- | :--- | :--- | :---: | :--- | :---: | :--- |
| `id` | `BIGINT` | `PK, IDENTITY` | NO | Surrogate primary key | `[PUBLIC]` | Canonical geographical identifier |
| `iso_alpha2` | `CHAR(2)` | `UK, NOT NULL` | NO | ISO 3166-1 standard code mandatory | `[PUBLIC]` | Two-letter country code (e.g. `'US'`, `'IN'`) |
| `iso_alpha3` | `CHAR(3)` | `UK, NOT NULL` | NO | ISO 3166-1 standard code mandatory | `[PUBLIC]` | Three-letter country code (e.g. `'USA'`, `'IND'`) |
| `name` | `VARCHAR(100)` | `NOT NULL` | NO | Official country/city display name mandatory | `[PUBLIC]` | Standard canonical entity name |
| `phone_calling_code`| `VARCHAR(10)` | `NOT NULL` | NO | Telecom dialing code mandatory | `[PUBLIC]` | International calling prefix (e.g. `'+91'`) |

### 4.2 `master.skill`
Canonical skill and technical competency registry.

| Column Name | Data Type | Constraints | Nullable? | Nullability Justification (RG5) | Sensitivity (RG6) | Description |
| :--- | :--- | :--- | :---: | :--- | :---: | :--- |
| `id` | `BIGINT` | `PK, IDENTITY` | NO | Surrogate primary key | `[PUBLIC]` | Canonical skill identifier |
| `name` | `VARCHAR(100)` | `NOT NULL` | NO | Display name mandatory | `[PUBLIC]` | Display name (e.g. `'PostgreSQL'`) |
| `normalized_name` | `VARCHAR(100)` | `UK, NOT NULL` | NO | Search lookup key mandatory | `[PUBLIC]` | Lowercase alphanumeric key (`'postgresql'`) |
| `category` | `VARCHAR(50)` | | YES | Emerging or cross-cutting skills may be uncategorized | `[PUBLIC]` | Functional taxonomy category |

---

## 5. Candidate Profile Schema (`profile`)

### 5.1 `profile.candidate_profile`
Core professional dossier linked to identity.

| Column Name | Data Type | Constraints | Nullable? | Nullability Justification (RG5) | Sensitivity (RG6) | Description |
| :--- | :--- | :--- | :---: | :--- | :---: | :--- |
| `id` | `BIGINT` | `PK, IDENTITY` | NO | Surrogate primary key | `[INTERNAL]` | Candidate profile surrogate key |
| `user_account_id` | `BIGINT` | `UK, FK core.user` | NO | 1-to-1 linkage with user account | `[INTERNAL]` | Referenced user account |
| `headline` | `VARCHAR(200)` | `CHECK (len > 0)` | YES | Draft profile may lack an initial headline | `[PERSONAL]` | Professional headline or role summary |
| `professional_summary`| `TEXT` | | YES | Optional extended candidate biography | `[PERSONAL]` | Detailed background statement |
| `total_experience_years`| `NUMERIC(4,1)`| `CHECK (>= 0)` | YES | Fresh graduates or early career may omit | `[PERSONAL]` | Cumulative years in professional workforce |
| `profile_status` | `VARCHAR(20)` | `CHECK (status)` | NO | Profile lifecycle state mandatory | `[INTERNAL]` | Status: `'draft'`, `'active'`, `'paused'` |
| `visibility` | `VARCHAR(20)` | `CHECK (vis)` | NO | Confidentiality policy mandatory | `[PERSONAL]` | Visibility: `'private'`, `'recruiters'`, `'public'` |

### 5.2 `profile.candidate_skill`
Candidate technical competencies linked to canonical skills.

| Column Name | Data Type | Constraints | Nullable? | Nullability Justification (RG5) | Sensitivity (RG6) | Description |
| :--- | :--- | :--- | :---: | :--- | :---: | :--- |
| `id` | `BIGINT` | `PK, IDENTITY` | NO | Surrogate primary key | `[INTERNAL]` | Skill claim identifier |
| `candidate_profile_id`| `BIGINT` | `FK profile.candidate`| NO | Skill claim must belong to a candidate | `[INTERNAL]` | Referenced candidate profile |
| `skill_id` | `BIGINT` | `FK master.skill` | NO | Must link to canonical master skill | `[PUBLIC]` | Referenced canonical skill |
| `proficiency_level` | `VARCHAR(20)` | `CHECK (level)` | YES | Candidate may declare skill without self-rating | `[PERSONAL]` | Level: `'beginner'`, `'intermediate'`, `'advanced'`, `'expert'` |
| `experience_years` | `NUMERIC(4,1)` | `CHECK (0..80)` | YES | Candidate may not track exact years per sub-skill | `[PERSONAL]` | Experience specific to this skill |
| `is_primary` | `BOOLEAN` | `DEFAULT FALSE` | NO | Primary skill flag mandatory | `[PERSONAL]` | Highlights core expertise on profile |

---

## 6. Recruitment Schema (`recruitment`)

### 6.1 `recruitment.job_posting`
Enterprise job requirements and vacancy announcements.

| Column Name | Data Type | Constraints | Nullable? | Nullability Justification (RG5) | Sensitivity (RG6) | Description |
| :--- | :--- | :--- | :---: | :--- | :---: | :--- |
| `id` | `BIGINT` | `PK, IDENTITY` | NO | Surrogate primary key | `[INTERNAL]` | Unique job vacancy identifier |
| `organization_id` | `BIGINT` | `FK recruitment.org` | NO | Employer organization mandatory | `[INTERNAL]` | Hiring organization |
| `employment_type_id`| `BIGINT` | `FK master.emp_type` | NO | Full-time / Part-time / Contract mandatory | `[PUBLIC]` | Canonical employment arrangement |
| `work_type_id` | `BIGINT` | `FK master.work_type`| NO | Remote / Hybrid / On-site mandatory | `[PUBLIC]` | Canonical workplace model |
| `city_id` | `BIGINT` | `FK master.city` | YES | Fully remote jobs do not have a physical city | `[PUBLIC]` | Physical job location |
| `title` | `VARCHAR(200)` | `NOT NULL` | NO | Job role title mandatory | `[PUBLIC]` | Public vacancy title |
| `job_status` | `VARCHAR(20)` | `CHECK (status)` | NO | Publication state mandatory | `[INTERNAL]` | Status: `'draft'`, `'published'`, `'paused'`, `'closed'` |
| `currency_code` | `CHAR(3)` | `CHECK (ISO 4217)` | YES | Companion required only if salary is declared | `[PUBLIC]` | Three-letter currency code (e.g. `'USD'`) |
| `salary_min` | `NUMERIC(14,2)`| `CHECK (>= 0)` | YES | Employer may choose not to disclose salary range | `[INTERNAL]` | Minimum compensation tier |
| `salary_max` | `NUMERIC(14,2)`| `CHECK (>= min)` | YES | Dependent on whether compensation is disclosed | `[INTERNAL]` | Maximum compensation tier |
| `published_at` | `TIMESTAMPTZ` | | YES | Draft or unpublished jobs have not been published | `[PUBLIC]` | Timestamp vacancy went live |

### 6.2 `recruitment.candidate_application`
The central hiring pipeline transaction table.

| Column Name | Data Type | Constraints | Nullable? | Nullability Justification (RG5) | Sensitivity (RG6) | Description |
| :--- | :--- | :--- | :---: | :--- | :---: | :--- |
| `id` | `BIGINT` | `PK, IDENTITY` | NO | Surrogate primary key | `[INTERNAL]` | Application transaction identifier |
| `candidate_profile_id`| `BIGINT` | `FK profile.candidate`| NO | Applicant profile mandatory | `[INTERNAL]` | Applying candidate |
| `job_posting_id` | `BIGINT` | `FK recruitment.job` | NO | Vacancy requirement mandatory | `[INTERNAL]` | Target job posting |
| `application_status`| `VARCHAR(20)` | `CHECK (status)` | NO | Pipeline state mandatory | `[INTERNAL]` | Stage: `'applied'`, `'shortlisted'`, `'interviewed'`, `'offered'`, `'joined'`, `'rejected'` |
| `application_source`| `VARCHAR(30)` | `CHECK (source)` | NO | Source attribution mandatory | `[INTERNAL]` | Source: `'direct'`, `'referral'`, `'agency'`, `'career_site'` |
| `applied_at` | `TIMESTAMPTZ` | `DEFAULT now()` | NO | Submission timestamp mandatory | `[INTERNAL]` | UTC timestamp application was placed |
| `last_status_changed_at`| `TIMESTAMPTZ`| `DEFAULT now()` | NO | Stage velocity tracking mandatory | `[INTERNAL]` | Timestamp of most recent status transition |

---

## 7. Gig Marketplace Schema (`gig`)

### 7.1 `gig.gig_assignment`
Contract project allocations with non-overlapping temporal constraints.

| Column Name | Data Type | Constraints | Nullable? | Nullability Justification (RG5) | Sensitivity (RG6) | Description |
| :--- | :--- | :--- | :---: | :--- | :---: | :--- |
| `id` | `BIGINT` | `PK, IDENTITY` | NO | Surrogate primary key | `[INTERNAL]` | Contract assignment identifier |
| `gig_request_id` | `BIGINT` | `FK gig.gig_request` | NO | Deliverable requirement mandatory | `[INTERNAL]` | Sponsoring corporate gig project |
| `gig_application_id`| `BIGINT` | `FK gig.gig_app` | NO | Approved worker bid mandatory | `[INTERNAL]` | Accepted application proposal |
| `gig_worker_profile_id`| `BIGINT`| `FK gig.gig_worker` | NO | Appointed contractor mandatory | `[INTERNAL]` | Assigned gig worker profile |
| `assigned_start_date`| `DATE` | `NOT NULL` | NO | Project start boundary mandatory | `[INTERNAL]` | Contract start date |
| `assigned_end_date` | `DATE` | `CHECK (>= start)` | NO | Project end boundary mandatory | `[INTERNAL]` | Contract expected delivery date |
| `agreed_amount` | `NUMERIC(14,2)`| `CHECK (> 0)` | NO | Financial compensation agreed contract | `[SENSITIVE]` | Agreed contract remuneration |
| `currency_code` | `CHAR(3)` | `DEFAULT 'USD'` | NO | Companion currency mandatory | `[PUBLIC]` | ISO 4217 currency code |
| `assignment_status` | `VARCHAR(20)` | `CHECK (status)` | NO | Contract execution state mandatory | `[INTERNAL]` | Status: `'active'`, `'completed'`, `'cancelled'`, `'disputed'` |
| `external_handoff_ref`| `VARCHAR(255)`| `NOT NULL` | NO | External fulfillment sync reference | `[INTERNAL]` | External system reconciliation ID |

---

## 8. Commercial & Financial Ledgers (`commercial`)

### 8.1 `commercial.wallet_ledger`
Strictly append-only corporate credit movement log (Rule Group 7).

| Column Name | Data Type | Constraints | Nullable? | Nullability Justification (RG5) | Sensitivity (RG6) | Description |
| :--- | :--- | :--- | :---: | :--- | :---: | :--- |
| `id` | `BIGINT` | `PK, IDENTITY` | NO | Surrogate primary key | `[INTERNAL]` | Ledger sequence transaction ID |
| `wallet_id` | `BIGINT` | `FK commercial.wallet`| NO | Associated wallet account mandatory | `[INTERNAL]` | Corporate wallet entity |
| `entry_type` | `VARCHAR(20)` | `CHECK (type)` | NO | Accounting direction mandatory | `[INTERNAL]` | Type: `'credit'`, `'debit'`, `'correction_credit'`, `'correction_debit'` |
| `amount` | `NUMERIC(14,2)`| `CHECK (> 0)` | NO | Transaction value must be positive | `[SENSITIVE]` | Credit/Debit movement amount |
| `currency_code` | `CHAR(3)` | `DEFAULT 'USD'` | NO | Companion currency code mandatory | `[PUBLIC]` | ISO 4217 currency code |
| `balance_after` | `NUMERIC(14,2)`| `CHECK (>= 0)` | NO | Running balance mandatory | `[SENSITIVE]` | Wallet balance following transaction |
| `reference_type` | `VARCHAR(40)` | `CHECK (ref_type)`| NO | Transaction classification mandatory | `[INTERNAL]` | Ref: `'recharge'`, `'profile_download'`, `'job_posting_fee'`, `'correction'` |
| `correction_of_ledger_id`| `BIGINT`| `FK commercial.wallet_ledger`| YES | Present strictly if transaction is a correction | `[INTERNAL]` | Self-referencing link to rectified ledger row |
| `notes` | `VARCHAR(500)` | | YES | Optional human explanation or PO reference | `[INTERNAL]` | Transaction audit narrative |
| `created_by_user_account_id`| `BIGINT`| `FK core.user_account`| NO | Actor accountability mandatory | `[INTERNAL]` | User issuing the financial transaction |
| `recorded_at` | `TIMESTAMPTZ` | `DEFAULT now()` | NO | Transaction timestamp immutable | `[INTERNAL]` | UTC timestamp recorded on disk |

---

## 9. Audit Schema (`audit`)

### 9.1 `audit.audit_event`
Tamper-proof compliance and access log (Rule Group 7).

| Column Name | Data Type | Constraints | Nullable? | Nullability Justification (RG5) | Sensitivity (RG6) | Description |
| :--- | :--- | :--- | :---: | :--- | :---: | :--- |
| `id` | `BIGINT` | `PK, IDENTITY` | NO | Surrogate primary key | `[INTERNAL]` | Immutable sequence event identifier |
| `user_account_id` | `BIGINT` | | YES | System processes / anonymous requests lack user ID | `[INTERNAL]` | Acting user account ID |
| `organization_id` | `BIGINT` | | YES | Candidate actions are not bound to an organization | `[INTERNAL]` | Acting tenant organization ID |
| `event_type` | `VARCHAR(60)` | `NOT NULL` | NO | Security event classification mandatory | `[INTERNAL]` | Event type (e.g. `'login_success'`, `'device_limit_exceeded'`) |
| `severity` | `VARCHAR(20)` | `DEFAULT 'info'` | NO | Severity classification mandatory | `[INTERNAL]` | Severity: `'info'`, `'warning'`, `'critical'` |
| `ip_address` | `INET` | | YES | Background workers do not possess a client IP | `[SENSITIVE]` | Client IP address in IPv4/IPv6 notation |
| `user_agent` | `VARCHAR(500)` | | YES | Programmatic API calls may omit User-Agent | `[INTERNAL]` | Browser or client SDK identity header |
| `metadata` | `JSONB` | | YES | Simple events do not require auxiliary context | `[INTERNAL]` | Structured before/after payloads or context |
| `created_at` | `TIMESTAMPTZ` | `DEFAULT now()` | NO | Event occurrence timestamp mandatory | `[INTERNAL]` | Immutable event timestamp in UTC |
