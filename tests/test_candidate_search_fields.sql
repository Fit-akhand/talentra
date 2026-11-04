-- Test suite: tests/test_candidate_search_fields.sql
-- Covers: REQ-010, REQ-014, SEC-010, SEC-012, BR-010, BR-043, BR-044 (migration 041: notice period, pay, last active, study mode, private gender; DEC-35, DEC-36)
-- Isolation: runs in a transaction that is rolled back.

BEGIN;

DO $$
DECLARE
    v_admin BIGINT; v_org BIGINT; v_rec BIGINT; v_cu1 BIGINT; v_cu2 BIGINT; v_cu3 BIGINT; v_p1 BIGINT; v_p2 BIGINT; v_p3 BIGINT; v_n INTEGER; v_caught BOOLEAN;
    v_ctc NUMERIC; v_visible BOOLEAN; v_when TIMESTAMPTZ; v_sess BIGINT;
BEGIN
    SELECT id INTO v_admin FROM core.user_account ORDER BY id LIMIT 1;
    INSERT INTO core.user_account (email, account_status) VALUES ('p41_rec@example.com', 'active') RETURNING id INTO v_rec;
    INSERT INTO core.user_account (email, account_status) VALUES ('p41_c1@example.com', 'active') RETURNING id INTO v_cu1;
    INSERT INTO core.user_account (email, account_status) VALUES ('p41_c2@example.com', 'active') RETURNING id INTO v_cu2;
    INSERT INTO core.user_account (email, account_status) VALUES ('p41_c3@example.com', 'active') RETURNING id INTO v_cu3;
    INSERT INTO recruitment.organization (name, slug, organization_type, created_by_user_account_id) VALUES ('P41 Org', 'p41-org', 'employer', v_admin) RETURNING id INTO v_org;
    INSERT INTO recruitment.organization_member (organization_id, user_account_id, organization_role, membership_status, joined_at) VALUES (v_org, v_rec, 'recruiter', 'active', now());
    INSERT INTO profile.candidate_profile (user_account_id, visibility) VALUES (v_cu1, 'public') RETURNING id INTO v_p1;
    INSERT INTO profile.candidate_profile (user_account_id, visibility) VALUES (v_cu2, 'public') RETURNING id INTO v_p2;
    INSERT INTO profile.candidate_profile (user_account_id, visibility) VALUES (v_cu3, 'private') RETURNING id INTO v_p3;

    -- 1. constraints
    v_caught := FALSE;
    BEGIN INSERT INTO profile.candidate_job_preference (candidate_profile_id, notice_period_days) VALUES (v_p1, 400); EXCEPTION WHEN check_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: a 400-day notice period was accepted'; END IF;
    v_caught := FALSE;
    BEGIN INSERT INTO profile.candidate_job_preference (candidate_profile_id, current_annual_ctc) VALUES (v_p1, 500000); EXCEPTION WHEN check_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: pay without a currency was accepted'; END IF;
    v_caught := FALSE;
    BEGIN INSERT INTO profile.candidate_job_preference (candidate_profile_id, current_annual_ctc, ctc_currency_code) VALUES (v_p1, -1, 'INR'); EXCEPTION WHEN check_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: negative pay was accepted'; END IF;
    v_caught := FALSE;
    BEGIN INSERT INTO profile.candidate_diversity_profile (candidate_profile_id, gender) VALUES (v_p1, 'unknown'); EXCEPTION WHEN check_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: an unlisted gender value was accepted'; END IF;
    v_caught := FALSE;
    BEGIN UPDATE profile.candidate_education SET study_mode = 'weekend' WHERE id = (SELECT id FROM profile.candidate_education LIMIT 1); EXCEPTION WHEN check_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: an unlisted study mode was accepted'; END IF;
    RAISE NOTICE 'PASS: notice period, pay, gender and study mode are constrained';

    -- 2. a recruiter sees pay only when the candidate revealed it; notice period always (for visible profiles)
    INSERT INTO profile.candidate_job_preference (candidate_profile_id, notice_period_days, current_annual_ctc, expected_annual_ctc, ctc_currency_code, is_ctc_visible_to_recruiters)
    VALUES (v_p1, 30, 900000, 1200000, 'INR', FALSE), (v_p2, 60, 1500000, 1800000, 'INR', TRUE), (v_p3, 15, 700000, 800000, 'INR', TRUE);
    INSERT INTO profile.candidate_diversity_profile (candidate_profile_id, gender) VALUES (v_p1, 'female'), (v_p2, 'male');
    EXECUTE 'SET LOCAL ROLE talentra_app';
    PERFORM set_config('app.current_user_id', v_rec::TEXT, true);
    PERFORM set_config('app.current_org_id', v_org::TEXT, true);
    SELECT notice_period_days, current_annual_ctc, is_ctc_visible INTO v_n, v_ctc, v_visible FROM profile.candidate_search_attributes WHERE candidate_profile_id = v_p1;
    IF v_n <> 30 OR v_ctc IS NOT NULL OR v_visible THEN RAISE EXCEPTION 'FAIL: a hidden pay figure reached the recruiter (notice %, pay %)', v_n, v_ctc; END IF;
    SELECT current_annual_ctc INTO v_ctc FROM profile.candidate_search_attributes WHERE candidate_profile_id = v_p2;
    IF v_ctc IS DISTINCT FROM 1500000 THEN RAISE EXCEPTION 'FAIL: a revealed pay figure was not shown (%)', v_ctc; END IF;
    SELECT count(*) INTO v_n FROM profile.candidate_search_attributes WHERE candidate_profile_id = v_p3;
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL: a private profile''s attributes reached the recruiter'; END IF;
    RAISE NOTICE 'PASS: pay is shown only when revealed, private profiles stay hidden, notice period is searchable';

    -- 3. the base tables are closed to recruiters; gender is closed to everyone but the owner and administrators
    SELECT count(*) INTO v_n FROM profile.candidate_job_preference WHERE candidate_profile_id IN (v_p1, v_p2);
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL: a recruiter read % rows of the pay table directly', v_n; END IF;
    SELECT count(*) INTO v_n FROM profile.candidate_diversity_profile WHERE candidate_profile_id IN (v_p1, v_p2);
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL: a recruiter read % gender declarations', v_n; END IF;
    PERFORM set_config('app.current_user_id', v_cu1::TEXT, true);
    PERFORM set_config('app.current_org_id', '', true);
    SELECT count(*) INTO v_n FROM profile.candidate_diversity_profile WHERE candidate_profile_id IN (v_p1, v_p2);
    IF v_n <> 1 THEN RAISE EXCEPTION 'FAIL: a candidate sees % gender declarations, expected only their own', v_n; END IF;
    SELECT current_annual_ctc INTO v_ctc FROM profile.candidate_job_preference WHERE candidate_profile_id = v_p1;
    IF v_ctc IS DISTINCT FROM 900000 THEN RAISE EXCEPTION 'FAIL: a candidate cannot read their own pay'; END IF;
    EXECUTE 'RESET ROLE';
    RAISE NOTICE 'PASS: gender is private to the candidate; pay tables are closed to recruiters';

    -- 4. last active moves forward with a sign-in and never backwards
    SELECT last_active_at INTO v_when FROM profile.candidate_profile WHERE id = v_p2;
    IF v_when IS NOT NULL THEN RAISE EXCEPTION 'FAIL: a new profile already has a last_active_at'; END IF;
    v_sess := core.create_session_with_device_limit(v_cu2, 'p41-dev', repeat('9', 64), 'laptop');
    SELECT last_active_at INTO v_when FROM profile.candidate_profile WHERE id = v_p2;
    IF v_when IS NULL OR v_when < now() - interval '1 minute' THEN RAISE EXCEPTION 'FAIL: signing in did not set last_active_at (%)', v_when; END IF;
    UPDATE profile.candidate_profile SET last_active_at = now() + interval '1 day' WHERE id = v_p2;
    v_sess := core.create_session_with_device_limit(v_cu2, 'p41-dev', repeat('8', 64), 'laptop');
    IF (SELECT last_active_at FROM profile.candidate_profile WHERE id = v_p2) < now() THEN RAISE EXCEPTION 'FAIL: last_active_at moved backwards'; END IF;
    RAISE NOTICE 'PASS: last_active_at follows sign-ins and never goes back';

    -- 5. erasure removes pay and gender
    PERFORM core.erase_user_account(v_cu1, v_admin);
    IF EXISTS (SELECT 1 FROM profile.candidate_job_preference WHERE candidate_profile_id = v_p1) OR EXISTS (SELECT 1 FROM profile.candidate_diversity_profile WHERE candidate_profile_id = v_p1) THEN
        RAISE EXCEPTION 'FAIL: erasure left pay or gender behind';
    END IF;
    RAISE NOTICE 'PASS: erasure removes pay, notice period and gender';
END $$;

ROLLBACK;
