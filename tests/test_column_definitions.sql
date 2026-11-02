-- Test suite: tests/test_column_definitions.sql
-- Covers: NFR-024 (every column is defined; every nullable column says what NULL means); docket data-dictionary rule
-- Prerequisite: migrations 001-033 have been applied.
-- Isolation: read-only checks on the catalog.

BEGIN;

DO $$
DECLARE
    v_undefined TEXT;
    v_unexplained TEXT;
BEGIN
    SELECT string_agg(n.nspname || '.' || c.relname || '.' || a.attname, ', ' ORDER BY n.nspname, c.relname, a.attnum) INTO v_undefined
      FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid AND c.relkind IN ('r','p') AND NOT c.relispartition
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname IN ('core','master','profile','recruitment','gig','commercial','sourcing','messaging','audit','analytics')
       AND a.attnum > 0 AND NOT a.attisdropped AND coalesce(length(col_description(c.oid, a.attnum)), 0) < 10;
    IF v_undefined IS NOT NULL THEN RAISE EXCEPTION 'FAIL: columns without a definition: %', v_undefined; END IF;

    SELECT string_agg(n.nspname || '.' || c.relname || '.' || a.attname, ', ' ORDER BY n.nspname, c.relname, a.attnum) INTO v_unexplained
      FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid AND c.relkind IN ('r','p') AND NOT c.relispartition
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname IN ('core','master','profile','recruitment','gig','commercial','sourcing','messaging','audit','analytics')
       AND a.attnum > 0 AND NOT a.attisdropped AND NOT a.attnotnull
       AND col_description(c.oid, a.attnum) !~ 'NULL|Nullable|Optional';
    IF v_unexplained IS NOT NULL THEN RAISE EXCEPTION 'FAIL: nullable columns that do not say what NULL means: %', v_unexplained; END IF;
    RAISE NOTICE 'PASS: every column is defined and every nullable column explains NULL';
END $$;

ROLLBACK;
