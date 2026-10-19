# Talentra Security & Threat Model Dossier
**System Engine**: PostgreSQL 17  
**Framework**: STRIDE Threat Analysis & Defense-in-Depth  
**Compliance Standards**: GDPR Article 25/32, SOC 2 Type II, PCI-DSS SAQ-A  

---

## 1. Executive Security Architecture

Talentra's security architecture operates on a **Zero-Trust Relational Core** model. Security boundaries are not merely applied in the application layer; they are baked directly into PostgreSQL 17 via **granular database roles**, **cryptographic hashing standards**, **append-only ledgers**, **declarative Row-Level Security (RLS)**, and **anti-tampering triggers**.

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
          [Row-Level Security]    [Cryptographic Hashing]    [Append-Only Immutability]
          - Tenant Isolation      - Argon2id Passwords       - Anti-Tamper Triggers
          - Recruiter Org Bound   - Encrypted Tax IDs        - Correction Ledgers
          - Candidate Blocks      - SHA-256 Checksums        - Immutable Audit Events
         ===============================================================================
```

---

## 2. STRIDE Threat Analysis Matrix

| Threat Category | Potential Attack Vector | Impact Level | Architectural Mitigation & PostgreSQL Control | Verification Mechanism |
| :--- | :--- | :---: | :--- | :--- |
| **Spoofing** | Credential stuffing, brute force login, session token forgery | **Critical** | Passwords hashed using Argon2id (`$argon2id$v=19$m=65536,t=3,p=4$`). Session tokens stored as SHA-256 hashes (`session_token_hash`). Login calls `core.create_session_with_device_limit` enforcing device limit entitlements. | `tests/test_identity.sql`, `tests/test_licences.sql` |
| **Tampering** | Recruiter modifies candidate assessment score or alters credit ledger | **High** | Append-only immutability enforced by triggers (`trg_prevent_wallet_ledger_tampering`, `trg_prevent_audit_tampering`). `UPDATE` and `DELETE` on financial ledgers raise fatal PostgreSQL exceptions. Corrections require explicit self-referencing debit/credit rows. | `tests/test_commercial.sql`, `tests/test_administration.sql` |
| **Repudiation** | Client denies downloading candidate profile or spending wallet credits | **High** | Append-only audit logging in `commercial.candidate_profile_download_history` capturing downloader user ID, organization ID, wallet ledger ID, IP address, and timestamp. Cannot be altered or truncated. | `tests/test_commercial.sql`, Query 08 |
| **Information Disclosure** | Recruiter scrapes unconsented candidate phone numbers or salary history | **High** | PII data classification. Candidate phone/email masked (`+91 98****3210`) unless candidate has applied or granted explicit consent in `core.consent_record`. `core.user_block` prevents blocked entities from querying candidate profiles. | `tests/test_administration.sql`, Query 06 |
| **Denial of Service** | Malicious bot floods login to exhaust device limits or runs unindexed query | **Medium** | Rate limiting at API gateway; concurrency limits locked atomically (`FOR UPDATE`) in `core.create_session_with_device_limit`. High-volume tables partitioned by range (`candidate_application_partitioned`). All 12 operational queries backed by optimized B-Tree and GIN indexes. | `scripts/run_benchmarks.py`, Query 04 |
| **Elevation of Privilege** | External consultant attempts to source candidates for private internal jobs | **Critical** | Database trigger `trg_enforce_consultant_policy_restrictions` prevents non-consultant jobs from receiving agency submissions. Granular RBAC roles (`talentra_app`, `talentra_reporting`, `talentra_admin`). | `tests/test_sourcing.sql`, `tests/test_administration.sql` |

---

## 3. Role-Based Access Control (RBAC) & Database Roles

Talentra enforces separation of duties through distinct PostgreSQL database user roles:

```sql
-- 1. Operational Application Role (Least Privilege)
CREATE ROLE talentra_app WITH LOGIN PASSWORD '...';
GRANT USAGE ON SCHEMA core, master, profile, recruitment, gig, sourcing, commercial, messaging TO talentra_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA core, profile, recruitment, gig, sourcing, commercial, messaging TO talentra_app;
GRANT SELECT, INSERT ON TABLE commercial.wallet_ledger, commercial.candidate_profile_download_history TO talentra_app;
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

## 4. Row-Level Security (RLS) & Multi-Tenant Isolation

Talentra prevents multi-tenant data leakage by enforcing Row-Level Security policies tied to session context variables (`app.current_user_id`, `app.current_org_id`):

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
                WHERE ub.blocker_user_account_id = profile.candidate_profile.user_account_id
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
CREATE OR REPLACE FUNCTION sourcing.enforce_consultant_policy_restrictions()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_open BOOLEAN;
BEGIN
    SELECT COALESCE(is_open_to_consultants, FALSE) INTO v_open
    FROM sourcing.job_consultant_policy
    WHERE job_posting_id = NEW.job_posting_id;

    IF NOT COALESCE(v_open, FALSE) THEN
        RAISE EXCEPTION 'Agency sourcing forbidden: Job requirement ID % is not open to external consultants', NEW.job_posting_id;
    END IF;
    RETURN NEW;
END;
$$;
```

---

## 5. PII Classification & Data Masking Standards

Talentra classifies every column across all 95 tables into four sensitivity tiers (Rule Group 6):

| Sensitivity Tier | Definition | Examples | Storage Standard | Masking Rule for Unauthorized Views |
| :--- | :--- | :--- | :--- | :--- |
| **`[PUBLIC]`** | Non-sensitive, indexable, freely queryable | Job titles, organization names, canonical skill names, work types | Plain text, B-Tree indexed | No masking |
| **`[INTERNAL]`** | Proprietary operational data, not public | Recruiter review notes, application status history, conversion cycle times | Plain text with strict RBAC | Redacted in candidate-facing views |
| **`[PERSONAL]`** | Identifiable candidate information (GDPR Art. 4) | Full name, summary, education institutions, employer names, locations | Plain text with tenant isolation | Anonymized in blind hiring modes (`Candidate #7402`) |
| **`[SENSITIVE]`** | High-risk credentials, financial identifiers, PII | Passwords, phone numbers, email addresses, tax IDs, wallet balances | Salted Argon2id hash, AES-256 CBC encryption, E.164 normalization | Phone: `+91 98****1234`<br>Email: `c***e@example.com`<br>Tax: `XXXX-XX-4912` |

---

## 6. Audit Trail & Anti-Tampering Immutability

### 6.1 Immutability of Audit Events
Every security-sensitive event (login, permission change, session revocation, profile unlock, device limit breach) is recorded in `audit.audit_event`:

```sql
CREATE TABLE audit.audit_event (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_account_id BIGINT,
    organization_id BIGINT,
    event_type VARCHAR(60) NOT NULL,
    severity VARCHAR(20) NOT NULL DEFAULT 'info',
    ip_address INET,
    user_agent VARCHAR(500),
    metadata JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
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

CREATE TRIGGER trg_prevent_audit_tampering
BEFORE UPDATE OR DELETE ON audit.audit_event
FOR EACH ROW EXECUTE FUNCTION audit.prevent_audit_tampering();
```

---

## 7. Disaster Recovery & RPO / RTO Specifications

* **Recovery Point Objective (RPO)**: **0 seconds** (Zero data loss). Achieved via PostgreSQL Write-Ahead Logging (WAL) streaming replication with synchronous commit to standby replica.
* **Recovery Time Objective (RTO)**: **< 15 minutes**. Automated failover using Patroni / pg_auto_failover with point-in-time recovery (PITR) supported by continuous WAL archiving to S3.
* **Automated Backup Runbook**:
  ```bash
  # Daily Compressed Consistent Backup
  pg_dump -h 127.0.0.1 -U talentra_admin -d talentra -F c -b -v -f /backups/talentra_$(date +%Y%m%d).dump
  ```
