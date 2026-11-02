-- =============================================================================
-- Migration 021: Database roles, permissions, row-level security, credential formats
-- Domain:        security (docket section 3 "Rules You Must Honour", Rule Group 6, SEC-001/002/006/007/012/013/014)
-- Depends on:    001-020
--
-- Model
--   * The application connects as a LOGIN role that is a member of `talentra_app`
--     (created per environment, not here, so that no password lives in a migration).
--   * Per transaction the application sets who is acting:
--         SELECT set_config('app.current_user_id', '<user id>', true);
--         SELECT set_config('app.current_org_id',  '<org id>',  true);   -- optional
--     Row-level security reads those two settings. With neither set, a session sees only
--     what is public (published jobs): it fails closed.
--   * The org setting is honoured only if the user is an ACTIVE member of that organisation,
--     so a caller cannot read another tenant's rows by writing a different number.
--   * Superusers and the table owner bypass RLS by design (migrations, backups). The
--     application must never connect as either.
--
-- Row-level security is enabled on the tables where a wrong row is a breach:
--   recruitment.job_posting, recruitment.candidate_application, commercial.wallet,
--   commercial.wallet_ledger, profile.candidate_profile, core.user_credential,
--   core.user_session, core.user_device, messaging.notification_delivery.
-- Every other table is protected by grants only; that boundary is recorded in
-- docs/phase-2-model/12-threat-model.md.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Roles (group roles, NOLOGIN)
-- -----------------------------------------------------------------------------
BEGIN;

DO $$
DECLARE
    v_role TEXT;
BEGIN
    FOREACH v_role IN ARRAY ARRAY['talentra_app', 'talentra_readonly', 'talentra_auditor',
                                  'talentra_analyst', 'talentra_support']
    LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = v_role) THEN
            EXECUTE format('CREATE ROLE %I NOLOGIN', v_role);
        END IF;
    END LOOP;
END;
$$;

COMMENT ON ROLE talentra_app      IS 'Application runtime. Read/write on business data, append on logs, no DDL, no access to audit reads.';
COMMENT ON ROLE talentra_readonly IS 'Engineers and reporting tools. Read-only; no credentials, sessions or account rows.';
COMMENT ON ROLE talentra_auditor  IS 'Compliance. Read-only on the audit schema.';
COMMENT ON ROLE talentra_analyst  IS 'BI. Read-only on the analytics schema.';
COMMENT ON ROLE talentra_support  IS 'Support staff. Masked account view and tickets only.';

-- -----------------------------------------------------------------------------
-- 2. Helper functions (SECURITY DEFINER so policies can look up membership without recursion)
-- -----------------------------------------------------------------------------
CREATE FUNCTION core.is_platform_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
    SELECT EXISTS (
        SELECT 1
          FROM core.user_role ur
          JOIN core.role r ON r.id = ur.role_id
         WHERE ur.user_account_id = core.current_app_user_id()
           AND r.name IN ('super_admin', 'admin')
    );
$$;

CREATE FUNCTION core.current_org_id()
RETURNS BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
    SELECT om.organization_id
      FROM recruitment.organization_member om
     WHERE om.user_account_id = core.current_app_user_id()
       AND om.membership_status = 'active'
       AND om.organization_id = NULLIF(current_setting('app.current_org_id', true), '')::BIGINT;
$$;

CREATE FUNCTION core.owns_candidate_profile(p_candidate_profile_id BIGINT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
    SELECT EXISTS (
        SELECT 1 FROM profile.candidate_profile p
         WHERE p.id = p_candidate_profile_id
           AND p.user_account_id = core.current_app_user_id()
    );
$$;

CREATE FUNCTION recruitment.job_organization_id(p_job_posting_id BIGINT)
RETURNS BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
    SELECT organization_id FROM recruitment.job_posting WHERE id = p_job_posting_id;
$$;

COMMENT ON FUNCTION core.current_org_id() IS
    'Organisation the caller acts for: app.current_org_id, honoured only if the caller is an active member. NULL otherwise.';

-- The visibility check reads profile.candidate_profile, which now has a policy that calls this check.
-- Running it as its owner breaks that loop. It is read-only and takes no caller-controlled SQL.
ALTER FUNCTION core.is_candidate_visible_to(BIGINT, BIGINT, BIGINT)
    SECURITY DEFINER SET search_path = pg_catalog;

-- Login lookup. Before authentication there is no current user, so RLS on core.user_credential would
-- hide every row. This function is the one sanctioned way to read a password hash by identifier.
CREATE FUNCTION core.find_credential_for_login(p_identifier TEXT)
RETURNS TABLE (user_account_id BIGINT, secret_hash TEXT, algorithm VARCHAR, account_status VARCHAR)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
    SELECT c.user_account_id, c.secret_hash, c.algorithm, u.account_status
      FROM core.user_credential c
      JOIN core.user_account u ON u.id = c.user_account_id
     WHERE c.credential_type = 'password'
       AND c.credential_identifier = lower(p_identifier)
       AND c.is_active
       AND u.deleted_at IS NULL
       AND (c.expires_at IS NULL OR c.expires_at > CURRENT_TIMESTAMP);
$$;

-- -----------------------------------------------------------------------------
-- 3. Grants
-- -----------------------------------------------------------------------------
-- PostgreSQL gives EXECUTE on every new function to PUBLIC. The login lookup is SECURITY DEFINER and returns
-- password hashes, so it must be callable by the application role only.
REVOKE EXECUTE ON FUNCTION core.find_credential_for_login(TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION core.find_credential_for_login(TEXT) TO talentra_app;
-- The visibility check answers "has this candidate blocked this viewer?" for any ids it is given. Now that it runs
-- as its owner, only the application role may ask.
REVOKE EXECUTE ON FUNCTION core.is_candidate_visible_to(BIGINT, BIGINT, BIGINT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION core.is_candidate_visible_to(BIGINT, BIGINT, BIGINT) TO talentra_app;

GRANT USAGE ON SCHEMA core, master, profile, recruitment, gig, commercial, sourcing, messaging, analytics, audit
    TO talentra_app, talentra_readonly;
GRANT USAGE ON SCHEMA audit TO talentra_auditor;
GRANT USAGE ON SCHEMA analytics TO talentra_analyst;
GRANT USAGE ON SCHEMA core, messaging TO talentra_support;

-- application: read/write business data
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA core, profile, recruitment, gig, commercial, sourcing, messaging
    TO talentra_app;
GRANT SELECT ON ALL TABLES IN SCHEMA master, analytics TO talentra_app;      -- reference and derived data: read only
GRANT INSERT ON audit.audit_event, audit.system_error_log TO talentra_app;   -- logs: append only, no read
GRANT USAGE ON ALL SEQUENCES IN SCHEMA core, profile, recruitment, gig, commercial, sourcing, messaging, audit
    TO talentra_app;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA core, recruitment, commercial, sourcing, messaging, analytics TO talentra_app;

-- append-only tables: the application may add rows and read them, never change or remove them
REVOKE UPDATE, DELETE, TRUNCATE ON
    commercial.wallet_ledger, commercial.candidate_profile_download_history,
    recruitment.application_status_history, profile.profile_view_history
    FROM talentra_app;
-- reference data is read-only after seeding (BR-005)
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON ALL TABLES IN SCHEMA master FROM talentra_app;

-- read-only roles
GRANT SELECT ON ALL TABLES IN SCHEMA master, profile, recruitment, gig, commercial, sourcing, messaging, analytics, audit
    TO talentra_readonly;
GRANT SELECT ON core.role, core.permission, core.role_permission, core.user_role, core.user_device,
                core.consent_record, core.user_block TO talentra_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA audit TO talentra_auditor;
GRANT SELECT ON ALL TABLES IN SCHEMA analytics TO talentra_analyst;

-- tables created by later migrations get the same grants by default (append-only ones must be revoked explicitly)
ALTER DEFAULT PRIVILEGES IN SCHEMA core, profile, recruitment, gig, commercial, sourcing, messaging
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO talentra_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA master, analytics GRANT SELECT ON TABLES TO talentra_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA audit GRANT SELECT ON TABLES TO talentra_auditor;
ALTER DEFAULT PRIVILEGES IN SCHEMA analytics GRANT SELECT ON TABLES TO talentra_analyst;

-- -----------------------------------------------------------------------------
-- 4. Masking (Rule Group 6: Personal / Sensitive columns are masked for staff who do not need them)
-- -----------------------------------------------------------------------------
CREATE FUNCTION core.mask_email(p_email TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE WHEN p_email IS NULL THEN NULL
                WHEN position('@' IN p_email) < 2 THEN '***'
                ELSE left(p_email, 1) || '***' || substr(p_email, position('@' IN p_email)) END;
$$;

CREATE FUNCTION core.mask_phone(p_phone TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE WHEN p_phone IS NULL THEN NULL
                WHEN length(p_phone) <= 5 THEN '***'
                ELSE left(p_phone, 3) || repeat('*', length(p_phone) - 5) || right(p_phone, 2) END;
$$;

CREATE VIEW core.support_user_account AS
SELECT id,
       core.mask_email(email)    AS email_masked,
       core.mask_phone(phone_e164) AS phone_masked,
       account_status,
       created_at
  FROM core.user_account
 WHERE deleted_at IS NULL;

COMMENT ON VIEW core.support_user_account IS
    'What support staff see: masked contact details, no credentials. The only account surface granted to talentra_support.';

GRANT SELECT ON core.support_user_account TO talentra_support;
GRANT SELECT ON messaging.support_ticket TO talentra_support;
GRANT EXECUTE ON FUNCTION core.mask_email(TEXT), core.mask_phone(TEXT) TO talentra_support, talentra_app, talentra_readonly;

-- -----------------------------------------------------------------------------
-- 5. Row-level security
-- -----------------------------------------------------------------------------
-- 5.1 Job postings: public when published; otherwise only the owning organisation
ALTER TABLE recruitment.job_posting ENABLE ROW LEVEL SECURITY;
CREATE POLICY job_posting_read ON recruitment.job_posting FOR SELECT TO talentra_app
    USING ((job_status = 'published' AND deleted_at IS NULL)
           OR organization_id = core.current_org_id()
           OR core.is_platform_admin());
CREATE POLICY job_posting_write ON recruitment.job_posting FOR ALL TO talentra_app
    USING (organization_id = core.current_org_id() OR core.is_platform_admin())
    WITH CHECK (organization_id = core.current_org_id() OR core.is_platform_admin());

-- 5.2 Applications: the candidate, the employer that owns the job, or an admin
ALTER TABLE recruitment.candidate_application ENABLE ROW LEVEL SECURITY;
CREATE POLICY application_read ON recruitment.candidate_application FOR SELECT TO talentra_app
    USING (core.owns_candidate_profile(candidate_profile_id)
           OR recruitment.job_organization_id(job_posting_id) = core.current_org_id()
           OR core.is_platform_admin());
CREATE POLICY application_apply ON recruitment.candidate_application FOR INSERT TO talentra_app
    WITH CHECK (core.owns_candidate_profile(candidate_profile_id) OR core.is_platform_admin());
CREATE POLICY application_update ON recruitment.candidate_application FOR UPDATE TO talentra_app
    USING (core.owns_candidate_profile(candidate_profile_id)
           OR recruitment.job_organization_id(job_posting_id) = core.current_org_id()
           OR core.is_platform_admin())
    WITH CHECK (core.owns_candidate_profile(candidate_profile_id)
           OR recruitment.job_organization_id(job_posting_id) = core.current_org_id()
           OR core.is_platform_admin());
CREATE POLICY application_delete ON recruitment.candidate_application FOR DELETE TO talentra_app
    USING (core.is_platform_admin());

-- 5.3 Wallet and ledger: the owning organisation only
ALTER TABLE commercial.wallet ENABLE ROW LEVEL SECURITY;
CREATE POLICY wallet_org ON commercial.wallet FOR ALL TO talentra_app
    USING (organization_id = core.current_org_id() OR core.is_platform_admin())
    WITH CHECK (organization_id = core.current_org_id() OR core.is_platform_admin());

ALTER TABLE commercial.wallet_ledger ENABLE ROW LEVEL SECURITY;
CREATE POLICY wallet_ledger_read ON commercial.wallet_ledger FOR SELECT TO talentra_app
    USING (EXISTS (SELECT 1 FROM commercial.wallet w WHERE w.id = wallet_id));   -- wallet RLS applies inside
CREATE POLICY wallet_ledger_append ON commercial.wallet_ledger FOR INSERT TO talentra_app
    WITH CHECK (EXISTS (SELECT 1 FROM commercial.wallet w WHERE w.id = wallet_id));

-- 5.4 Candidate profiles: the owner, or a viewer the candidate has not blocked (docket section 3, BR-010)
ALTER TABLE profile.candidate_profile ENABLE ROW LEVEL SECURITY;
CREATE POLICY candidate_profile_read ON profile.candidate_profile FOR SELECT TO talentra_app
    USING (user_account_id = core.current_app_user_id()
           OR core.is_platform_admin()
           OR (deleted_at IS NULL
               AND visibility IN ('recruiters', 'public')
               AND core.is_candidate_visible_to(id, core.current_app_user_id(), core.current_org_id())))
    ;
CREATE POLICY candidate_profile_write ON profile.candidate_profile FOR ALL TO talentra_app
    USING (user_account_id = core.current_app_user_id() OR core.is_platform_admin())
    WITH CHECK (user_account_id = core.current_app_user_id() OR core.is_platform_admin());

-- 5.5 Credentials and sessions: the owner only
ALTER TABLE core.user_credential ENABLE ROW LEVEL SECURITY;
CREATE POLICY credential_owner ON core.user_credential FOR ALL TO talentra_app
    USING (user_account_id = core.current_app_user_id() OR core.is_platform_admin())
    WITH CHECK (user_account_id = core.current_app_user_id() OR core.is_platform_admin());

ALTER TABLE core.user_session ENABLE ROW LEVEL SECURITY;
CREATE POLICY session_owner ON core.user_session FOR ALL TO talentra_app
    USING (user_account_id = core.current_app_user_id() OR core.is_platform_admin())
    WITH CHECK (user_account_id = core.current_app_user_id() OR core.is_platform_admin());

-- 5.5b Registered devices: the owner only
ALTER TABLE core.user_device ENABLE ROW LEVEL SECURITY;
CREATE POLICY device_owner ON core.user_device FOR ALL TO talentra_app
    USING (user_account_id = core.current_app_user_id() OR core.is_platform_admin())
    WITH CHECK (user_account_id = core.current_app_user_id() OR core.is_platform_admin());

-- 5.6 Notifications: the recipient reads them; the platform may create them for anyone
ALTER TABLE messaging.notification_delivery ENABLE ROW LEVEL SECURITY;
CREATE POLICY notification_recipient ON messaging.notification_delivery FOR SELECT TO talentra_app
    USING (recipient_user_account_id = core.current_app_user_id() OR core.is_platform_admin());
CREATE POLICY notification_create ON messaging.notification_delivery FOR INSERT TO talentra_app
    WITH CHECK (TRUE);
CREATE POLICY notification_update ON messaging.notification_delivery FOR UPDATE TO talentra_app
    USING (recipient_user_account_id = core.current_app_user_id() OR core.is_platform_admin());

-- -----------------------------------------------------------------------------
-- 6. TRUNCATE is not stopped by the row-level tamper triggers: block it on every append-only ledger
-- -----------------------------------------------------------------------------
CREATE FUNCTION audit.prevent_truncate()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'TRUNCATE is not permitted on append-only table %.%', TG_TABLE_SCHEMA, TG_TABLE_NAME
        USING ERRCODE = 'restrict_violation';
END;
$$;

DO $$
DECLARE
    v_table TEXT;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'audit.audit_event', 'audit.system_error_log', 'commercial.wallet_ledger',
        'commercial.candidate_profile_download_history', 'recruitment.application_status_history',
        'profile.profile_view_history']
    LOOP
        EXECUTE format('CREATE TRIGGER %I BEFORE TRUNCATE ON %s FOR EACH STATEMENT EXECUTE FUNCTION audit.prevent_truncate()',
                       'trg_' || split_part(v_table, '.', 2) || '_block_truncate', v_table);
    END LOOP;
END;
$$;

-- -----------------------------------------------------------------------------
-- 7. Credential and token formats (SEC-006, SEC-007)
-- -----------------------------------------------------------------------------
-- Password hashes must be argon2id or bcrypt. 'erased' is the marker core.erase_user_account writes.
ALTER TABLE core.user_credential
    ADD CONSTRAINT ck_user_credential_password_hash_format
    CHECK (credential_type <> 'password'
           OR secret_hash ~ '^\$(argon2id|2a|2b)\$'
           OR secret_hash = 'erased');

-- core.user_account.password_hash duplicates core.user_credential and is deprecated; it must still be a real hash.
ALTER TABLE core.user_account
    ADD CONSTRAINT ck_user_account_password_hash_format
    CHECK (password_hash IS NULL OR password_hash ~ '^\$(argon2id|2a|2b)\$');
COMMENT ON COLUMN core.user_account.password_hash IS
    'DEPRECATED: use core.user_credential. Kept for backward compatibility; must be NULL or an argon2id/bcrypt hash.';

-- Session tokens are stored only as a SHA-256 digest: 64 lowercase hex characters.
ALTER TABLE core.user_session
    ADD CONSTRAINT ck_user_session_token_hash_sha256
    CHECK (session_token_hash ~ '^[0-9a-f]{64}$');

-- -----------------------------------------------------------------------------
-- 8. Permission catalogue and role mapping (SEC-001)
-- -----------------------------------------------------------------------------
INSERT INTO core.permission (code, name, module, description) VALUES
 ('user.manage',            'Manage user accounts',            'identity',    'Create, suspend and reactivate accounts'),
 ('user.erase',             'Erase a user account',            'identity',    'Run the right-to-erasure procedure'),
 ('session.revoke_any',     'Revoke any session or device',    'identity',    'Revoke sessions of other users'),
 ('profile.manage_own',     'Manage own candidate profile',    'profile',     'Create and edit own profile, resume and documents'),
 ('job.search',             'Search published jobs',           'recruitment', 'Read published job postings'),
 ('job.post',               'Post and manage jobs',            'recruitment', 'Create and edit job postings of own organisation'),
 ('job.moderate',           'Moderate job postings',           'recruitment', 'Close or reject any posting'),
 ('application.apply',      'Apply to jobs',                   'recruitment', 'Create an application and track own applications'),
 ('application.review',     'Review applications',             'recruitment', 'Move applications through the pipeline for own organisation'),
 ('candidate.search',       'Search candidates',               'profile',     'Search profiles visible to the caller'),
 ('candidate.download',     'Download candidate profiles',     'commercial',  'Download a profile; deducts credits'),
 ('outreach.send',          'Send outreach',                   'sourcing',    'Bulk outreach to candidates; deducts credits'),
 ('sourcing.manage',        'Manage sourcing requests',        'sourcing',    'Accept or decline consultant requests'),
 ('sourcing.submit',        'Submit candidates for jobs',      'sourcing',    'Consultant submissions to consultant-open jobs'),
 ('gig.request',            'Post gig requests',               'gig',         'Create gig requests and decide applications'),
 ('gig.apply',              'Apply to gigs',                   'gig',         'Gig worker applications'),
 ('gig.rate',               'Rate completed gigs',             'gig',         'Requester ratings'),
 ('wallet.view',            'View wallet balance',             'commercial',  'Read wallet and ledger of own organisation'),
 ('wallet.manage',          'Recharge and manage wallet',      'commercial',  'Recharge, refund and correct entries'),
 ('licence.manage',         'Manage licences and seats',       'commercial',  'Allocate seats, set device limits'),
 ('organization.manage',    'Manage organisation',             'recruitment', 'Members, locations, identifiers'),
 ('organization.verify',    'Verify organisations',            'recruitment', 'Approve registration and tax verification'),
 ('audit.read_own_org',     'Read own organisation audit log', 'audit',       'Audit events of the caller''s organisation'),
 ('audit.read_all',         'Read the full audit log',         'audit',       'Platform-wide audit events'),
 ('support.create',         'Raise a support ticket',          'messaging',   'Create and read own tickets'),
 ('support.manage',         'Work support tickets',            'messaging',   'Assign and resolve any ticket'),
 ('campus.manage',          'Manage campus hiring',            'recruitment', 'Placement officer campus drives'),
 ('masterdata.manage',      'Maintain reference data',         'master',      'Change cities, skills, qualifications'),
 ('kpi.view',               'View KPI reports',                'analytics',   'Read KPI and analytics outputs');

INSERT INTO core.role_permission (role_id, permission_id)
SELECT r.id, p.id
  FROM (VALUES
    ('super_admin',       '*'),
    ('admin',             '*-user.erase-audit.read_all-masterdata.manage'),
    ('account_admin',     'job.search job.post application.review candidate.search candidate.download outreach.send sourcing.manage gig.request wallet.view wallet.manage licence.manage organization.manage audit.read_own_org support.create kpi.view'),
    ('guest',             'job.search'),
    ('candidate',         'profile.manage_own job.search application.apply gig.apply support.create'),
    ('employer',          'job.search job.post application.review candidate.search candidate.download outreach.send sourcing.manage gig.request gig.rate wallet.view support.create kpi.view'),
    ('recruiter',         'job.search job.post application.review candidate.search candidate.download outreach.send sourcing.manage wallet.view support.create'),
    ('consultant',        'job.search candidate.search candidate.download outreach.send sourcing.submit support.create'),
    ('placement_officer', 'job.search candidate.search campus.manage support.create')
  ) AS m (role_name, spec)
  JOIN core.role r ON r.name = m.role_name
  JOIN core.permission p ON
       CASE
         WHEN m.spec = '*' THEN TRUE
         WHEN m.spec LIKE '*-%' THEN p.code <> ALL (string_to_array(substr(m.spec, 3), '-'))
         ELSE p.code = ANY (string_to_array(m.spec, ' '))
       END;

COMMIT;
