-- Test suite: tests/test_classification.sql
-- Covers: SEC-012, SEC-013; docket Rule Group 6 (sensitive data classification), Rule Group 4 (retention)
-- Prerequisite: migrations 001-024 have been applied.
-- Isolation: read-only checks, plus one rolled-back transaction.
--
-- This test is what keeps the classification honest. A migration that adds a column without calling
-- audit.sync_column_classification() fails here.

BEGIN;

DO $$
DECLARE
    v_list TEXT;
    v_n    INTEGER;
    v_caught BOOLEAN := FALSE;
BEGIN
    RAISE NOTICE '=== Column classification ===';

    -- 1. Every column of every base table is classified; nothing is classified that no longer exists
    SELECT string_agg(c.table_schema || '.' || c.table_name || '.' || c.column_name, ', ') INTO v_list
      FROM information_schema.columns c
      JOIN information_schema.tables t ON t.table_schema = c.table_schema AND t.table_name = c.table_name AND t.table_type = 'BASE TABLE'
     WHERE c.table_schema IN ('core','master','profile','recruitment','gig','commercial','sourcing','messaging','audit','analytics')
       AND NOT EXISTS (SELECT 1 FROM audit.column_classification x
                        WHERE x.schema_name = c.table_schema AND x.table_name = c.table_name AND x.column_name = c.column_name);
    IF v_list IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: unclassified columns (call audit.sync_column_classification() in the migration): %', left(v_list, 600);
    END IF;
    SELECT string_agg(x.schema_name || '.' || x.table_name || '.' || x.column_name, ', ') INTO v_list
      FROM audit.column_classification x
     WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns c
                        WHERE c.table_schema = x.schema_name AND c.table_name = x.table_name AND c.column_name = x.column_name);
    IF v_list IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: classification rows for columns that no longer exist: %', left(v_list, 600);
    END IF;
    RAISE NOTICE 'PASS: every column of every base table is classified';

    -- 2. A Sensitive column is protected, or it is a recorded, pinned risk
    v_caught := FALSE;
    BEGIN
        INSERT INTO audit.column_classification (schema_name, table_name, column_name, data_class, protection)
        VALUES ('core', 'user_account', 'pretend_secret', 'sensitive', 'none');
    EXCEPTION WHEN check_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: a Sensitive column with no protection was accepted'; END IF;

    SELECT string_agg(schema_name || '.' || table_name || '.' || column_name, ', ' ORDER BY schema_name, table_name, column_name) INTO v_list
      FROM audit.column_classification WHERE protection = 'open_risk';
    IF v_list IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: the set of known unprotected Sensitive columns changed: %. Update docs/phase-2-model/12-threat-model.md and this test deliberately.', v_list;
    END IF;
    RAISE NOTICE 'PASS: Sensitive columns are protected; no open risk remains (the tax identifier is encrypted, migration 034)';

    -- 3. Claims about protection can be checked against the catalog
    SELECT string_agg(DISTINCT x.schema_name || '.' || x.table_name, ', ') INTO v_list
      FROM audit.column_classification x
      JOIN pg_class c ON c.relname = x.table_name AND c.relnamespace = x.schema_name::regnamespace
     WHERE x.protection = 'rls' AND NOT c.relrowsecurity;
    IF v_list IS NOT NULL THEN RAISE EXCEPTION 'FAIL: classified as rls-protected but row-level security is off: %', v_list; END IF;

    SELECT string_agg(x.schema_name || '.' || x.table_name || '.' || x.column_name, ', ') INTO v_list
      FROM audit.column_classification x
     WHERE x.protection = 'hashed'
       AND NOT EXISTS (SELECT 1 FROM pg_constraint k
                        WHERE k.conrelid = (x.schema_name || '.' || x.table_name)::regclass AND k.contype = 'c'
                          AND pg_get_constraintdef(k.oid) LIKE '%' || x.column_name || '%'
                          AND (pg_get_constraintdef(k.oid) LIKE '%argon2id%' OR pg_get_constraintdef(k.oid) LIKE '%[0-9a-f]{64}%'));
    IF v_list IS NOT NULL THEN RAISE EXCEPTION 'FAIL: classified as hashed but no CHECK enforces a hash format: %', v_list; END IF;
    RAISE NOTICE 'PASS: rls and hashed claims are backed by row-level security and format constraints';

    -- 4. Every non-reference table with a personal or Sensitive column states a retention period
    SELECT string_agg(DISTINCT cc.schema_name || '.' || cc.table_name, ', ') INTO v_list
      FROM audit.column_classification cc
      JOIN audit.entity_lifecycle_policy p ON p.schema_name = cc.schema_name AND p.table_name = cc.table_name
     WHERE cc.data_class IN ('personal', 'sensitive') AND p.delete_mode <> 'reference' AND p.retention_days IS NULL;
    IF v_list IS NOT NULL THEN RAISE EXCEPTION 'FAIL: personal data without a retention period: %', v_list; END IF;
    RAISE NOTICE 'PASS: every table holding personal or Sensitive data states a retention period (all still proposals)';

    -- 5. Classification summary, for the log
    SELECT count(*) INTO v_n FROM audit.column_classification WHERE basis = 'reviewed';
    RAISE NOTICE 'NOTE: % of % classifications are human-reviewed; the rest come from name patterns',
        v_n, (SELECT count(*) FROM audit.column_classification);

    RAISE NOTICE '=== Classification tests passed ===';
END
$$;

ROLLBACK;
