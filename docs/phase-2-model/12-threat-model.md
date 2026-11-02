# Talentra Security & Threat Model Dossier
**System Engine**: PostgreSQL 17  
**Framework**: STRIDE Threat Analysis & Defense-in-Depth  
**Target Compliance Framework** (alignment intent; no attestation performed): GDPR Article 25/32, SOC 2 Type II, PCI-DSS SAQ-A

---

## 1. Executive Security Architecture

Talentra's security architecture operates on a **Zero-Trust Relational Core** model. Security boundaries are not merely applied in the application layer; several controls are baked directly into PostgreSQL 17 via **append-only ledgers**, **cryptographic hashing standards**, and **anti-tampering triggers**. *Granular database roles (§3) and declarative Row-Level Security (§4) are **proposed designs that are not yet implemented** in this repository.*

```
                           +----------------------------------------+
                           |        External Client Requests        |
                           +----------------------------------------+
                                                |
                               +----------------v---------------+
                               |  TLS 1.3 / API Gateway / WAF   |
                               +--------------------------------+
                                                |
                               +----------------v---------------+
                               |   RBAC & Permission Check      |
                               | (admin, recruiter, candidate)  |
                               +--------------------------------+
                                                |
         =======================================v=======================================
                            POSTGRESQL 17 DEFENSE-IN-DEPTH CORE
         ===============================================================================
          [Row-Level Security]   [Cryptographic Hashing]   [Append-Only Immutability]
          - Tenant Isolation (I)  - Password Hashing (I)   - Anti-Tamper Triggers
          - Recruiter Bound (I)   - SHA-256 Checksums      - Correction Ledgers
          - Candidate Blocks (I)  - E.164 Normalization    - Immutable Audit Events
         ===============================================================================
          (I) IMPLEMENTED and tested (migrations 021, 022; tests/test_access_control.sql).
```

---

## 2. STRIDE Threat Analysis Matrix

| Threat Category | Potential Attack Vector | Impact Level | Architectural Mitigation & PostgreSQL Control | Verification Mechanism |
| :--- | :--- | :---: | :--- | :--- |
| **Spoofing** | Credential stuffing, brute force login, session token forgery | **Critical** | Passwords are stored as salted hashes. `core.user_credential.algorithm` **defaults** to `argon2id` but the schema does not enforce the format, and hashing is performed by the application layer. Session tokens are stored as hashes in `core.user_session.session_token_hash` (length-constrained only). Login calls `core.create_session_with_device_limit` enforcing device limit entitlements. | `tests/test_identity.sql`, `tests/test_licences.sql`, `tests/test_concurrency.py` |
| **Tampering** | Recruiter alters the credit ledger, the audit trail, or the download history | **High** | Append-only immutability enforced by triggers (`trg_prevent_wallet_ledger_tampering`, `trg_prevent_audit_event_tampering`, `trg_prevent_download_history_tampering`). `UPDATE` and `DELETE` on financial ledgers raise fatal PostgreSQL exceptions. Corrections require explicit self-referencing debit/credit rows. *Candidate assessment scores are deliberately mutable and are not protected by these triggers.* | `tests/test_commercial.sql`, `tests/test_administration.sql` |
| **Repudiation** | Client denies downloading candidate profile or spending wallet credits | **High** | Append-only audit logging in `commercial.candidate_profile_download_history` capturing downloader user ID, organization ID, wallet ledger ID, and timestamp. *IP address and user-agent are captured on `audit.audit_event`, which does not currently receive download events.* Cannot be altered or deleted by `UPDATE`/`DELETE`; `TRUNCATE` is not blocked by a trigger. | `tests/test_commercial.sql`, Query 08 |
| **Information Disclosure** | Recruiter scrapes unconsented candidate phone numbers or salary history | **High** | PII data classification is defined in `docs/phase-2-model/10-data-dictionary.md`. Consent state is modelled in `core.consent_record`. `core.user_block` records block state, and `core.is_candidate_visible_to()` enforces it for callers of that function. *Phone/email masking for unauthorized viewers is not currently implemented at the database layer.* | `tests/test_administration.sql`, Query 06 |
| **Denial of Service** | Malicious bot floods login to exhaust device limits or runs unindexed query | **Medium** | Rate limiting at API gateway; concurrency limits locked atomically (`FOR UPDATE` on the `core.user_account` row) in `core.create_session_with_device_limit`. High-velocity applications have a prepared range-partitioned table (`recruitment.candidate_application_partitioned`); the operational application table is currently the unpartitioned `recruitment.candidate_application`. All 12 operational queries are backed by optimized B-Tree indexes, with GiST indexes backing two exclusion constraints. | `tests/test_concurrency.py`, `tests/test_licences.sql` |
| **Elevation of Privilege** | External consultant attempts to source candidates for private internal jobs | **Critical** | Database trigger `trg_enforce_consultant_openness` (on `sourcing.consultant_sourcing_request`) prevents non-consultant jobs from receiving agency submissions. Granular RBAC roles (`talentra_app`, `talentra_reporting`, `talentra_admin`) are a **proposed** model — see §3. | `tests/test_sourcing.sql`, `tests/test_administration.sql` |

---

## 3. Role-Based Access Control (RBAC) & Database Roles

**Implemented in migration 021** and tested by acting as each role (`tests/test_access_control.sql`). Five `NOLOGIN` group roles exist; a login role per environment is made a member of one of them. No password lives in a migration.

| Role | May | May not |
|:--|:--|:--|
| `talentra_app` | Read and write business data (subject to row-level security); append to `audit.audit_event` and `audit.system_error_log`; add rows to the ledger and history tables | Change or delete ledger and history rows; change reference (`master`) data; read the audit log; run DDL |
| `talentra_readonly` | Read everything except credentials, sessions and the raw account table | Write anything |
| `talentra_auditor` | Read the `audit` schema | Anything else |
| `talentra_analyst` | Read the `analytics` schema | Read operational tables |
| `talentra_support` | Read `core.support_user_account` (masked email and phone) and support tickets | Read the raw account table or any credential |

The instance still has one `SUPERUSER`, `talentra_admin`, created by `POSTGRES_USER` in `docker-compose.yml`. It owns the schema and bypasses row-level security by design. **The application must never connect as it.** The original proposal follows for the record; the migration replaced `talentra_reporting` with the narrower roles above.

```sql
-- 1. Operational Application Role (Least Privilege)
CREATE ROLE talentra_app WITH LOGIN PASSWORD '...';
GRANT USAGE ON SCHEMA core, master, profile, recruitment, gig, sourcing, commercial, messaging TO talentra_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA core, profile, recruitment, gig, sourcing, commercial, messaging TO talentra_app;
GRANT SELECT, INSERT ON TABLE commercial.wallet_ledger, commercial.candidate_profile_download_history TO talentra_app;
-- A GRANT does not narrow an earlier GRANT: reclaim the write access the blanket grant above conferred.
REVOKE UPDATE, DELETE ON TABLE commercial.wallet_ledger, commercial.candidate_profile_download_history FROM talentra_app;
GRANT SELECT, INSERT ON TABLE audit.audit_event, audit.system_error_log TO talentra_app;
-- Forbid TRUNCATE, DROP, ALTER for application user
REVOKE ALL ON SCHEMA audit FROM talentra_app;
GRANT USAGE ON SCHEMA audit TO talentra_app;
GRANT INSERT, SELECT ON ALL TABLES IN SCHEMA audit TO talentra_app;

-- 2. Business Intelligence & Reporting Role (Read-Only)
CREATE ROLE talentra_reporting WITH LOGIN PASSWORD '...';
GRANT USAGE ON SCHEMA analytics, master TO talentra_reporting;
GRANT SELECT ON ALL TABLES IN SCHEMA analytics, master TO talentra_reporting;
REVOKE ALL ON SCHEMA core, profile, commercial, audit FROM talentra_reporting;

-- 3. Migration & Administration Role (High Privilege)
CREATE ROLE talentra_admin WITH LOGIN SUPERUSER PASSWORD '...';
```

### Application-Level Permissions Matrix

| Entity / Action | Candidate | Recruiter | Agency Consultant | Organization Admin | Platform Superadmin |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Manage Own Profile / CV** | **Full** | None | None | None | Read |
| **Search Published Jobs** | **Full** | Read | Read | Read | Read |
| **Post Job Requirements** | None | **Full** (Own Org) | None | **Full** (Own Org) | Full |
| **Review Candidate Applications** | Own Only | **Full** (Own Org) | Submissions Only | **Full** (Own Org) | Full |
| **Download Unlocked Profiles** | None | Deduct Credits | Deduct Credits | Deduct Credits | Full |
| **Source for Private Jobs** | None | Assigned Only | **Denied (Trigger)** | Assigned Only | Full |
| **Manage Wallet & Recharge** | None | View Balance | None | **Full** | Full |
| **Inspect Append-Only Audit Logs** | None | None | None | Own Org Only | **Full** |

---

## 4. Row-Level Security (RLS) & Multi-Tenant Isolation — IMPLEMENTED (migration 021)

Row-level security is **enabled and tested** on these tables: `recruitment.job_posting`, `recruitment.candidate_application`, `commercial.wallet`, `commercial.wallet_ledger`, `profile.candidate_profile`, `profile.candidate_activity_log`, `profile.candidate_search_history`, `profile.course_enrolment`, `core.user_credential`, `core.user_session`, `core.user_device`, `messaging.notification_delivery`. Every other table relies on grants only; that is a known boundary, not an oversight.

The application sets who is acting at the start of each transaction (`SELECT set_config('app.current_user_id', '<id>', true)`, and `app.current_org_id` when acting for an organisation). With neither set, a session sees only published jobs: it fails closed.

**Differences from the original proposal below, and why:**
1. `app.current_org_id` is honoured only if the user is an *active member* of that organisation (`core.current_org_id()`). The proposal trusted the setting, so a bug that wrote another tenant's id would have exposed that tenant's data.
2. Policies call small `SECURITY DEFINER` helpers (`core.is_platform_admin`, `core.owns_candidate_profile`, `recruitment.job_organization_id`) and `core.is_candidate_visible_to` was made `SECURITY DEFINER` as well. Without that, the candidate-profile policy and the visibility function call each other and PostgreSQL stops with infinite recursion.
3. Superusers and the table owner bypass RLS. Migrations and backups rely on that.

The original proposal, kept for the record:

### 4.1 Recruiter Tenant Isolation Policy
Recruiters can only access job postings and candidate applications belonging to their employer organization:

```sql
ALTER TABLE recruitment.job_posting ENABLE ROW LEVEL SECURITY;

CREATE POLICY recruiter_org_isolation ON recruitment.job_posting
    FOR ALL
    TO talentra_app
    USING (
        organization_id = NULLIF(current_setting('app.current_org_id', TRUE), '')::BIGINT
        OR job_status = 'published' -- Candidates can view published jobs
    );
```

### 4.2 Candidate Block Exclusion Policy
If a candidate has explicitly blocked an organization or recruiter in `core.user_block`, that recruiter is barred from querying the candidate's profile:

```sql
ALTER TABLE profile.candidate_profile ENABLE ROW LEVEL SECURITY;

CREATE POLICY candidate_block_enforcement ON profile.candidate_profile
    FOR SELECT
    TO talentra_app
    USING (
        user_account_id = NULLIF(current_setting('app.current_user_id', TRUE), '')::BIGINT
        OR (
            visibility IN ('recruiters', 'public')
            AND NOT EXISTS (
                SELECT 1
                FROM core.user_block ub
                WHERE ub.blocker_user_account_id = candidate_profile.user_account_id
                  AND (
                      ub.blocked_organization_id = NULLIF(current_setting('app.current_org_id', TRUE), '')::BIGINT
                      OR ub.blocked_user_account_id = NULLIF(current_setting('app.current_user_id', TRUE), '')::BIGINT
                  )
            )
        )
    );
```

### 4.3 Consultant Sourcing Restrictions
Consultants can only submit candidate profiles to job postings that explicitly permit external agency sourcing:

```sql
CREATE OR REPLACE FUNCTION sourcing.enforce_consultant_openness()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_is_open BOOLEAN;
BEGIN
    SELECT is_open_to_consultants INTO v_is_open
    FROM sourcing.job_consultant_policy
    WHERE job_posting_id = NEW.job_posting_id;

    IF v_is_open IS NOT TRUE THEN
        RAISE EXCEPTION 'Job posting % is not open to external consultants', NEW.job_posting_id;
    END IF;
    RETURN NEW;
END;
$$;
```

*This trigger **is implemented** — see `db/migrations/016_create_sourcing_and_consultants.sql:110-133`, where it is attached as `trg_enforce_consultant_openness` on `sourcing.consultant_sourcing_request`. It is reproduced here to show the control the RLS design would complement.*

---

## 5. PII Classification & Data Masking Standards

Talentra classifies columns into four sensitivity tiers (Rule Group 6). The data dictionary currently documents **13 of 95 tables** as a representative sample; full coverage is outstanding.

| Sensitivity Tier | Definition | Examples | Storage Standard | Masking Rule for Unauthorized Views |
| :--- | :--- | :--- | :--- | :--- |
| **`[PUBLIC]`** | Non-sensitive, indexable, freely queryable | Job titles, organization names, canonical skill names, work types | Plain text, B-Tree indexed | No masking |
| **`[INTERNAL]`** | Proprietary operational data, not public | Recruiter review notes, application status history, conversion cycle times | Plain text with strict RBAC | Redacted in candidate-facing views |
| **`[PERSONAL]`** | Identifiable candidate information (GDPR Art. 4) | Full name, summary, education institutions, employer names, locations | Plain text with tenant isolation | Anonymized in blind hiring modes (`Candidate #7402`) |
| **`[SENSITIVE]`** | High-risk credentials, financial identifiers, PII | Passwords, phone numbers, email addresses, wallet balances | Salted password hash (**algorithm not enforced by the schema**), SHA-256 document checksum, E.164 normalization | Phone: `+91 98****1234`<br>Email: `c***e@example.com` |

---

## 6. Audit Trail & Anti-Tampering Immutability

### 6.1 Immutability of Audit Events
Device-limit breaches (`db/migrations/015_create_licences_and_device_limits.sql:221`) and session revocations (`:317`) are recorded in `audit.audit_event`. *Recording of logins, permission changes, profile unlocks and profile downloads is outstanding.* The actual table definition is:

```sql
CREATE TABLE audit.audit_event (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    actor_user_account_id BIGINT,
    impersonator_user_account_id BIGINT,
    action VARCHAR(80) NOT NULL,
    entity_schema VARCHAR(50) NOT NULL,
    entity_name VARCHAR(80) NOT NULL,
    entity_id BIGINT,
    old_values_json JSONB,
    new_values_json JSONB,
    client_ip VARCHAR(45),
    user_agent VARCHAR(500),
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_audit_event PRIMARY KEY (id),
    ...
);
```

### 6.2 Anti-Tamper Enforcement Trigger
Direct tampering with audit events or financial transactions is strictly prohibited by database triggers:

```sql
CREATE OR REPLACE FUNCTION audit.prevent_audit_tampering()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'Audit trail violation: UPDATE or DELETE is strictly forbidden on audit.audit_event';
END;
$$;

CREATE TRIGGER trg_prevent_audit_event_tampering
BEFORE UPDATE OR DELETE ON audit.audit_event
FOR EACH ROW EXECUTE FUNCTION audit.prevent_audit_tampering();
```

*`TRUNCATE` is blocked separately: migration 021 adds a `BEFORE TRUNCATE` statement trigger (`audit.prevent_truncate`) on the six append-only ledgers and removes the privilege from `talentra_app`. A superuser can still disable a trigger.*

---

## 7. Disaster Recovery & RPO / RTO Specifications

* **Recovery Point Objective (RPO)**: one backup interval. The repository implements logical backups via `pg_dump` with a scripted restore-and-verify procedure (`scripts/backup_restore.sh`) that restores into a staging database and compares row counts across seven tables. *Synchronous streaming replication and point-in-time recovery (PITR) are production deployment requirements; no replica, `archive_mode`, or WAL-archiving job is configured in this repository.*
* **Recovery Time Objective (RTO)**: bounded by the measured restore duration, which `scripts/backup_restore.sh` reports against a 900-second (15-minute) threshold. *Automated failover tooling such as Patroni or pg_auto_failover is not configured here.*
* **Backup & Restore Runbook**: use `scripts/backup_restore.sh`, which performs the full `pg_dump` → restore into `talentra_recovery_test` → row-count parity check → drop cycle and reports the elapsed recovery time. *Note that the script creates and then drops the `talentra_recovery_test` database.*

---

## 8. Scope and Limitations

This dossier distinguishes **implemented** controls (verifiable in `db/migrations/`) from **proposed** designs (documented here but not deployed) and from **externally certified** status (not claimed).

| Control | Status | Evidence |
|:--|:--|:--|
| Append-only triggers on `commercial.wallet_ledger`, `audit.audit_event`, `commercial.candidate_profile_download_history` | **Implemented** | `017:374-377,443-446`; `012:290-293` |
| `btree_gist` exclusion constraints (gig assignment, subscription) | **Implemented** | `014:316-321`; `017:98-101` |
| Consultant-openness trigger `trg_enforce_consultant_openness` | **Implemented** | `016:110-133` |
| Device-limit enforcement with pessimistic locking | **Implemented** | `015:167-240`; `tests/test_concurrency.py` |
| Block-state enforcement via `core.is_candidate_visible_to()` | **Implemented** (for callers of that function) | `012:336-388`; `tests/test_administration.sql:154-181` |
| Row-Level Security policies (§4) | **Implemented** (12 tables) | `021`, `022`; `tests/test_access_control.sql` |
| Least-privilege database roles (§3) | **Implemented** (5 roles; the application login role is created per environment) | `021`; `tests/test_access_control.sql` |
| Synchronous replication / PITR / automated failover (§7) | **Proposed — not implemented** | Single-service `docker-compose.yml`; `scripts/backup_restore.sh` is the implemented mechanism |
| PII masking for support staff | **Implemented** (`core.mask_email`, `core.mask_phone`, `core.support_user_account`) | `021`; `tests/test_access_control.sql` |
| Credential and session-token formats enforced by the schema | **Implemented** (argon2id/bcrypt hash; SHA-256 hex token) | `021` |
| Column classification and retention per table | **Implemented**, all pattern-based and unreviewed; periods are proposals | `024`, `020`; `tests/test_classification.sql` |
| Right to erasure | **Implemented** (`core.erase_user_account`); a scheduled job to call it is not | `020`; `tests/test_lifecycle.sql` |
| **Tax / registration identifiers (`recruitment.organization_identifier.identifier_ciphertext`, `identifier_bidx`)** | **Encrypted by the application (migration 034, DEC-25).** The database holds neither plaintext nor key. Residual risk: no consuming application yet, development key is public, canonical forms not reviewed by a domain expert | `docs/phase-2-model/12-tax-id-security-design.md`; pinned by `tests/test_classification.sql` |
| SOC 2 Type II / PCI-DSS / GDPR status | **Not claimed** | No attestation, control mapping, or gap analysis in this repository |

**Known limitations of the anti-tamper controls.** The append-only triggers block `UPDATE` and `DELETE` on the protected tables. `TRUNCATE` is blocked by a statement trigger and by revoking the privilege (migration 021). They do not constrain a privileged administrator who can `ALTER TABLE … DISABLE TRIGGER` or act as a superuser; the data generator does exactly that for one statement batch when it back-fills application history.

**Coverage gap.** This STRIDE analysis addresses the six primary categories against the transactional schemas. It does not yet cover authentication/authorization threats on the `master` and `analytics` read paths, audit-log exfiltration by a privileged administrator, availability threats specific to the GiST exclusion constraints under adversarial date-range insertion, or supply-chain threats.
