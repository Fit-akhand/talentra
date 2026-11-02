-- 035: lookup rows for enumerations (docket Rule Group 3: "any fixed set of values is held in a lookup table with a code,
-- a display name per supported UI language, an active flag and a sort order").
--
-- Decision DEC-27 (Delegated, 2026-10-28; docs/lifecycle/decision-log.md): the CHECK constraints stay the authority on which
-- values a column accepts, because triggers and queries branch on those values and a data edit must not be able to add one.
-- This table mirrors them so that the interface can list, order and label every allowed value, and tests/test_enumerations.sql
-- fails whenever the two drift apart. Display names are ordinary translations (messaging.ui_translation), so a language is added
-- by inserting rows, and an untranslated language falls back to English through messaging.get_ui_translation.

BEGIN;

CREATE TABLE master.enumeration_value (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    column_ref    VARCHAR(150) NOT NULL,     -- schema.table.column the value belongs to
    code          VARCHAR(80)  NOT NULL,     -- the stored value
    sort_order    INTEGER      NOT NULL,
    is_active     BOOLEAN      NOT NULL DEFAULT TRUE,

    CONSTRAINT uq_enumeration_value UNIQUE (column_ref, code),
    CONSTRAINT ck_enumeration_value_ref CHECK (column_ref ~ '^[a-z_]+\.[a-z0-9_]+\.[a-z0-9_]+$'),
    CONSTRAINT ck_enumeration_value_code CHECK (length(btrim(code)) >= 1),
    CONSTRAINT ck_enumeration_value_sort CHECK (sort_order >= 1)
);
COMMENT ON TABLE master.enumeration_value IS 'Every value a CHECK-constrained column accepts, with order and active flag. Mirrors the CHECK constraints (which stay authoritative); display names are messaging.ui_translation rows keyed enum.<schema>.<table>.<column>.<code>.';
COMMENT ON COLUMN master.enumeration_value.column_ref IS 'schema.table.column whose CHECK constraint lists this value.';
COMMENT ON COLUMN master.enumeration_value.code IS 'The value as stored in the column.';
COMMENT ON COLUMN master.enumeration_value.sort_order IS 'Position when the values are listed, starting at 1; follows the order in the CHECK constraint, which lists them in lifecycle order where there is one.';
COMMENT ON COLUMN master.enumeration_value.is_active IS 'False when the CHECK constraint no longer accepts the value; the row is kept so old data can still be labelled.';
SELECT audit.apply_standard_lifecycle('master', 'enumeration_value', 'reference');
COMMENT ON COLUMN master.enumeration_value.id IS 'Surrogate primary key (64-bit identity). Never reused, never shown to users.';
COMMENT ON COLUMN master.enumeration_value.created_at IS 'When the row was created (UTC). Set by trigger and never changed.';
COMMENT ON COLUMN master.enumeration_value.updated_at IS 'When the row was last changed (UTC). Set by trigger.';
COMMENT ON COLUMN master.enumeration_value.created_by_user_account_id IS 'Account that created the row, taken from the session. NULL when the system created it (seed, migration, scheduled job).';
COMMENT ON COLUMN master.enumeration_value.updated_by_user_account_id IS 'Account that last changed the row, taken from the session. NULL when the system changed it.';
CREATE INDEX idx_enumeration_value_ref ON master.enumeration_value (column_ref, sort_order);

-- Re-reads the CHECK constraints. Run it after any migration that adds or removes an allowed value.
CREATE FUNCTION master.sync_enumeration_values()
RETURNS TABLE (added INTEGER, deactivated INTEGER, labelled INTEGER)
LANGUAGE plpgsql
AS $$
DECLARE
    v_added INTEGER; v_off INTEGER; v_lab INTEGER;
BEGIN
    DROP TABLE IF EXISTS tmp_enum_found;
    CREATE TEMP TABLE tmp_enum_found ON COMMIT DROP AS
    WITH c AS (
        SELECT n.nspname AS s, r.relname AS t, pg_get_constraintdef(k.oid) AS d
          FROM pg_constraint k JOIN pg_class r ON r.oid = k.conrelid JOIN pg_namespace n ON n.oid = r.relnamespace
         WHERE k.contype = 'c' AND NOT r.relispartition AND r.relkind IN ('r', 'p')
           AND n.nspname IN ('core','master','profile','recruitment','gig','commercial','sourcing','messaging','audit','analytics')
    ), m AS (
        SELECT s, t, (regexp_matches(d, '\(+(\w+)\)+(?:::\w+)* = ANY \(+ARRAY\[([^\]]*)\]', 'g')) AS x FROM c
    ), v AS (
        SELECT s || '.' || t || '.' || x[1] AS column_ref, y.code, y.ord
          FROM m CROSS JOIN LATERAL (
              SELECT (regexp_matches(e.item, '^''(.*)''::', ''))[1] AS code, e.ord
                FROM regexp_split_to_table(x[2], ', ') WITH ORDINALITY AS e(item, ord)) y
         WHERE y.code IS NOT NULL
    )
    SELECT DISTINCT ON (column_ref, code) column_ref, code, ord::INTEGER AS ord FROM v ORDER BY column_ref, code, ord;

    INSERT INTO master.enumeration_value (column_ref, code, sort_order)
    SELECT column_ref, code, ord FROM tmp_enum_found
    ON CONFLICT (column_ref, code) DO UPDATE SET sort_order = EXCLUDED.sort_order, is_active = TRUE
      WHERE (master.enumeration_value.sort_order, master.enumeration_value.is_active) IS DISTINCT FROM (EXCLUDED.sort_order, TRUE);
    GET DIAGNOSTICS v_added = ROW_COUNT;

    UPDATE master.enumeration_value e SET is_active = FALSE
     WHERE e.is_active AND NOT EXISTS (SELECT 1 FROM tmp_enum_found f WHERE f.column_ref = e.column_ref AND f.code = e.code);
    GET DIAGNOSTICS v_off = ROW_COUNT;

    -- an English display name for every value that has none; a person improves the wording, a translator adds the other languages
    INSERT INTO messaging.ui_translation (string_key, language_code, translated_text)
    SELECT 'enum.' || e.column_ref || '.' || lower(regexp_replace(e.code, '[^A-Za-z0-9]+', '_', 'g')), 'en',
           upper(left(replace(e.code, '_', ' '), 1)) || substr(replace(e.code, '_', ' '), 2)
      FROM master.enumeration_value e
     WHERE e.is_active
    ON CONFLICT (string_key, language_code) DO NOTHING;
    GET DIAGNOSTICS v_lab = ROW_COUNT;

    RETURN QUERY SELECT v_added, v_off, v_lab;
END;
$$;
COMMENT ON FUNCTION master.sync_enumeration_values() IS 'Mirrors the CHECK-constraint value lists into master.enumeration_value and gives every active value an English display name. Idempotent. Returns rows added or changed, rows deactivated, and labels added.';

SELECT * FROM master.sync_enumeration_values();

GRANT SELECT ON master.enumeration_value TO talentra_app, talentra_readonly, talentra_analyst, talentra_support;

SELECT audit.sync_column_classification();
SELECT audit.refresh_protection();

COMMIT;
