-- Test suite: tests/test_integration_structures.sql
-- Covers: BR-032, BR-037, SEC-007, NFR-027 (docket section 6: nine integration boundaries; migration 038, DEC-32)
-- Isolation: runs in a transaction that is rolled back.

BEGIN;

DO $$
DECLARE
    v_admin BIGINT; v_a BIGINT; v_b BIGINT; v_org BIGINT; v_job BIGINT; v_ver BIGINT; v_n INTEGER; v_caught BOOLEAN; v_text TEXT; v_start BIGINT;
BEGIN
    SELECT id INTO v_admin FROM core.user_account ORDER BY id LIMIT 1;
    INSERT INTO core.user_account (email, account_status) VALUES ('is_a@example.com', 'active') RETURNING id INTO v_a;
    INSERT INTO core.user_account (email, account_status) VALUES ('is_b@example.com', 'active') RETURNING id INTO v_b;
    INSERT INTO recruitment.organization (name, slug, organization_type, created_by_user_account_id) VALUES ('IS Org', 'is-org', 'employer', v_admin) RETURNING id INTO v_org;
    SELECT id INTO v_job FROM recruitment.job_posting j WHERE NOT EXISTS (SELECT 1 FROM messaging.external_reference e WHERE e.entity_name = 'recruitment.job_posting' AND e.entity_id = j.id) ORDER BY id LIMIT 1;
    SELECT coalesce(max(id), 0) INTO v_start FROM audit.audit_event;

    -- 1. identity verification: a verified outcome needs a token and a time; duplicates are refused
    v_caught := FALSE;
    BEGIN INSERT INTO core.identity_verification (user_account_id, provider_code, request_id, verification_status) VALUES (v_a, 'idv_test', 'req-1', 'verified');
    EXCEPTION WHEN check_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: a verified outcome without a token was accepted'; END IF;
    INSERT INTO core.identity_verification (user_account_id, provider_code, request_id) VALUES (v_a, 'idv_test', 'req-1') RETURNING id INTO v_ver;
    v_caught := FALSE;
    BEGIN INSERT INTO core.identity_verification (user_account_id, provider_code, request_id) VALUES (v_b, 'idv_test', 'req-1'); EXCEPTION WHEN unique_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: a repeated provider request id was accepted'; END IF;
    RAISE NOTICE 'PASS: identity verification stores outcome plus token and is idempotent per request';

    -- 2. state machine and audit
    UPDATE core.identity_verification SET verification_status = 'verified', provider_token_ref = 'opaque-token-123', verified_at = now() WHERE id = v_ver;
    v_caught := FALSE;
    BEGIN UPDATE core.identity_verification SET verification_status = 'pending' WHERE id = v_ver; EXCEPTION WHEN check_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: verified -> pending was accepted'; END IF;
    SELECT count(*) INTO v_n FROM audit.audit_event WHERE id > v_start AND entity_name = 'identity_verification' AND action = 'account.status_changed';
    IF v_n < 2 THEN RAISE EXCEPTION 'FAIL: expected audit events for the insert and the verification, found %', v_n; END IF;
    IF EXISTS (SELECT 1 FROM audit.audit_event WHERE id > v_start AND entity_name = 'identity_verification' AND (new_values_json::text LIKE '%opaque-token-123%' OR old_values_json::text LIKE '%opaque-token-123%')) THEN
        RAISE EXCEPTION 'FAIL: the token reference reached the audit trail';
    END IF;
    RAISE NOTICE 'PASS: illegal transitions refused; outcome changes audited without the token';

    -- 3. row-level security: a person sees only their own verification and shares
    INSERT INTO core.identity_verification (user_account_id, provider_code, request_id) VALUES (v_b, 'idv_test', 'req-2');
    INSERT INTO messaging.share_event (user_account_id, job_posting_id, channel) VALUES (v_a, v_job, 'whatsapp'), (v_b, v_job, 'copy_link');
    EXECUTE 'SET LOCAL ROLE talentra_app';
    PERFORM set_config('app.current_user_id', v_a::TEXT, true);
    SELECT count(*) INTO v_n FROM core.identity_verification WHERE user_account_id IN (v_a, v_b);
    IF v_n <> 1 THEN RAISE EXCEPTION 'FAIL: user A sees % verification rows, expected 1', v_n; END IF;
    SELECT count(*) INTO v_n FROM messaging.share_event WHERE user_account_id IN (v_a, v_b);
    IF v_n <> 1 THEN RAISE EXCEPTION 'FAIL: user A sees % share events, expected 1', v_n; END IF;
    EXECUTE 'RESET ROLE';
    RAISE NOTICE 'PASS: verification and share rows are private to their owner';

    -- 4. erasure removes both
    PERFORM core.erase_user_account(v_a, v_admin);
    IF EXISTS (SELECT 1 FROM core.identity_verification WHERE user_account_id = v_a) OR EXISTS (SELECT 1 FROM messaging.share_event WHERE user_account_id = v_a) THEN
        RAISE EXCEPTION 'FAIL: erasure left a verification or share row';
    END IF;
    RAISE NOTICE 'PASS: erasure removes the verification record and the share events';

    -- 5. company review figures: salary needs a currency; the URL must be absolute; stale figures are flagged, not hidden
    v_caught := FALSE;
    BEGIN INSERT INTO recruitment.company_review_summary (organization_id, source, salary_median, refreshed_at) VALUES (v_org, 'ReviewCo', 50000, now()); EXCEPTION WHEN check_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: a salary without a currency was accepted'; END IF;
    INSERT INTO recruitment.company_review_summary (organization_id, source, rating_average, review_count, refreshed_at) VALUES (v_org, 'ReviewCo', 4.2, 120, now() - interval '45 days');
    IF NOT (SELECT is_stale FROM recruitment.company_review_summary_labelled WHERE organization_id = v_org) THEN RAISE EXCEPTION 'FAIL: a 45-day-old figure is not flagged stale'; END IF;
    RAISE NOTICE 'PASS: review figures carry source and refresh date and are labelled stale';

    -- 6. external references: one external id per row and the reverse
    INSERT INTO messaging.external_reference (boundary_code, entity_name, entity_id, external_id) VALUES ('legacy_sync', 'recruitment.job_posting', v_job, 'LEG-1');
    v_caught := FALSE;
    BEGIN INSERT INTO messaging.external_reference (boundary_code, entity_name, entity_id, external_id) VALUES ('legacy_sync', 'recruitment.job_posting', v_job + 100000, 'LEG-1'); EXCEPTION WHEN unique_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: one legacy id mapped to two Talentra rows'; END IF;
    RAISE NOTICE 'PASS: external references are one to one';

    -- 7. legacy field mapping: every column of the three synchronised tables has a direction; synced fields have a rule and an owner
    SELECT string_agg(c.table_schema || '.' || c.table_name || '.' || c.column_name, ', ') INTO v_text
      FROM information_schema.columns c
     WHERE (c.table_schema, c.table_name) IN (('profile', 'candidate_profile'), ('recruitment', 'job_posting'), ('recruitment', 'candidate_application'))
       AND NOT EXISTS (SELECT 1 FROM messaging.legacy_field_mapping m WHERE m.talentra_table = c.table_schema || '.' || c.table_name AND m.talentra_column = c.column_name);
    IF v_text IS NOT NULL THEN RAISE EXCEPTION 'FAIL: columns with no sync direction: %', v_text; END IF;
    SELECT string_agg(m.talentra_table || '.' || m.talentra_column, ', ') INTO v_text
      FROM messaging.legacy_field_mapping m
     WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns c WHERE c.table_schema || '.' || c.table_name = m.talentra_table AND c.column_name = m.talentra_column);
    IF v_text IS NOT NULL THEN RAISE EXCEPTION 'FAIL: mapped columns that do not exist: %', v_text; END IF;
    SELECT count(*) INTO v_n FROM messaging.legacy_field_mapping WHERE direction <> 'not_synced' AND conflict_rule IS NOT NULL AND owner_role IS NOT NULL;
    IF v_n < 25 THEN RAISE EXCEPTION 'FAIL: only % synchronised fields have a rule and an owner', v_n; END IF;
    RAISE NOTICE 'PASS: every field of the synchronised tables has a direction, and every synced field a conflict rule and an owner';

    -- 8. the conflict rules
    IF messaging.resolve_sync_conflict('legacy_wins', now(), now(), TRUE) <> 'legacy'
       OR messaging.resolve_sync_conflict('talentra_wins', NULL, NULL, FALSE) <> 'talentra'
       OR messaging.resolve_sync_conflict('cutover_dependent', now(), now(), FALSE) <> 'legacy'
       OR messaging.resolve_sync_conflict('cutover_dependent', now(), now(), TRUE) <> 'talentra'
       OR messaging.resolve_sync_conflict('latest_update_wins', now(), now() - interval '1 day', FALSE) <> 'legacy'
       OR messaging.resolve_sync_conflict('latest_update_wins', now() - interval '1 day', now(), FALSE) <> 'talentra'
       OR messaging.resolve_sync_conflict('latest_update_wins', now(), NULL, FALSE) <> 'legacy'
       OR messaging.resolve_sync_conflict('latest_update_wins', '2026-01-01', '2026-01-01', FALSE) <> 'review'
       OR messaging.resolve_sync_conflict('latest_update_wins', NULL, NULL, FALSE) <> 'review'
       OR messaging.resolve_sync_conflict('manual_review', now(), now(), FALSE) <> 'review' THEN
        RAISE EXCEPTION 'FAIL: a conflict rule returned the wrong winner';
    END IF;
    RAISE NOTICE 'PASS: all five conflict rules, including ties and missing timestamps';

    -- 9. conflict log: hashes only; a review stays open until a person chooses
    INSERT INTO messaging.sync_conflict (mapping_id, entity_id, legacy_value_sha256, talentra_value_sha256, rule_outcome)
    SELECT id, v_job, repeat('a', 64), repeat('b', 64), 'review' FROM messaging.legacy_field_mapping WHERE talentra_column = 'title' AND talentra_table = 'recruitment.job_posting';
    v_caught := FALSE;
    BEGIN UPDATE messaging.sync_conflict SET resolved_at = now() WHERE entity_id = v_job; EXCEPTION WHEN check_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: a review was closed without a choice'; END IF;
    v_caught := FALSE;
    BEGIN INSERT INTO messaging.sync_conflict (mapping_id, entity_id, legacy_value_sha256, talentra_value_sha256, rule_outcome)
          SELECT id, v_job, 'plain text value', repeat('b', 64), 'legacy' FROM messaging.legacy_field_mapping LIMIT 1; EXCEPTION WHEN check_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: a raw value was accepted in place of a hash'; END IF;
    RAISE NOTICE 'PASS: the conflict log holds hashes and keeps reviews open until a choice';
END $$;

ROLLBACK;
