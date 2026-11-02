-- =============================================================================
-- Migration 020: Audit columns, soft delete, lifecycle policy and account erasure
-- Domain:        cross-cutting (docket Rule Group 4: Audit and lifecycle)
-- Depends on:    001-019
--
-- What this migration does
--   1. Adds created_at / created_by / updated_at / updated_by to every business table
--      that lacks them, and keeps them correct with one trigger function.
--   2. Adds deleted_at / deleted_by to the entities that are soft-deleted, and one
--      `active_<table>` view per soft-deleted entity that excludes deleted rows.
--   3. Records, for every table, how rows leave it (soft, hard, append-only,
--      reference, derived) and, where it holds personal or financial data, the
--      proposed retention period: audit.entity_lifecycle_policy.
--   4. Adds core.erase_user_account (right to erasure) and
--      core.find_inactive_accounts (the query a scheduled retention job runs).
--
-- Who is the actor?
--   The database cannot know the application user. The access layer sets
--   `SET LOCAL app.current_user_id = '<core.user_account.id>'` at the start of each
--   transaction. When it is unset the *_by columns stay NULL: they are nullable on
--   purpose, because system jobs and migrations have no user.
--
-- Naming: the *_by columns are foreign keys to core.user_account, so they follow the
--   docket's "<referenced table>_id" rule: created_by_user_account_id.
-- Views:  `active_<table>` in the same schema as the table.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Actor helper and audit-column trigger function
-- -----------------------------------------------------------------------------
BEGIN;

CREATE FUNCTION core.current_app_user_id()
RETURNS BIGINT
LANGUAGE sql
STABLE
AS $$
    SELECT NULLIF(current_setting('app.current_user_id', true), '')::BIGINT;
$$;

COMMENT ON FUNCTION core.current_app_user_id() IS
    'Application user for this transaction, from SET LOCAL app.current_user_id. NULL for system jobs.';

CREATE FUNCTION core.maintain_audit_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_user_id BIGINT := core.current_app_user_id();
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.created_at := COALESCE(NEW.created_at, CURRENT_TIMESTAMP);
        NEW.created_by_user_account_id := COALESCE(NEW.created_by_user_account_id, v_user_id);
        NEW.updated_at := COALESCE(NEW.updated_at, NEW.created_at);
        -- creation is the first update: when nobody else is named, the creator is also the last updater
        NEW.updated_by_user_account_id := COALESCE(NEW.updated_by_user_account_id, v_user_id, NEW.created_by_user_account_id);
    ELSE
        -- creation facts are immutable; update facts are always set by the database
        NEW.created_at := OLD.created_at;
        NEW.created_by_user_account_id := OLD.created_by_user_account_id;
        NEW.updated_at := CURRENT_TIMESTAMP;
        NEW.updated_by_user_account_id := COALESCE(v_user_id, NEW.updated_by_user_account_id);
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION core.maintain_audit_columns() IS
    'BEFORE INSERT OR UPDATE trigger: stamps created_*/updated_* and makes created_* immutable.';

-- -----------------------------------------------------------------------------
-- 2. Lifecycle policy table: how each entity's rows leave the system
-- -----------------------------------------------------------------------------
CREATE TABLE audit.entity_lifecycle_policy (
    id                      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    schema_name             VARCHAR(63)  NOT NULL,
    table_name              VARCHAR(63)  NOT NULL,
    delete_mode             VARCHAR(12)  NOT NULL,
    retention_days          INTEGER,
    retention_basis         VARCHAR(200),
    is_retention_approved   BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at              TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by_user_account_id BIGINT,
    updated_at              TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by_user_account_id BIGINT,

    CONSTRAINT uq_entity_lifecycle_policy_table
        UNIQUE (schema_name, table_name),
    CONSTRAINT ck_entity_lifecycle_policy_delete_mode
        CHECK (delete_mode IN ('soft', 'hard', 'append_only', 'reference', 'derived')),
    CONSTRAINT ck_entity_lifecycle_policy_retention_days
        CHECK (retention_days IS NULL OR retention_days > 0),
    -- a retention period without a stated basis is a number nobody can defend
    CONSTRAINT ck_entity_lifecycle_policy_retention_basis
        CHECK (retention_days IS NULL OR retention_basis IS NOT NULL),
    CONSTRAINT fk_entity_lifecycle_policy_created_by
        FOREIGN KEY (created_by_user_account_id) REFERENCES core.user_account (id)
        ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_entity_lifecycle_policy_updated_by
        FOREIGN KEY (updated_by_user_account_id) REFERENCES core.user_account (id)
        ON UPDATE RESTRICT ON DELETE RESTRICT
);

COMMENT ON TABLE audit.entity_lifecycle_policy IS
    'One row per base table: soft/hard/append-only/reference/derived, plus retention. Completeness is asserted by tests/test_lifecycle.sql.';
COMMENT ON COLUMN audit.entity_lifecycle_policy.retention_days IS
    'NULL = no retention limit defined. Counted from last activity for personal data, from creation for records.';
COMMENT ON COLUMN audit.entity_lifecycle_policy.is_retention_approved IS
    'FALSE until the data owner / legal approves the period. Every period seeded here is a proposal.';

-- -----------------------------------------------------------------------------
-- 3. Add the audit columns where missing; attach the trigger
--    Excluded: append-only tables (they carry their own recorded_at and must never be
--    updated) and derived analytics tables (rebuilt from operational data).
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    r RECORD;
    v_append_only TEXT[] := ARRAY[
        'audit.audit_event', 'audit.system_error_log',
        'commercial.wallet_ledger', 'commercial.candidate_profile_download_history',
        'recruitment.application_status_history', 'profile.profile_view_history',
        'analytics.fact_application_event', 'analytics.fact_gig_performance',
        'analytics.fact_wallet_transaction'
    ];
BEGIN
    FOR r IN
        SELECT n.nspname AS s, c.relname AS t
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relkind IN ('r', 'p')
          AND NOT c.relispartition
          AND n.nspname IN ('core', 'master', 'profile', 'recruitment', 'gig',
                            'commercial', 'sourcing', 'messaging', 'audit')
          AND (n.nspname || '.' || c.relname) <> ALL (v_append_only)
        ORDER BY 1, 2
    LOOP
        EXECUTE format('ALTER TABLE %I.%I ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP', r.s, r.t);
        EXECUTE format('ALTER TABLE %I.%I ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP', r.s, r.t);

        IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                       WHERE table_schema = r.s AND table_name = r.t AND column_name = 'created_by_user_account_id') THEN
            EXECUTE format('ALTER TABLE %I.%I ADD COLUMN created_by_user_account_id BIGINT', r.s, r.t);
            EXECUTE format('ALTER TABLE %I.%I ADD CONSTRAINT %I FOREIGN KEY (created_by_user_account_id) REFERENCES core.user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT',
                           r.s, r.t, 'fk_' || r.t || '_created_by');
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                       WHERE table_schema = r.s AND table_name = r.t AND column_name = 'updated_by_user_account_id') THEN
            EXECUTE format('ALTER TABLE %I.%I ADD COLUMN updated_by_user_account_id BIGINT', r.s, r.t);
            EXECUTE format('ALTER TABLE %I.%I ADD CONSTRAINT %I FOREIGN KEY (updated_by_user_account_id) REFERENCES core.user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT',
                           r.s, r.t, 'fk_' || r.t || '_updated_by');
        END IF;

        EXECUTE format('CREATE TRIGGER %I BEFORE INSERT OR UPDATE ON %I.%I FOR EACH ROW EXECUTE FUNCTION core.maintain_audit_columns()',
                       'trg_' || r.t || '_audit_columns', r.s, r.t);
    END LOOP;
END;
$$;

-- -----------------------------------------------------------------------------
-- 4. Soft delete: columns and default-query views
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT split_part(x, '.', 1) AS s, split_part(x, '.', 2) AS t
        FROM unnest(ARRAY[
            'core.user_account', 'profile.candidate_profile', 'profile.candidate_document',
            'recruitment.organization', 'recruitment.job_posting',
            'gig.gig_worker_profile', 'gig.gig_request',
            'messaging.community_post', 'messaging.support_ticket'
        ]) AS x
    LOOP
        EXECUTE format('ALTER TABLE %I.%I ADD COLUMN deleted_at TIMESTAMPTZ', r.s, r.t);
        EXECUTE format('ALTER TABLE %I.%I ADD COLUMN deleted_by_user_account_id BIGINT', r.s, r.t);
        EXECUTE format('ALTER TABLE %I.%I ADD CONSTRAINT %I FOREIGN KEY (deleted_by_user_account_id) REFERENCES core.user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT',
                       r.s, r.t, 'fk_' || r.t || '_deleted_by');
        -- a deletion actor without a deletion time is meaningless
        EXECUTE format('ALTER TABLE %I.%I ADD CONSTRAINT %I CHECK (deleted_by_user_account_id IS NULL OR deleted_at IS NOT NULL)',
                       r.s, r.t, 'ck_' || r.t || '_deleted_pair');
        EXECUTE format('CREATE VIEW %I.%I AS SELECT * FROM %I.%I WHERE deleted_at IS NULL',
                       r.s, 'active_' || r.t, r.s, r.t);
        EXECUTE format('COMMENT ON VIEW %I.%I IS %L', r.s, 'active_' || r.t,
                       'Default query surface: ' || r.t || ' without soft-deleted rows.');
    END LOOP;
END;
$$;

-- -----------------------------------------------------------------------------
-- 5. Populate the lifecycle policy for every base table
-- -----------------------------------------------------------------------------
INSERT INTO audit.entity_lifecycle_policy (schema_name, table_name, delete_mode)
SELECT n.nspname, c.relname,
       CASE
         WHEN (n.nspname || '.' || c.relname) IN (
              'audit.audit_event', 'audit.system_error_log',
              'commercial.wallet_ledger', 'commercial.candidate_profile_download_history',
              'recruitment.application_status_history', 'profile.profile_view_history',
              'analytics.fact_application_event', 'analytics.fact_gig_performance',
              'analytics.fact_wallet_transaction')                       THEN 'append_only'
         WHEN (n.nspname || '.' || c.relname) IN (
              'core.user_account', 'profile.candidate_profile', 'profile.candidate_document',
              'recruitment.organization', 'recruitment.job_posting',
              'gig.gig_worker_profile', 'gig.gig_request',
              'messaging.community_post', 'messaging.support_ticket')    THEN 'soft'
         WHEN n.nspname = 'master'                                       THEN 'reference'
         WHEN c.relname LIKE 'dim\_%'                                    THEN 'derived'
         ELSE 'hard'
       END
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'p')
  AND NOT c.relispartition
  AND n.nspname IN ('core', 'master', 'profile', 'recruitment', 'gig', 'commercial',
                    'sourcing', 'messaging', 'audit', 'analytics');

-- Proposed retention. Every figure is a PROPOSAL: is_retention_approved stays FALSE until the
-- data owner approves it (docket Rule Group 4 asks that the rule be stated per entity).
UPDATE audit.entity_lifecycle_policy SET
    retention_days  = 730,
    retention_basis = 'Proposed: candidate personal data, erase after 24 months of account inactivity'
WHERE schema_name = 'profile';

UPDATE audit.entity_lifecycle_policy SET
    retention_days  = 730,
    retention_basis = 'Proposed: account and identity data, erase after 24 months of inactivity or on request'
WHERE (schema_name, table_name) IN
      (('core', 'user_account'), ('core', 'user_credential'), ('core', 'user_device'),
       ('core', 'consent_record'), ('core', 'user_block'));

UPDATE audit.entity_lifecycle_policy SET
    retention_days  = 90,
    retention_basis = 'Proposed: session and login history, 90 days'
WHERE (schema_name, table_name) = ('core', 'user_session');

UPDATE audit.entity_lifecycle_policy SET
    retention_days  = 180,
    retention_basis = 'Proposed: delivery records beyond what audit needs, 180 days'
WHERE (schema_name, table_name) IN (('messaging', 'notification_delivery'), ('sourcing', 'outreach_recipient'));

UPDATE audit.entity_lifecycle_policy SET
    retention_days  = 2555,
    retention_basis = 'Proposed: financial and audit records, 7 years'
WHERE (schema_name, table_name) IN
      (('commercial', 'wallet_ledger'), ('commercial', 'payment_order'), ('commercial', 'invoice'),
       ('commercial', 'payment_refund'), ('commercial', 'candidate_profile_download_history'),
       ('audit', 'audit_event'));

-- -----------------------------------------------------------------------------
-- 6. Right to erasure and the inactivity query
-- -----------------------------------------------------------------------------
CREATE FUNCTION core.erase_user_account(p_user_account_id BIGINT, p_requested_by BIGINT DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_now TIMESTAMPTZ := CURRENT_TIMESTAMP;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM core.user_account WHERE id = p_user_account_id AND deleted_at IS NULL) THEN
        RAISE EXCEPTION 'User account % does not exist or is already erased', p_user_account_id;
    END IF;

    -- identity: keep the row (other tables reference it) but remove everything that identifies the person
    UPDATE core.user_account
       SET email = 'erased+' || id || '@erased.invalid',
           phone_e164 = NULL,
           phone_country_code = NULL,
           password_hash = NULL,
           account_status = 'deactivated',
           deleted_at = v_now,
           deleted_by_user_account_id = COALESCE(p_requested_by, p_user_account_id)
     WHERE id = p_user_account_id;

    UPDATE core.user_credential
       SET is_active = FALSE,
           credential_identifier = 'erased:' || id,
           secret_hash = 'erased'
     WHERE user_account_id = p_user_account_id;

    UPDATE core.user_session
       SET revoked_at = v_now, ended_at = COALESCE(ended_at, v_now)
     WHERE user_account_id = p_user_account_id AND ended_at IS NULL AND revoked_at IS NULL;

    -- candidate data
    UPDATE profile.candidate_profile
       SET headline = NULL, professional_summary = NULL, visibility = 'private',
           deleted_at = v_now, deleted_by_user_account_id = COALESCE(p_requested_by, p_user_account_id)
     WHERE user_account_id = p_user_account_id AND deleted_at IS NULL;

    -- documents live in external object storage: mark them for the storage sweeper
    UPDATE profile.candidate_document d
       SET document_status = 'archived', archived_at = v_now,
           deleted_at = v_now, deleted_by_user_account_id = COALESCE(p_requested_by, p_user_account_id)
      FROM profile.candidate_profile p
     WHERE d.candidate_profile_id = p.id AND p.user_account_id = p_user_account_id AND d.deleted_at IS NULL;

    -- the erasure itself is a sensitive action
    INSERT INTO audit.audit_event (actor_user_account_id, action, entity_schema, entity_name, entity_id)
    VALUES (COALESCE(p_requested_by, p_user_account_id), 'user.erased', 'core', 'user_account', p_user_account_id);
END;
$$;

COMMENT ON FUNCTION core.erase_user_account(BIGINT, BIGINT) IS
    'Right to erasure: anonymises identity, revokes sessions, soft-deletes candidate data, writes an audit event. Financial and audit rows are retained by policy.';

CREATE FUNCTION core.find_inactive_accounts(p_inactive_days INTEGER DEFAULT NULL)
RETURNS TABLE (user_account_id BIGINT, last_activity_at TIMESTAMPTZ)
LANGUAGE sql
STABLE
AS $$
    WITH policy AS (
        SELECT COALESCE(p_inactive_days,
                        (SELECT retention_days FROM audit.entity_lifecycle_policy
                          WHERE schema_name = 'core' AND table_name = 'user_account')) AS days
    )
    SELECT u.id,
           GREATEST(u.created_at, COALESCE(MAX(s.last_activity_at), u.created_at)) AS last_activity_at
      FROM core.user_account u
      LEFT JOIN core.user_session s ON s.user_account_id = u.id
     WHERE u.deleted_at IS NULL
     GROUP BY u.id, u.created_at
    HAVING GREATEST(u.created_at, COALESCE(MAX(s.last_activity_at), u.created_at))
           < CURRENT_TIMESTAMP - make_interval(days => (SELECT days FROM policy));
$$;

COMMENT ON FUNCTION core.find_inactive_accounts(INTEGER) IS
    'Accounts with no session activity within the retention period. A scheduled job calls core.erase_user_account for each row.';

COMMIT;
