-- =============================================================================
-- Migration 025: Written justification for nullable columns that follow an exact pattern
-- Domain:        documentation in the schema (docket Rule Group 5: "Every nullable column must have a written justification")
-- Depends on:    001-024
--
-- Three kinds of nullable column have one correct explanation each, so it can be written once and applied:
--   * <verb>_by_user_account_id   the audit trigger fills it from app.current_user_id; a system job or a
--                                 migration has no user, so NULL means "no user did this"
--   * deleted_at                  NULL means the row is live
--   * <event>_at                  NULL means the event has not happened yet
--
-- Columns outside these patterns (optional descriptions, optional foreign keys, optional measurements) need a
-- human to say WHY they are optional. They are deliberately NOT given a generic comment here; the data
-- dictionary (docs/phase-2-model/07-attribute-catalogue.md) lists them as the remaining work.
-- Columns that already carry a comment are left alone.
-- =============================================================================
BEGIN;

DO $$
DECLARE
    r RECORD;
    v_text TEXT;
BEGIN
    FOR r IN
        SELECT n.nspname AS s, c.relname AS t, a.attname AS col
          FROM pg_attribute a
          JOIN pg_class c ON c.oid = a.attrelid AND c.relkind IN ('r', 'p') AND NOT c.relispartition
          JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE a.attnum > 0 AND NOT a.attisdropped AND NOT a.attnotnull
           AND n.nspname IN ('core','master','profile','recruitment','gig','commercial','sourcing','messaging','audit','analytics')
           AND col_description(c.oid, a.attnum) IS NULL
           AND (a.attname ~ '_by_user_account_id$' OR a.attname = 'deleted_at' OR a.attname ~ '_at$')
    LOOP
        v_text := CASE
            WHEN r.col IN ('created_by_user_account_id', 'updated_by_user_account_id') THEN
                'Nullable: filled from app.current_user_id by the audit trigger. NULL when a system job or migration made the change, which has no user.'
            WHEN r.col = 'deleted_by_user_account_id' THEN
                'Nullable: NULL while the row is live, and when the deletion was done by a system job (retention).'
            WHEN r.col ~ '_by_user_account_id$' THEN
                'Nullable: NULL until the action named by the column has been taken, or when a system job took it.'
            WHEN r.col = 'deleted_at' THEN
                'Nullable: NULL means the row is live. Set when the row is soft-deleted; default queries use the active_ view.'
            ELSE
                'Nullable: NULL until the event this timestamp records has happened.'
        END;
        EXECUTE format('COMMENT ON COLUMN %I.%I.%I IS %L', r.s, r.t, r.col, v_text);
    END LOOP;
END;
$$;

SELECT audit.sync_column_classification();

COMMIT;
