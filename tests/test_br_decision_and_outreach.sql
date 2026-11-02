-- Test suite: tests/test_br_decision_and_outreach.sql
-- Covers: BR-002 (all four rows of the device decision table), BR-021 (outreach block rule, migration 037), BR-005 (master data is read-only to the application)
-- Isolation: runs in a transaction that is rolled back.

BEGIN;

DO $$
DECLARE
    v_admin BIGINT; v_u BIGINT; v_org BIGINT; v_lic BIGINT; v_s1 BIGINT; v_s2 BIGINT; v_s3 BIGINT; v_s4 BIGINT;
    v_cand_user BIGINT; v_cand BIGINT; v_batch BIGINT; v_rcpt BIGINT; v_status TEXT; v_caught BOOLEAN; v_n INTEGER;
BEGIN
    SELECT id INTO v_admin FROM core.user_account ORDER BY id LIMIT 1;
    INSERT INTO core.user_account (email, account_status) VALUES ('br002@example.com', 'active') RETURNING id INTO v_u;
    INSERT INTO recruitment.organization (name, slug, organization_type, created_by_user_account_id) VALUES ('BR002 Org', 'br002-org', 'employer', v_admin) RETURNING id INTO v_org;
    INSERT INTO commercial.subscription_licence (organization_id, licence_key, licence_name, max_users, max_devices_per_user, valid_from, valid_to, licence_status)
    VALUES (v_org, 'BR002-LIC', 'BR002', 5, 2, now() - interval '1 day', now() + interval '1 year', 'active') RETURNING id INTO v_lic;
    INSERT INTO commercial.licence_seat_allocation (subscription_licence_id, user_account_id) VALUES (v_lic, v_u);

    -- row 3: the device already has an active session and the limit is NOT reached -> allowed
    v_s1 := core.create_session_with_device_limit(v_u, 'dev-A', repeat('a', 64), 'A');
    v_s2 := core.create_session_with_device_limit(v_u, 'dev-A', repeat('b', 64), 'A again');
    IF v_s1 IS NULL OR v_s2 IS NULL THEN RAISE EXCEPTION 'FAIL: BR-002 row 3: a second session on a known device below the limit was refused'; END IF;
    RAISE NOTICE 'PASS: BR-002 row 3 (known device, below the limit) is allowed';

    -- fill the limit with a second device, then a third device is refused (row 2, already tested elsewhere; here as the setup for row 4)
    v_s3 := core.create_session_with_device_limit(v_u, 'dev-B', repeat('c', 64), 'B');
    IF core.create_session_with_device_limit(v_u, 'dev-C', repeat('d', 64), 'C') IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: BR-002 row 2: a third device was accepted at a limit of 2';
    END IF;

    -- row 4: the device already has an active session and the limit IS reached -> allowed, the limit does not apply to a known device
    v_s4 := core.create_session_with_device_limit(v_u, 'dev-B', repeat('e', 64), 'B again');
    IF v_s4 IS NULL THEN RAISE EXCEPTION 'FAIL: BR-002 row 4: a known device at the limit was refused'; END IF;
    SELECT count(DISTINCT device_identifier) INTO v_n FROM core.user_session WHERE user_account_id = v_u AND ended_at IS NULL AND revoked_at IS NULL;
    IF v_n <> 2 THEN RAISE EXCEPTION 'FAIL: BR-002 row 4: expected 2 distinct active devices, found %', v_n; END IF;
    RAISE NOTICE 'PASS: BR-002 row 4 (known device, at the limit) is allowed and adds no device';

    -- BR-021: a recipient the candidate has blocked is stored as blocked and cannot be delivered
    INSERT INTO core.user_account (email, account_status) VALUES ('br021_cand@example.com', 'active') RETURNING id INTO v_cand_user;
    INSERT INTO profile.candidate_profile (user_account_id, visibility) VALUES (v_cand_user, 'public') RETURNING id INTO v_cand;
    INSERT INTO core.user_block (blocker_user_account_id, blocked_organization_id) VALUES (v_cand_user, v_org);
    INSERT INTO sourcing.outreach_batch (organization_id, created_by_user_account_id, campaign_name, message_body) VALUES (v_org, v_u, 'BR021', 'hello') RETURNING id INTO v_batch;
    INSERT INTO sourcing.outreach_recipient (outreach_batch_id, candidate_profile_id) VALUES (v_batch, v_cand) RETURNING id, delivery_status INTO v_rcpt, v_status;
    IF v_status <> 'blocked' THEN RAISE EXCEPTION 'FAIL: BR-021: a blocked candidate was stored as %', v_status; END IF;
    v_caught := FALSE;
    BEGIN UPDATE sourcing.outreach_recipient SET delivery_status = 'sent', sent_at = now() WHERE id = v_rcpt; EXCEPTION WHEN insufficient_privilege THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: BR-021: a blocked recipient was moved to sent'; END IF;
    RAISE NOTICE 'PASS: BR-021 a blocked candidate is stored as blocked and cannot be delivered to';

    -- an unblocked candidate is unaffected
    INSERT INTO core.user_account (email, account_status) VALUES ('br021_ok@example.com', 'active') RETURNING id INTO v_cand_user;
    INSERT INTO profile.candidate_profile (user_account_id, visibility) VALUES (v_cand_user, 'public') RETURNING id INTO v_cand;
    INSERT INTO sourcing.outreach_recipient (outreach_batch_id, candidate_profile_id) VALUES (v_batch, v_cand) RETURNING delivery_status INTO v_status;
    IF v_status <> 'pending' THEN RAISE EXCEPTION 'FAIL: BR-021: an unblocked candidate was stored as %', v_status; END IF;
    RAISE NOTICE 'PASS: BR-021 an unblocked candidate stays pending';

    -- BR-005: master code tables are read-only to the application role and reference nothing outside master and the audit users
    SELECT count(*) INTO v_n FROM information_schema.role_table_grants
     WHERE grantee = 'talentra_app' AND table_schema = 'master' AND privilege_type IN ('INSERT', 'UPDATE', 'DELETE')
       AND table_name IN ('country', 'language', 'state', 'city', 'industry', 'job_role', 'skill', 'qualification', 'employment_type', 'work_type');
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL: BR-005: the application role can write % master privileges', v_n; END IF;
    SELECT count(*) INTO v_n FROM pg_constraint k JOIN pg_class r ON r.oid = k.conrelid JOIN pg_namespace n ON n.oid = r.relnamespace
      JOIN pg_class f ON f.oid = k.confrelid JOIN pg_namespace fn ON fn.oid = f.relnamespace
     WHERE k.contype = 'f' AND n.nspname = 'master' AND fn.nspname NOT IN ('master') AND NOT (fn.nspname = 'core' AND f.relname = 'user_account');
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL: BR-005: % master foreign keys point outside master', v_n; END IF;
    RAISE NOTICE 'PASS: BR-005 master data is read-only to the application and self-contained';
END $$;

ROLLBACK;
