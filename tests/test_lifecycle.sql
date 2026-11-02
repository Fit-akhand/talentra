-- Test suite: tests/test_lifecycle.sql
-- Covers: DATA-003, SEC-003 (audit of erasure); docket Rule Group 4 (audit and lifecycle)
-- Prerequisite: migrations 001-020 have been applied.
-- Isolation: runs inside one transaction that is rolled back.

BEGIN;

DO $$
DECLARE
    v_missing TEXT;
    v_count   INTEGER;
    v_actor   BIGINT;
    v_user    BIGINT;
    v_old     BIGINT;
    v_profile BIGINT;
    v_created TIMESTAMPTZ;
    v_caught  BOOLEAN;
BEGIN
    RAISE NOTICE '=== Lifecycle: audit columns, soft delete, retention, erasure ===';

    -- 1. Every base table has a lifecycle policy row, and no policy row points at a missing table
    SELECT string_agg(n.nspname || '.' || c.relname, ', ') INTO v_missing
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE c.relkind IN ('r', 'p') AND NOT c.relispartition
       AND n.nspname IN ('core','master','profile','recruitment','gig','commercial','sourcing','messaging','audit','analytics')
       AND NOT EXISTS (SELECT 1 FROM audit.entity_lifecycle_policy p
                        WHERE p.schema_name = n.nspname AND p.table_name = c.relname);
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: tables without a lifecycle policy: %', v_missing;
    END IF;
    SELECT string_agg(p.schema_name || '.' || p.table_name, ', ') INTO v_missing
      FROM audit.entity_lifecycle_policy p
     WHERE to_regclass(quote_ident(p.schema_name) || '.' || quote_ident(p.table_name)) IS NULL;
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: policy rows for tables that do not exist: %', v_missing;
    END IF;
    RAISE NOTICE 'PASS: every base table has exactly one lifecycle policy row';

    -- 2. Rule Group 4: every table that is not append-only or derived carries all four audit columns
    SELECT string_agg(p.schema_name || '.' || p.table_name, ', ') INTO v_missing
      FROM audit.entity_lifecycle_policy p
     WHERE p.delete_mode IN ('soft', 'hard', 'reference')
       AND (SELECT count(*) FROM information_schema.columns c
             WHERE c.table_schema = p.schema_name AND c.table_name = p.table_name
               AND c.column_name IN ('created_at', 'created_by_user_account_id', 'updated_at', 'updated_by_user_account_id')) < 4;
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: tables missing audit columns: %', v_missing;
    END IF;
    RAISE NOTICE 'PASS: all soft/hard/reference tables carry created_at/by and updated_at/by';

    -- 3. Soft-deleted entities have deleted_at and an active_ view; nothing else has deleted_at
    SELECT string_agg(p.schema_name || '.' || p.table_name, ', ') INTO v_missing
      FROM audit.entity_lifecycle_policy p
     WHERE p.delete_mode = 'soft'
       AND (NOT EXISTS (SELECT 1 FROM information_schema.columns c WHERE c.table_schema = p.schema_name AND c.table_name = p.table_name AND c.column_name = 'deleted_at')
         OR to_regclass(quote_ident(p.schema_name) || '.active_' || p.table_name) IS NULL);
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: soft-deleted entities without deleted_at or active_ view: %', v_missing;
    END IF;
    SELECT string_agg(p.schema_name || '.' || p.table_name, ', ') INTO v_missing
      FROM audit.entity_lifecycle_policy p
     WHERE p.delete_mode <> 'soft'
       AND EXISTS (SELECT 1 FROM information_schema.columns c WHERE c.table_schema = p.schema_name AND c.table_name = p.table_name AND c.column_name = 'deleted_at');
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: deleted_at on an entity not classified as soft-deleted: %', v_missing;
    END IF;
    RAISE NOTICE 'PASS: soft-delete columns and active_ views match the classification';

    -- 3b. An active_ view exposes every column of its table (SELECT * is expanded once, when the view is created)
    SELECT string_agg(p.schema_name || '.active_' || p.table_name, ', ') INTO v_missing
      FROM audit.entity_lifecycle_policy p
     WHERE p.delete_mode = 'soft'
       AND (SELECT count(*) FROM information_schema.columns c WHERE c.table_schema = p.schema_name AND c.table_name = p.table_name)
        <> (SELECT count(*) FROM information_schema.columns c WHERE c.table_schema = p.schema_name AND c.table_name = 'active_' || p.table_name);
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: stale active_ views (run audit.refresh_active_views() in the migration): %', v_missing;
    END IF;
    RAISE NOTICE 'PASS: every active_ view exposes the same columns as its table';

    -- 4. Personal-data tables have a stated retention period; an approval is traceable
    SELECT string_agg(table_name, ', ') INTO v_missing
      FROM audit.entity_lifecycle_policy WHERE schema_name = 'profile' AND retention_days IS NULL
         AND delete_mode <> 'reference' AND table_name <> 'course';   -- catalogues hold no personal data
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: candidate tables without retention: %', v_missing;
    END IF;
    -- an approval has a name and a reference; the irreversible one (erasing dormant accounts) is still waiting for a person
    SELECT count(*) INTO v_count FROM audit.entity_lifecycle_policy WHERE is_retention_approved IS DISTINCT FROM (retention_approved_by IS NOT NULL);
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'FAIL: % policy rows where "approved" and "approved by" disagree', v_count;
    END IF;
    IF (SELECT is_retention_approved FROM audit.entity_lifecycle_policy WHERE schema_name = 'core' AND table_name = 'user_account') THEN
        RAISE EXCEPTION 'FAIL: erasing dormant accounts is marked approved; that needs a person (DEC-23)';
    END IF;
    v_caught := FALSE;
    BEGIN
        INSERT INTO audit.entity_lifecycle_policy (schema_name, table_name, delete_mode, retention_days)
        VALUES ('core', 'no_such_table_a', 'hard', 30);
    EXCEPTION WHEN check_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: a retention period without a basis was accepted'; END IF;
    RAISE NOTICE 'PASS: retention is stated for candidate data, approvals name their approver, and erasing dormant accounts is not approved';

    -- 5. The trigger stamps the actor and timestamps, and creation facts are immutable
    INSERT INTO core.user_account (email) VALUES ('lifecycle-actor@example.com') RETURNING id INTO v_actor;
    PERFORM set_config('app.current_user_id', v_actor::TEXT, true);
    INSERT INTO core.user_account (email) VALUES ('lifecycle-subject@example.com') RETURNING id, created_at INTO v_user, v_created;
    IF (SELECT created_by_user_account_id FROM core.user_account WHERE id = v_user) IS DISTINCT FROM v_actor THEN
        RAISE EXCEPTION 'FAIL: created_by was not stamped from app.current_user_id';
    END IF;
    UPDATE core.user_account SET preferred_language = 'hi' WHERE id = v_user;
    IF (SELECT updated_by_user_account_id FROM core.user_account WHERE id = v_user) IS DISTINCT FROM v_actor THEN
        RAISE EXCEPTION 'FAIL: updated_by was not stamped on update';
    END IF;
    UPDATE core.user_account SET created_at = created_at - interval '5 years',
                                 created_by_user_account_id = NULL WHERE id = v_user;
    IF (SELECT created_at FROM core.user_account WHERE id = v_user) <> v_created
       OR (SELECT created_by_user_account_id FROM core.user_account WHERE id = v_user) IS DISTINCT FROM v_actor THEN
        RAISE EXCEPTION 'FAIL: created_at / created_by were changed by an UPDATE';
    END IF;
    PERFORM set_config('app.current_user_id', '', true);
    RAISE NOTICE 'PASS: audit trigger stamps actor and time; created_* is immutable';

    -- 6. Erasure: identity is anonymised, sessions revoked, candidate data soft-deleted, audit event written
    INSERT INTO core.user_credential (user_account_id, credential_type, credential_identifier, secret_hash)
    VALUES (v_user, 'password', 'lifecycle-subject@example.com', '$argon2id$v=19$m=65536,t=3,p=4$abc$def');
    INSERT INTO core.user_session (user_account_id, device_identifier, session_token_hash)
    VALUES (v_user, 'lifecycle-device', encode(sha256('lifecycle-token-hash-1'::bytea), 'hex'));
    INSERT INTO profile.candidate_profile (user_account_id, headline, professional_summary)
    VALUES (v_user, 'Backend engineer', 'Ten years of PostgreSQL') RETURNING id INTO v_profile;

    PERFORM core.erase_user_account(v_user, v_actor);

    IF (SELECT email FROM core.user_account WHERE id = v_user) <> 'erased+' || v_user || '@erased.invalid' THEN
        RAISE EXCEPTION 'FAIL: email was not anonymised';
    END IF;
    IF EXISTS (SELECT 1 FROM core.active_user_account WHERE id = v_user) THEN
        RAISE EXCEPTION 'FAIL: erased user still visible in active_user_account';
    END IF;
    IF EXISTS (SELECT 1 FROM core.user_session WHERE user_account_id = v_user AND revoked_at IS NULL) THEN
        RAISE EXCEPTION 'FAIL: sessions not revoked';
    END IF;
    IF (SELECT headline FROM profile.candidate_profile WHERE id = v_profile) IS NOT NULL
       OR NOT EXISTS (SELECT 1 FROM profile.candidate_profile WHERE id = v_profile AND deleted_at IS NOT NULL) THEN
        RAISE EXCEPTION 'FAIL: candidate profile not scrubbed and soft-deleted';
    END IF;
    IF EXISTS (SELECT 1 FROM core.user_credential WHERE user_account_id = v_user AND (is_active OR secret_hash <> 'erased')) THEN
        RAISE EXCEPTION 'FAIL: credential not disabled and scrubbed';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM audit.audit_event WHERE action = 'user.erased' AND entity_id = v_user AND actor_user_account_id = v_actor) THEN
        RAISE EXCEPTION 'FAIL: erasure was not written to the audit trail';
    END IF;
    v_caught := FALSE;
    BEGIN PERFORM core.erase_user_account(v_user, v_actor);
    EXCEPTION WHEN raise_exception THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: erasing an already-erased account was accepted'; END IF;
    RAISE NOTICE 'PASS: erase_user_account anonymises, revokes, soft-deletes and audits; second call is refused';

    -- 7. Inactivity query finds an old, silent account and ignores an active one
    INSERT INTO core.user_account (email, created_at) VALUES ('lifecycle-old@example.com', now() - interval '3 years') RETURNING id INTO v_old;
    IF NOT EXISTS (SELECT 1 FROM core.find_inactive_accounts(365) WHERE user_account_id = v_old) THEN
        RAISE EXCEPTION 'FAIL: inactive account not found';
    END IF;
    IF EXISTS (SELECT 1 FROM core.find_inactive_accounts(365) WHERE user_account_id = v_actor) THEN
        RAISE EXCEPTION 'FAIL: a new account was reported as inactive';
    END IF;
    IF EXISTS (SELECT 1 FROM core.find_inactive_accounts(365) WHERE user_account_id = v_user) THEN
        RAISE EXCEPTION 'FAIL: an erased account was reported as inactive';
    END IF;
    RAISE NOTICE 'PASS: find_inactive_accounts selects only live accounts past the inactivity period';

    RAISE NOTICE '=== Lifecycle tests passed ===';
END
$$;

ROLLBACK;
