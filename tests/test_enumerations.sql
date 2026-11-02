-- Test suite: tests/test_enumerations.sql
-- Covers: DATA-001, BR-032 (docket Rule Group 3: enumerations have a code, a display name, an active flag and a sort order); migration 035, DEC-27
-- Isolation: runs in a transaction that is rolled back.

BEGIN;

DO $$
DECLARE
    v_list TEXT; v_added INTEGER; v_off INTEGER; v_lab INTEGER; v_n INTEGER;
BEGIN
    -- 1. the catalogue already mirrors every CHECK list: a re-sync finds nothing to do
    SELECT added, deactivated, labelled INTO v_added, v_off, v_lab FROM master.sync_enumeration_values();
    IF (v_added, v_off, v_lab) <> (0, 0, 0) THEN
        RAISE EXCEPTION 'FAIL: master.enumeration_value has drifted from the CHECK constraints (added %, deactivated %, labelled %); run SELECT master.sync_enumeration_values() in the migration that changed a list', v_added, v_off, v_lab;
    END IF;
    RAISE NOTICE 'PASS: enumeration catalogue matches the CHECK constraints';

    -- 2. every active value has an English display name
    SELECT string_agg(e.column_ref || '=' || e.code, ', ') INTO v_list
      FROM master.enumeration_value e
     WHERE e.is_active AND NOT EXISTS (SELECT 1 FROM messaging.ui_translation t
                                        WHERE t.language_code = 'en' AND t.string_key = 'enum.' || e.column_ref || '.' || lower(regexp_replace(e.code, '[^A-Za-z0-9]+', '_', 'g')));
    IF v_list IS NOT NULL THEN RAISE EXCEPTION 'FAIL: values without an English display name: %', v_list; END IF;
    RAISE NOTICE 'PASS: every active value has an English display name';

    -- 3. a display name resolves in any language through the English fallback
    IF messaging.get_ui_translation('enum.recruitment.candidate_application.application_status.shortlisted', 'hi') IS NULL THEN
        RAISE EXCEPTION 'FAIL: an untranslated language does not fall back to English';
    END IF;
    RAISE NOTICE 'PASS: untranslated languages fall back to English';

    -- 4. sort order is 1..n without gaps within each column
    SELECT string_agg(column_ref, ', ') INTO v_list FROM (
        SELECT column_ref FROM master.enumeration_value WHERE is_active GROUP BY column_ref HAVING min(sort_order) <> 1 OR max(sort_order) <> count(*)) x;
    IF v_list IS NOT NULL THEN RAISE EXCEPTION 'FAIL: sort order is not 1..n for: %', v_list; END IF;
    RAISE NOTICE 'PASS: sort order is contiguous';

    -- 5. a new allowed value is picked up, labelled, and a removed one is deactivated
    CREATE TABLE master.zz_enum_probe (kind VARCHAR(10) CHECK (kind IN ('alpha', 'beta_two')));
    SELECT added INTO v_added FROM master.sync_enumeration_values();
    SELECT count(*) INTO v_n FROM master.enumeration_value WHERE column_ref = 'master.zz_enum_probe.kind' AND is_active;
    IF v_added <> 2 OR v_n <> 2 THEN RAISE EXCEPTION 'FAIL: a new CHECK list was not picked up (added %, active %)', v_added, v_n; END IF;
    IF messaging.get_ui_translation('enum.master.zz_enum_probe.kind.beta_two', 'en') <> 'Beta two' THEN
        RAISE EXCEPTION 'FAIL: the generated display name is wrong';
    END IF;
    ALTER TABLE master.zz_enum_probe DROP CONSTRAINT zz_enum_probe_kind_check;
    ALTER TABLE master.zz_enum_probe ADD CONSTRAINT zz_enum_probe_kind_check CHECK (kind IN ('alpha', 'gamma'));
    SELECT deactivated INTO v_off FROM master.sync_enumeration_values();
    IF v_off <> 1 OR (SELECT count(*) FROM master.enumeration_value WHERE column_ref = 'master.zz_enum_probe.kind' AND is_active) <> 2 THEN RAISE EXCEPTION 'FAIL: a removed value was not deactivated (deactivated %)', v_off; END IF;
    RAISE NOTICE 'PASS: new values are picked up and removed values deactivated';
END $$;

ROLLBACK;
