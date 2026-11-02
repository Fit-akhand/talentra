# Talentra Rule Group Compliance (Docket Section 5)

**Engine:** PostgreSQL (the docket allows PostgreSQL or MySQL; PostgreSQL was chosen, see `09-architecture.md`)
**Checked:** 2026-10-28 against the live schema (migrations 001-035, applied on PostgreSQL 17.11, the declared target; the same documents generate identically on 16.15)
**How to read the result:** each row says what the schema does today and what test or query shows it. A deviation is listed with its reason and its risk, as the docket requires. Verdicts are `Complies`, `Partly` or `Deviation`.

> **Numbering warning.** `scripts/validate_data.py` labels its checks RG1-RG10 using its own numbering, which differs from the docket's for several groups (for example the validator's "RG7" is ledgers; the docket's Rule Group 7 is multilingual data). This table uses the **docket's** numbering. The validator's evidence is kept in Appendix A.

## Compliance table

| Rule group | Design complies | Deviation, with reason and risk | Evidence |
|:--|:--|:--|:--|
| **1 Naming conventions** | **Complies** | **Index names:** 18 of 307 indexes do not follow `idx_`/`uq_`. They are PostgreSQL defaults for primary keys declared inline (`*_pkey`), the two exclusion constraints (`ex_*`), and partition indexes the engine names itself. *Risk:* low; none is referenced by name in application code. **Reserved words:** no table or column name is a PostgreSQL reserved word (`pg_get_keywords()`, category R). The MySQL list was not checked because the design targets PostgreSQL only. | `validate_data.py` (RG1); query in this table's source |
| **2 Keys and constraints** | **Complies** | **Update rule:** 7 foreign keys leave `ON UPDATE` as `NO ACTION` (immediate in practice, equivalent to `RESTRICT`). The other 328 state both rules (242 RESTRICT, 62 CASCADE and 24 SET NULL on delete, all RESTRICT on update); 335 foreign keys in all. | `pg_constraint`; `test_concurrency.py`; `test_licences.sql` |
| **3 Standard domains** | **Complies**, with one design choice | **Enumerations:** the CHECK constraints stay the authority on allowed values, because triggers and queries branch on them and a data edit must not be able to add one (DEC-27). `master.enumeration_value` mirrors every CHECK list (337 values in 74 columns) with code, sort order and active flag, and each value has an English display name in `messaging.ui_translation` (key `enum.<schema>.<table>.<column>.<code>`), falling back to English in every other language. `tests/test_enumerations.sql` fails when the two drift. *Risk:* only English labels exist; other languages are added as translation rows. **Tax identifiers:** canonical form and check digits per type are implemented in `scripts/identifier_crypto.py` (DEC-25); VAT and company numbers are only length-checked. **Booleans** are `NOT NULL` with a default except `application_question_response.boolean_response` (NULL means "not answered", a tri-state by design) and the derived `analytics.dim_date.is_weekend`. Money has a companion currency everywhere after migration 026. No `float`, no `timestamp without time zone`. | `validate_data.py`; `test_enumerations.sql`; `test_domains_and_transitions.sql` (money and language); catalog queries |
| **4 Audit and lifecycle** | **Complies** | **Retention periods were approved by the assistant, not by a data owner** (DEC-23, under the owner's delegation); `core.user_account` is the exception and stays unapproved because account retention depends on legal advice. **Scheduling:** `core.run_maintenance()` runs the purge, the inactive-account erasure and the mart refresh and records each run; the `maintenance` service in `docker-compose.yml` calls it on a loop. | `test_lifecycle.sql` (audit columns on every non-append-only table, soft-delete classification, retention, erasure, inactivity); `test_integration_maintenance.sql` |
| **5 Nullability and unknown values** | **Complies** | **418 of 418 nullable columns say what NULL means** in their definition (migration 033, plus the earlier ones); `tests/test_column_definitions.sql` fails otherwise. The wording for columns whose meaning follows from a pattern (optional foreign key, optional URL) is generic; the 35 whose meaning is not obvious were written by hand. No sentinel values are used (validator check). | `07-attribute-catalogue.md` (counts are generated); `test_column_definitions.sql`; `validate_data.py` |
| **6 Sensitive data classification** | **Complies**, AI-reviewed | Every column of every base table is classified and says how it is protected, and a test fails when a column is added without one. The classification was reviewed by the assistant under the owner's delegation (DEC-24): class follows what a column holds, not its name. No human has reviewed it. **No Sensitive column is unprotected.** The tax identifier is stored as AES-256-GCM ciphertext with an HMAC blind index (migration 034, DEC-25); the key is held by the application, which does not yet exist in this repository, and the seed uses a public development key. | `test_classification.sql`; `test_identifier_encryption.sql`; `test_identifier_crypto.py`; `12-threat-model.md` |
| **7 Multilingual data** | **Complies** | **Language of user-entered text is nullable** (`description_language_code`, `summary_language_code`, `content_language_code`) because the docket says "where it is known". Other free text (cover letters, project descriptions) does not yet record a language. | `test_messaging.sql`; `test_domains_and_transitions.sql` |
| **8 Naming of physical objects** | **Complies** | None. Partitions `candidate_application_y2025/2026/2027`; default-query views `active_<table>`; analytical objects live in schema `analytics` and are prefixed `dim_`, `fact_`, `mv_`. | catalog |
| **Reserved keyword check** | **Complies** | PostgreSQL only; see rule group 1. | `pg_get_keywords()` |
| **9 Licensing, devices and sessions** | **Complies** | None. `max_users` and `max_devices_per_user` are explicit columns with `CHECK (> 0)`; the limit is enforced at login under a row lock; ended and revoked sessions are not counted; the refused attempt and every revocation are audited. | `test_licences.sql`; `test_concurrency.py` |
| **10 Money, subscriptions and history** | **Complies** | **View history records a flag, not an amount:** `profile.profile_view_history.credit_deducted` is a boolean, while download history records the amount. The docket asks for the deduction "where one applies"; if viewing is ever charged by amount, the column must change. | `test_commercial.sql`; `test_access_control.sql` (app role cannot alter the ledger); `test_domains_and_transitions.sql` (history append-only) |

## What changed since the previous version of this document

The previous version reported "100% compliant (15/15)". That number is the validator's, and it measures fifteen checks of its own devising, not the docket's ten groups. Checked against the docket, three groups were **not** met: Rule Group 4 (2 of 92 tables had audit columns, none had soft delete or retention), Rule Group 3 (three money columns without a currency; enumerations not in lookup tables) and Rule Group 7 (no content language). Migrations 020, 024, 025 and 026 close what could be closed; the remainder is listed above as deviations.

## Appendix A. Validator evidence (the validator's own numbering)

| Rule Group | Rule Domain Description | Mandatory Invariant | Enforcing Mechanism / Objects | Automated Audit Status |
| :---: | :--- | :--- | :--- | :---: |
| **RG1** | **Naming & Identifier Standards** | Strict `snake_case`, singular entity names, semantic boolean prefixes (`is_`, `has_`, `can_`, `allow_`, `show_`) | DDL naming conventions across all 10 schemas | **PASS** |
| **RG2** | **Surrogate Key Architecture** | All operational primary keys use `BIGINT GENERATED ALWAYS AS IDENTITY` named `id` | Table DDL `pk_*` constraints | **PASS** |
| **RG3** | **Domain & Format Constraints** | Lowercase RFC emails, E.164 phone formats (`^\+[1-9]\d{1,14}$`), ISO 4217 currencies, ISO 3166 countries | CHECK constraints: `ck_user_account_email_format`, `ck_user_account_phone_format`, `ck_job_posting_salary_currency` | **PASS** |
| **RG4** | **Temporal & Chronological Standards** | Universal `TIMESTAMPTZ` in UTC; chronological sequence integrity (`end_date >= start_date`, `valid_to >= valid_from`) | CHECK constraints: `ck_candidate_education_dates`, `ck_gig_worker_availability_dates`, `ck_gig_assignment_dates` | **PASS** |
| **RG5** | **Nullability & Anti-Sentinel Discipline** | Missing data represented strictly as SQL `NULL`; zero dummy sentinel strings (`'NA'`, `'NONE'`, `'NULL'`, `'UNKNOWN'`) | DDL `NOT NULL` constraints & Data Dictionary justification table | **PASS** |
| **RG6** | **Sensitive Data Classification** | Cryptographic password hashing (Argon2id/bcrypt), PII classification tags (`[PUBLIC]`, `[INTERNAL]`, `[PERSONAL]`, `[SENSITIVE]`) | CHECK constraint `ck_user_account_password_hash` (length only) + runtime hash-format check in `scripts/validate_data.py:210-215` + Data Dictionary | **PASS** |
| **RG7** | **Append-Only Ledgers & Immutability** | Financial transactions and audit logs are strictly append-only; balance $\equiv \sum \text{credits} - \sum \text{debits}$ | Database triggers: `trg_prevent_wallet_ledger_tampering`, `trg_prevent_audit_event_tampering` | **PASS** |
| **RG8** | **Multilingual UI & Fallback Logic** | Multilingual UI translation resolution with dynamic fallback to default English | Table `messaging.ui_translation` + Function `messaging.get_ui_translation(key, lang)` | **PASS** |
| **RG9** | **Licensing & Device Limit Enforcement** | Active user devices cannot exceed purchased licence limit (`max_devices_per_user`); pessimistic locking on the user account row | Function `core.create_session_with_device_limit` with `SELECT ... FOR UPDATE` on `core.user_account` | **PASS** |
| **RG10** | **Partitioning & Exclusion Integrity** | High-velocity applications partitioned by range; non-overlapping gig worker calendars enforced at DB level | Declarative Range Partitions + GiST exclusion `ex_gig_assignment_no_overlap` | **PASS** |

---

## 2. Rule Group Evidence & Technical Proofs

### Rule Group 1: Naming & Identifier Standards
* **Verification Logic**: Scans all `information_schema.tables` and `information_schema.columns` across all 10 schemas.
* **Result**: Zero non-snake_case identifiers. All boolean columns use standard semantic prefixes (`is_active`, `is_primary`, `is_headquarters`, `has_work_permit`, `allow_recruiter_direct_message`).

### Rule Group 2: Surrogate Primary Key Architecture
* **Verification Logic**: Verifies that every table in operational schemas (`core`, `profile`, `recruitment`, `gig`, `commercial`, `sourcing`, `messaging`, `audit`) possesses a surrogate key named `id` (or standard dimensional keys `date_key`, `job_posting_key` in OLAP marts).
* **Result**: 100% compliance. All operational tables utilize `BIGINT GENERATED ALWAYS AS IDENTITY`.

### Rule Group 3: Domain & Formatting Constraints
* **RFC Email Check**:
  ```sql
  CONSTRAINT ck_user_account_email_format
  CHECK (email ~ '^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$')
  ```
  Verified: Zero uppercase or malformed emails permitted in `core.user_account`.
* **E.164 Phone Format Check**:
  ```sql
  CONSTRAINT ck_user_account_phone_format
  CHECK (phone_e164 IS NULL OR phone_e164 ~ '^\+[1-9]\d{1,14}$')
  ```
  Verified: Zero non-compliant phone numbers stored.
* **ISO 4217 Currency Standards**:
  ```sql
  CONSTRAINT ck_job_posting_salary_currency
  CHECK (
      (salary_min IS NULL AND salary_max IS NULL AND currency_code IS NULL AND salary_period IS NULL)
      OR
      ((salary_min IS NOT NULL OR salary_max IS NOT NULL)
       AND currency_code IS NOT NULL
       AND currency_code ~ '^[A-Z]{3}$'
       AND salary_period IS NOT NULL
       AND salary_period IN ('hour', 'day', 'week', 'month', 'year'))
  )
  ```
  Verified: All currency codes are exactly 3 uppercase alphabetic characters (`USD`, `EUR`, `GBP`, `INR`).

### Rule Group 4: Temporal & Chronological Range Standards
* **Chronological Integrity Constraints**:
  * `profile.candidate_work_experience`: `CHECK (end_date IS NULL OR end_date >= start_date)`
  * `profile.candidate_education`: `CHECK (end_date IS NULL OR end_date >= start_date)`
  * `gig.gig_worker_availability`: `CHECK (available_to >= available_from)`
  * `gig.gig_assignment`: `CHECK (assigned_end_date >= assigned_start_date)`
  * `commercial.subscription_licence`: `CHECK (valid_to >= valid_from)`
* **Audit Execution**: Automated queries across the operational dataset confirmed 0 inverted date ranges.

### Rule Group 5: Nullability & Anti-Sentinel Discipline
* **Zero Dummy String Rule**: Prohibits sentinel strings such as `'NA'`, `'N/A'`, `'NONE'`, `'NULL'`, `'UNKNOWN'`, or `'?'`.
* **Zero Dummy Number Rule**: Prohibits `-1`, `0`, or `9999` used to represent missing dates or foreign keys.
* **Automated Audit**: Full-text scanning across candidate headlines, summaries, and notes yielded **0 sentinel values**. All missing attributes are stored strictly as SQL `NULL`.

### Rule Group 6: Sensitive Data Classification & Hashing
* **Cryptographic Password Check**:
  The schema-level constraint is a length check only:
  ```sql
  CONSTRAINT ck_user_account_password_hash
  CHECK (password_hash IS NULL OR LENGTH(password_hash) > 0)
  ```
  The Argon2id / bcrypt **header format** is verified at runtime by the validator, not enforced by a DDL constraint:
  ```sql
  -- scripts/validate_data.py:210-215
  SELECT COUNT(*)
  FROM core.user_account
  WHERE password_hash IS NOT NULL
    AND password_hash !~ '^\$(argon2id|2b|2a)\$';
  ```
  Verified: 100% of stored passwords conform to modern salted Argon2id / bcrypt standard headers. *The schema does not enforce the algorithm; `core.user_credential.algorithm` merely defaults to `argon2id`.*
* **PII Classification**: All columns cataloged in `docs/phase-2-model/10-data-dictionary.md` with explicit `[PUBLIC]`, `[INTERNAL]`, `[PERSONAL]`, and `[SENSITIVE]` classification tags. *The dictionary currently documents 13 of 95 tables; full coverage is outstanding.*

### Rule Group 7: Append-Only Ledgers & Financial Reconciliation
* **Immutability Triggers**:
  Direct `UPDATE` and `DELETE` queries on `commercial.wallet_ledger` and `audit.audit_event` are blocked by database triggers:
  ```sql
  CREATE TRIGGER trg_prevent_wallet_ledger_tampering
  BEFORE UPDATE OR DELETE ON commercial.wallet_ledger
  FOR EACH ROW EXECUTE FUNCTION commercial.prevent_ledger_tampering();
  ```
* **Balance Reconciliation Proof**:
  Automated SQL execution verifies:
  $$\text{Wallet Balance} \equiv \sum \text{Credits} - \sum \text{Debits}$$
  Across all enterprise client wallets, zero reconciliation discrepancies were detected. *This is an observation of the last validator run on the seeded dataset, not a standing property. `commercial.wallet.balance` is a stored column — no trigger derives it from the ledger, so the invariant is checked rather than enforced by the schema.*

### Rule Group 8: Multilingual UI & Fallback Resolution
* **Dynamic Translation Engine**:
  ```sql
  SELECT messaging.get_ui_translation('btn.apply_job', 'es'); -- Returns: 'Postularse para este puesto'
  SELECT messaging.get_ui_translation('btn.apply_job', 'ja'); -- Returns: 'Apply for this Role' (English Fallback)
  ```
  The English-fallback value is the `en` row of `messaging.ui_translation` for `btn.apply_job`, which has two possible sources. The migration seed (`db/migrations/018_create_messaging_and_translations.sql:43`) sets `'Apply for this Role'`; the synthetic loader (`scripts/generate_data.py:166`) sets `'Apply Now'`. **Both seeders use `ON CONFLICT (string_key, language_code) DO NOTHING`**, so the migration row is written first and survives the loader's `ON CONFLICT` no-op. In the documented setup — migrations 001–019 applied (`README.md` step 2), then optional synthetic seeding (step 4) — the fallback therefore resolves to `'Apply for this Role'`. `'Apply Now'` appears only in a database seeded *exclusively* by `scripts/generate_data.py` without the migration applied. `tests/test_messaging.sql:43` accepts either value, so the behaviour is correct either way; only the documented value needed correction.
* **Unicode script coverage**: UTF-8 integrity is exercised across the Latin and Devanagari scripts by the seeded UI translations (`'Postularse para este puesto'`, `'इस पद के लिए आवेदन करें'`), with zero mojibake errors. *No Cyrillic string exists in `messaging.ui_translation` in any seeding path — the seeded language codes are `en`, `es`, `hi`, `fr` (migration 018) and `en`, `es`, `de`, `hi`, `fr` (the synthetic loader). The only Cyrillic literal in the schema is `('ru', 'Russian', 'Русский')` in `master.language.native_name` (`db/migrations/010_create_candidate_extensions.sql:41`), which is a language-code reference table and is not read by `messaging.get_ui_translation`.*

### Rule Group 9: Licensing & Concurrent Session Device Limits
* **Atomic Session Creation**:
  Executed via `core.create_session_with_device_limit(p_user_id, p_device_id, p_token_hash)`.
* **Pessimistic Locking**:
  Pessimistically locks the `core.user_account` row with `FOR UPDATE` to serialize concurrent login attempts. The licence seat allocation is read to derive the device entitlement. If concurrent active sessions exceed `max_devices_per_user`, session creation is blocked and logged in `audit.audit_event`.
* **Audit Execution**: Verified that 0 active users exceed their entitlement quota.

### Rule Group 10: Partitioning & Exclusion Constraint Integrity
* **Declarative Range Partitioning**:
  `recruitment.candidate_application_partitioned` successfully partitioned by `RANGE (applied_at)` with compound PK `(id, applied_at)`.
* **GiST Calendar Exclusion**:
  ```sql
  CONSTRAINT ex_gig_assignment_no_overlap
  EXCLUDE USING gist (
      gig_worker_profile_id WITH =,
      daterange(assigned_start_date, assigned_end_date, '[]') WITH &&
  )
  WHERE (assignment_status = 'active');
  ```
  Verified: Guarantees zero double-booked gig workers at the hardware storage layer.
