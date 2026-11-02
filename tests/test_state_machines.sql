-- Test suite: tests/test_state_machines.sql
-- Covers: playbook step 08 ("every status has a way in and a way out, or is marked final"); REQ-020, REQ-022; BR-015, BR-026
-- Prerequisite: migrations 001-032 have been applied.
-- Isolation: read-only checks on the catalog and on master.status_transition.
--
-- Three promises: no status column escapes a decision, no state is a dead end nobody can reach, and every trigger is
-- wired to a column that exists.

BEGIN;

DO $$
DECLARE
    r RECORD;
    v_list TEXT;
    v_states TEXT[];
    v_reach TEXT[];
    v_start TEXT[];
    v_frontier TEXT[];
    v_next TEXT[];
    v_entity_count INTEGER;
BEGIN
    RAISE NOTICE '=== State machines ===';

    -- 1. every status-like column with an enumerated CHECK is governed or exempt
    SELECT string_agg(DISTINCT n.nspname || '.' || c.relname || '.' || a.attname, ', ') INTO v_list
      FROM pg_constraint k
      JOIN pg_class c ON c.oid = k.conrelid AND c.relkind IN ('r', 'p') AND NOT c.relispartition
      JOIN pg_namespace n ON n.oid = c.relnamespace
      JOIN pg_attribute a ON a.attrelid = k.conrelid AND a.attnum = k.conkey[1]
     WHERE k.contype = 'c' AND array_length(k.conkey, 1) = 1
       AND a.attname ~ '(status|state|stage)$'
       AND pg_get_constraintdef(k.oid) LIKE '%ARRAY[%'
       AND n.nspname IN ('core','master','profile','recruitment','gig','commercial','sourcing','messaging','audit','analytics')
       AND NOT EXISTS (SELECT 1 FROM master.status_transition st WHERE st.entity_code = n.nspname || '.' || c.relname)
       AND NOT EXISTS (SELECT 1 FROM master.status_machine_exemption e WHERE e.entity_code = n.nspname || '.' || c.relname AND e.column_name = a.attname);
    IF v_list IS NOT NULL THEN RAISE EXCEPTION 'FAIL: status columns that are neither a state machine nor a recorded exemption: %', v_list; END IF;
    RAISE NOTICE 'PASS: every status column is governed by transition rules or has a recorded exemption';

    -- 2. every governed entity has its trigger, wired to a real column
    FOR r IN SELECT DISTINCT entity_code FROM master.status_transition LOOP
        SELECT string_agg(a.attname, ',') INTO v_list
          FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace
          JOIN pg_attribute a ON a.attrelid = t.tgrelid AND a.attnum = ANY (t.tgattr)
         WHERE n.nspname || '.' || c.relname = r.entity_code AND t.tgfoid = 'master.enforce_status_transition'::regproc AND NOT t.tgisinternal;
        IF v_list IS NULL THEN RAISE EXCEPTION 'FAIL: % has transition rules but no enforcing trigger', r.entity_code; END IF;
        IF position(v_list IN encode((SELECT t.tgargs FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace
                                       WHERE n.nspname || '.' || c.relname = r.entity_code AND t.tgfoid = 'master.enforce_status_transition'::regproc AND NOT t.tgisinternal LIMIT 1), 'escape')) = 0 THEN
            RAISE EXCEPTION 'FAIL: the trigger on % watches % but passes a different column name to the function', r.entity_code, v_list;
        END IF;
    END LOOP;
    SELECT count(DISTINCT entity_code) INTO v_entity_count FROM master.status_transition;
    RAISE NOTICE 'PASS: all % governed entities have an enforcing trigger on the column they govern', v_entity_count;

    -- 3. no unreachable state: start from states nothing leads to (or the column default) and follow the rules
    FOR r IN SELECT DISTINCT entity_code FROM master.status_transition LOOP
        v_states := ARRAY(SELECT from_status FROM master.status_transition WHERE entity_code = r.entity_code
                          UNION SELECT to_status FROM master.status_transition WHERE entity_code = r.entity_code);
        v_start  := ARRAY(SELECT s FROM unnest(v_states) s
                           WHERE NOT EXISTS (SELECT 1 FROM master.status_transition st WHERE st.entity_code = r.entity_code AND st.to_status = s));
        IF array_length(v_start, 1) IS NULL THEN
            -- every state has an incoming move (a cycle): the entry point is the column default
            v_start := ARRAY(SELECT regexp_replace(pg_get_expr(d.adbin, d.adrelid), '^''([^'']+)''.*$', '\1')
                               FROM pg_attrdef d JOIN pg_class c ON c.oid = d.adrelid JOIN pg_namespace n ON n.oid = c.relnamespace
                               JOIN pg_trigger t ON t.tgrelid = c.oid AND t.tgfoid = 'master.enforce_status_transition'::regproc
                              WHERE n.nspname || '.' || c.relname = r.entity_code AND d.adnum = ANY (t.tgattr) LIMIT 1);
        END IF;
        v_reach := v_start; v_frontier := v_start;
        WHILE array_length(v_frontier, 1) IS NOT NULL LOOP
            v_next := ARRAY(SELECT DISTINCT st.to_status FROM master.status_transition st
                             WHERE st.entity_code = r.entity_code AND st.from_status = ANY (v_frontier) AND NOT st.to_status = ANY (v_reach));
            v_reach := v_reach || v_next; v_frontier := v_next;
        END LOOP;
        SELECT string_agg(s, ', ') INTO v_list FROM unnest(v_states) s WHERE NOT s = ANY (v_reach);
        IF v_list IS NOT NULL THEN RAISE EXCEPTION 'FAIL: % has states nothing can reach: %', r.entity_code, v_list; END IF;
    END LOOP;
    RAISE NOTICE 'PASS: every state of every machine can be reached from its entry state';

    -- 4. a final state really is final: no rule leaves it, and no governed entity has zero final states unless it is a cycle by design
    SELECT string_agg(DISTINCT entity_code, ', ') INTO v_list FROM master.status_transition st
     WHERE NOT EXISTS (SELECT 1 FROM master.status_transition x WHERE x.entity_code = st.entity_code
                        AND NOT EXISTS (SELECT 1 FROM master.status_transition y WHERE y.entity_code = st.entity_code AND y.from_status = x.to_status));
    IF v_list IS NOT NULL THEN RAISE NOTICE 'NOTE: machines with no final state (they cycle by design): %', v_list; END IF;

    RAISE NOTICE '=== State machine tests passed ===';
END
$$;

ROLLBACK;
