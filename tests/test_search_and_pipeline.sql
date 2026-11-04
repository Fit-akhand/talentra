-- Test suite: tests/test_search_and_pipeline.sql
-- Covers: REQ-014, REQ-019, REQ-021, REQ-022, SEC-010, BR-010, BR-015, BR-016, BR-045, BR-046 (migration 042: keyword search and match score, saved searches, the sourced stage, recruiter on an application, pipeline view)
-- Isolation: runs in a transaction that is rolled back. Candidates carry the made-up word "zorblax" so seeded data cannot interfere.

BEGIN;

DO $$
DECLARE
    v_admin BIGINT; v_org BIGINT; v_org2 BIGINT; v_rec BIGINT; v_rec2 BIGINT; v_outsider BIGINT; v_cuA BIGINT; v_cuB BIGINT; v_cuC BIGINT; v_cuD BIGINT;
    v_pA BIGINT; v_pB BIGINT; v_pC BIGINT; v_pD BIGINT; v_job BIGINT; v_job2 BIGINT; v_s1 BIGINT; v_s2 BIGINT; v_c1 BIGINT; v_c2 BIGINT; v_q BIGINT; v_d1 BIGINT;
    v_emp BIGINT; v_wt BIGINT; v_n INTEGER; v_ids BIGINT[]; v_pctA INTEGER; v_pctB INTEGER; v_caught BOOLEAN; v_app BIGINT; v_sid BIGINT; v_txt TEXT;
BEGIN
    SELECT id INTO v_admin FROM core.user_account ORDER BY id LIMIT 1;
    SELECT id INTO v_s1 FROM master.skill ORDER BY id LIMIT 1;
    SELECT id INTO v_s2 FROM master.skill ORDER BY id OFFSET 1 LIMIT 1;
    SELECT id INTO v_c1 FROM master.city ORDER BY id LIMIT 1;
    SELECT id INTO v_c2 FROM master.city ORDER BY id OFFSET 1 LIMIT 1;
    SELECT id INTO v_q FROM master.qualification ORDER BY id OFFSET 4 LIMIT 1;
    SELECT id INTO v_d1 FROM master.department ORDER BY id LIMIT 1;
    SELECT id INTO v_emp FROM master.employment_type ORDER BY id LIMIT 1;
    SELECT id INTO v_wt FROM master.work_type ORDER BY id LIMIT 1;
    INSERT INTO core.user_account (email, account_status) VALUES ('p42_rec@example.com', 'active') RETURNING id INTO v_rec;
    INSERT INTO core.user_account (email, account_status) VALUES ('p42_rec2@example.com', 'active') RETURNING id INTO v_rec2;
    INSERT INTO core.user_account (email, account_status) VALUES ('p42_out@example.com', 'active') RETURNING id INTO v_outsider;
    INSERT INTO core.user_account (email, account_status) VALUES ('p42_a@example.com', 'active') RETURNING id INTO v_cuA;
    INSERT INTO core.user_account (email, account_status) VALUES ('p42_b@example.com', 'active') RETURNING id INTO v_cuB;
    INSERT INTO core.user_account (email, account_status) VALUES ('p42_c@example.com', 'active') RETURNING id INTO v_cuC;
    INSERT INTO core.user_account (email, account_status) VALUES ('p42_d@example.com', 'active') RETURNING id INTO v_cuD;
    INSERT INTO recruitment.organization (name, slug, organization_type, created_by_user_account_id) VALUES ('P42 Org', 'p42-org', 'employer', v_admin) RETURNING id INTO v_org;
    INSERT INTO recruitment.organization (name, slug, organization_type, created_by_user_account_id) VALUES ('P42 Other', 'p42-other', 'employer', v_admin) RETURNING id INTO v_org2;
    INSERT INTO recruitment.organization_member (organization_id, user_account_id, organization_role, membership_status, joined_at) VALUES
        (v_org, v_rec, 'recruiter', 'active', now()), (v_org, v_rec2, 'recruiter', 'active', now()), (v_org2, v_outsider, 'recruiter', 'active', now());
    INSERT INTO recruitment.job_posting (organization_id, created_by_user_account_id, employment_type_id, work_type_id, title, description, job_status, published_at)
    VALUES (v_org, v_rec, v_emp, v_wt, 'P42 job', 'd', 'published', now()) RETURNING id INTO v_job;
    INSERT INTO recruitment.job_posting (organization_id, created_by_user_account_id, employment_type_id, work_type_id, title, description, job_status, published_at)
    VALUES (v_org2, v_outsider, v_emp, v_wt, 'P42 other job', 'd', 'published', now()) RETURNING id INTO v_job2;

    INSERT INTO profile.candidate_profile (user_account_id, headline, total_experience_years, visibility, last_active_at, profile_status) VALUES (v_cuA, 'Zorblax backend engineer', 5, 'public', now(), 'active') RETURNING id INTO v_pA;
    INSERT INTO profile.candidate_profile (user_account_id, headline, total_experience_years, visibility, last_active_at, profile_status) VALUES (v_cuB, 'Zorblax frontend designer', 2, 'recruiters', now() - interval '100 days', 'active') RETURNING id INTO v_pB;
    INSERT INTO profile.candidate_profile (user_account_id, headline, total_experience_years, visibility, last_active_at, profile_status) VALUES (v_cuC, 'Zorblax secret agent', 4, 'private', now(), 'active') RETURNING id INTO v_pC;
    INSERT INTO profile.candidate_profile (user_account_id, headline, total_experience_years, visibility, last_active_at, profile_status) VALUES (v_cuD, 'Zorblax blocked engineer', 4, 'public', now(), 'active') RETURNING id INTO v_pD;
    INSERT INTO core.user_block (blocker_user_account_id, blocked_organization_id) VALUES (v_cuD, v_org);
    INSERT INTO profile.candidate_skill (candidate_profile_id, skill_id) VALUES (v_pA, v_s1), (v_pA, v_s2), (v_pB, v_s2);
    INSERT INTO profile.candidate_location (candidate_profile_id, city_id, location_type) VALUES (v_pA, v_c1, 'current'), (v_pB, v_c2, 'current');
    INSERT INTO profile.candidate_education (candidate_profile_id, qualification_id, institution_name, field_of_study, study_mode) VALUES (v_pA, v_q, 'Quuxton Institute', 'Computer Science', 'full_time');
    INSERT INTO profile.candidate_work_experience (candidate_profile_id, employer_name, job_title, start_date, department_id) VALUES (v_pA, 'Quuxcorp', 'Zorblax developer', '2020-01-01', v_d1);
    INSERT INTO profile.candidate_job_preference (candidate_profile_id, notice_period_days, current_annual_ctc, expected_annual_ctc, ctc_currency_code, is_ctc_visible_to_recruiters) VALUES
        (v_pA, 30, 1500000, 1800000, 'INR', TRUE), (v_pB, 90, 600000, 900000, 'INR', FALSE);

    EXECUTE 'SET LOCAL ROLE talentra_app';
    PERFORM set_config('app.current_user_id', v_rec::TEXT, true);
    PERFORM set_config('app.current_org_id', v_org::TEXT, true);

    -- 1. keywords, privacy and blocks
    SELECT array_agg(candidate_profile_id ORDER BY candidate_profile_id) INTO v_ids FROM profile.search_candidates(p_keywords => 'zorblax');
    IF v_ids IS DISTINCT FROM ARRAY[v_pA, v_pB] THEN RAISE EXCEPTION 'FAIL: keyword search returned % (expected the public and recruiters-only profiles, not the private or blocking one)', v_ids; END IF;
    RAISE NOTICE 'PASS: keyword search skips private profiles and candidates who blocked the organisation';

    -- 2. exclusions, mandatory versus any, boolean mode
    SELECT array_agg(candidate_profile_id) INTO v_ids FROM profile.search_candidates(p_keywords => 'zorblax', p_exclude_keywords => 'designer');
    IF v_ids IS DISTINCT FROM ARRAY[v_pA] THEN RAISE EXCEPTION 'FAIL: exclude keywords returned %', v_ids; END IF;
    SELECT count(*) INTO v_n FROM profile.search_candidates(p_keywords => 'zorblax backend, zorblax frontend');
    IF v_n <> 2 THEN RAISE EXCEPTION 'FAIL: any-keyword search found % candidates, expected 2', v_n; END IF;
    SELECT count(*) INTO v_n FROM profile.search_candidates(p_keywords => 'zorblax backend, zorblax frontend', p_all_keywords => TRUE);
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL: mark-all-mandatory found % candidates, expected 0', v_n; END IF;
    SELECT array_agg(candidate_profile_id ORDER BY candidate_profile_id) INTO v_ids FROM profile.search_candidates(p_keywords => '"zorblax backend" or "zorblax frontend"', p_boolean_mode => TRUE);
    IF v_ids IS DISTINCT FROM ARRAY[v_pA, v_pB] THEN RAISE EXCEPTION 'FAIL: boolean OR of two phrases returned %', v_ids; END IF;
    SELECT array_agg(candidate_profile_id) INTO v_ids FROM profile.search_candidates(p_keywords => 'zorblax -designer', p_boolean_mode => TRUE);
    IF v_ids IS DISTINCT FROM ARRAY[v_pA] THEN RAISE EXCEPTION 'FAIL: boolean exclusion returned %', v_ids; END IF;
    RAISE NOTICE 'PASS: exclusions, mandatory keywords and boolean mode (OR, phrases, minus)';

    -- 3. the other filters
    SELECT array_agg(candidate_profile_id) INTO v_ids FROM profile.search_candidates(p_keywords => 'zorblax', p_min_experience => 3, p_max_experience => 10);
    IF v_ids IS DISTINCT FROM ARRAY[v_pA] THEN RAISE EXCEPTION 'FAIL: experience range returned %', v_ids; END IF;
    SELECT array_agg(candidate_profile_id) INTO v_ids FROM profile.search_candidates(p_keywords => 'zorblax', p_city_ids => ARRAY[v_c2]);
    IF v_ids IS DISTINCT FROM ARRAY[v_pB] THEN RAISE EXCEPTION 'FAIL: city filter returned %', v_ids; END IF;
    SELECT array_agg(candidate_profile_id ORDER BY candidate_profile_id) INTO v_ids FROM profile.search_candidates(p_keywords => 'zorblax', p_skill_ids => ARRAY[v_s2]);
    IF v_ids IS DISTINCT FROM ARRAY[v_pA, v_pB] THEN RAISE EXCEPTION 'FAIL: skill filter returned %', v_ids; END IF;
    SELECT array_agg(candidate_profile_id) INTO v_ids FROM profile.search_candidates(p_keywords => 'zorblax', p_qualification_ids => ARRAY[v_q], p_study_mode => 'full_time');
    IF v_ids IS DISTINCT FROM ARRAY[v_pA] THEN RAISE EXCEPTION 'FAIL: qualification and study mode returned %', v_ids; END IF;
    SELECT array_agg(candidate_profile_id) INTO v_ids FROM profile.search_candidates(p_keywords => 'zorblax', p_department_ids => ARRAY[v_d1]);
    IF v_ids IS DISTINCT FROM ARRAY[v_pA] THEN RAISE EXCEPTION 'FAIL: department filter returned %', v_ids; END IF;
    SELECT array_agg(candidate_profile_id) INTO v_ids FROM profile.search_candidates(p_keywords => 'zorblax', p_max_notice_days => 60);
    IF v_ids IS DISTINCT FROM ARRAY[v_pA] THEN RAISE EXCEPTION 'FAIL: notice period filter returned %', v_ids; END IF;
    SELECT array_agg(candidate_profile_id) INTO v_ids FROM profile.search_candidates(p_keywords => 'zorblax', p_active_within_days => 30);
    IF v_ids IS DISTINCT FROM ARRAY[v_pA] THEN RAISE EXCEPTION 'FAIL: recent activity filter returned %', v_ids; END IF;
    SELECT array_agg(candidate_profile_id) INTO v_ids FROM profile.search_candidates(p_keywords => 'zorblax', p_ctc_min => 1000000, p_ctc_max => 2000000, p_include_undisclosed_ctc => FALSE);
    IF v_ids IS DISTINCT FROM ARRAY[v_pA] THEN RAISE EXCEPTION 'FAIL: pay range without undisclosed returned %', v_ids; END IF;
    SELECT array_agg(candidate_profile_id ORDER BY candidate_profile_id) INTO v_ids FROM profile.search_candidates(p_keywords => 'zorblax', p_ctc_min => 1000000, p_ctc_max => 2000000, p_include_undisclosed_ctc => TRUE);
    IF v_ids IS DISTINCT FROM ARRAY[v_pA, v_pB] THEN RAISE EXCEPTION 'FAIL: pay range with undisclosed returned %', v_ids; END IF;
    SELECT count(*) INTO v_n FROM profile.search_candidates(p_keywords => 'zorblax', p_limit => 1);
    IF v_n <> 1 THEN RAISE EXCEPTION 'FAIL: limit 1 returned % rows', v_n; END IF;
    RAISE NOTICE 'PASS: experience, city, skill, education, department, notice, activity and pay filters (hidden pay counts as undisclosed)';

    -- 4. match percentage: more matched skills ranks higher; always 0..100; ordering follows it
    SELECT match_percent INTO v_pctA FROM profile.search_candidates(p_keywords => 'zorblax', p_skill_ids => ARRAY[v_s1, v_s2]) WHERE candidate_profile_id = v_pA;
    SELECT match_percent INTO v_pctB FROM profile.search_candidates(p_keywords => 'zorblax', p_skill_ids => ARRAY[v_s1, v_s2]) WHERE candidate_profile_id = v_pB;
    IF v_pctA <= v_pctB OR v_pctA > 100 OR v_pctB < 0 THEN RAISE EXCEPTION 'FAIL: match percent A % B % (A matched both skills, B one)', v_pctA, v_pctB; END IF;
    IF (SELECT candidate_profile_id FROM profile.search_candidates(p_keywords => 'zorblax', p_skill_ids => ARRAY[v_s1, v_s2]) LIMIT 1) <> v_pA THEN RAISE EXCEPTION 'FAIL: the best match is not first'; END IF;
    RAISE NOTICE 'PASS: the match percentage ranks fuller matches higher and stays within 0 to 100';

    -- 5. saved and recent searches
    FOR v_n IN 1..25 LOOP PERFORM profile.record_recruiter_search(jsonb_build_object('keywords', 'zorblax ' || v_n), v_n); END LOOP;
    SELECT count(*) INTO v_n FROM profile.recruiter_search WHERE user_account_id = v_rec AND name IS NULL;
    IF v_n <> 20 THEN RAISE EXCEPTION 'FAIL: % recent searches are kept, expected 20', v_n; END IF;
    v_sid := profile.record_recruiter_search('{"keywords": "java"}'::jsonb, 5, 'Java seniors', TRUE);
    IF profile.record_recruiter_search('{"keywords": "java 2"}'::jsonb, 9, ' java seniors ', FALSE) <> v_sid THEN RAISE EXCEPTION 'FAIL: saving a search under the same name created a second one'; END IF;
    v_caught := FALSE;
    BEGIN INSERT INTO profile.recruiter_search (organization_id, user_account_id, criteria_json, result_count, is_alert_enabled) VALUES (v_org, v_rec, '{}', 0, TRUE); EXCEPTION WHEN check_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: an alert on an unnamed search was accepted'; END IF;
    PERFORM set_config('app.current_user_id', v_rec2::TEXT, true);
    SELECT count(*) INTO v_n FROM profile.recruiter_search WHERE user_account_id = v_rec;
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL: a colleague sees % of another recruiter''s searches', v_n; END IF;
    PERFORM set_config('app.current_user_id', v_rec::TEXT, true);
    RAISE NOTICE 'PASS: recent searches are capped at 20, saved searches upsert by name, alerts need a name, searches are private';

    -- 6. the sourced stage
    INSERT INTO recruitment.candidate_application (candidate_profile_id, job_posting_id, application_status, application_source, created_by_user_account_id, updated_by_user_account_id)
    VALUES (v_pA, v_job, 'sourced', 'recruiter_sourced', v_rec, v_rec) RETURNING id INTO v_app;
    IF (SELECT assigned_recruiter_user_account_id FROM recruitment.candidate_application WHERE id = v_app) IS DISTINCT FROM v_rec THEN RAISE EXCEPTION 'FAIL: the sourcing recruiter did not become the candidate''s recruiter'; END IF;
    v_caught := FALSE;
    BEGIN INSERT INTO recruitment.candidate_application (candidate_profile_id, job_posting_id, application_status, application_source, created_by_user_account_id, updated_by_user_account_id)
          VALUES (v_pC, v_job, 'sourced', 'recruiter_sourced', v_rec, v_rec); EXCEPTION WHEN OTHERS THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: a recruiter sourced a private candidate'; END IF;
    v_caught := FALSE;
    BEGIN INSERT INTO recruitment.candidate_application (candidate_profile_id, job_posting_id, application_status, application_source, created_by_user_account_id, updated_by_user_account_id)
          VALUES (v_pB, v_job2, 'sourced', 'recruiter_sourced', v_rec, v_rec); EXCEPTION WHEN OTHERS THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: a recruiter sourced a candidate onto another organisation''s job'; END IF;
    EXECUTE 'RESET ROLE';
    v_caught := FALSE;
    BEGIN INSERT INTO recruitment.candidate_application (candidate_profile_id, job_posting_id, application_status, application_source, created_by_user_account_id, updated_by_user_account_id)
          VALUES (v_pB, v_job, 'sourced', 'direct', v_rec, v_rec); EXCEPTION WHEN check_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: a sourced application with source direct was accepted'; END IF;
    v_caught := FALSE;
    BEGIN UPDATE recruitment.candidate_application SET application_status = 'joined' WHERE id = v_app; EXCEPTION WHEN check_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: sourced -> joined was accepted'; END IF;
    v_caught := FALSE;
    BEGIN UPDATE recruitment.candidate_application SET assigned_recruiter_user_account_id = v_outsider WHERE id = v_app; EXCEPTION WHEN check_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: a recruiter of another organisation was assigned'; END IF;
    PERFORM recruitment.change_application_status(v_app, 'shortlisted', 'Strong profile');
    IF (SELECT new_status || '<-' || coalesce(previous_status, 'none') FROM recruitment.application_status_history WHERE candidate_application_id = v_app ORDER BY id LIMIT 1) <> 'sourced<-none' THEN
        RAISE EXCEPTION 'FAIL: the history does not start at sourced';
    END IF;
    RAISE NOTICE 'PASS: sourced is a first stage with its own rules, history and recruiter';

    -- 7. the candidate table of a requirement page
    INSERT INTO recruitment.candidate_application (candidate_profile_id, job_posting_id, created_by_user_account_id, updated_by_user_account_id) VALUES (v_pB, v_job2, v_outsider, v_outsider);
    EXECUTE 'SET LOCAL ROLE talentra_app';
    PERFORM set_config('app.current_user_id', v_rec::TEXT, true);
    PERFORM set_config('app.current_org_id', v_org::TEXT, true);
    SELECT count(*) INTO v_n FROM recruitment.job_candidate_pipeline WHERE job_posting_id IN (v_job, v_job2);
    IF v_n <> 1 THEN RAISE EXCEPTION 'FAIL: the pipeline view shows % applications of two organisations'' jobs, expected only the organisation''s own', v_n; END IF;
    SELECT application_status || '|' || coalesce(last_comment, '') INTO v_txt FROM recruitment.job_candidate_pipeline WHERE candidate_application_id = v_app;
    IF v_txt <> 'shortlisted|Strong profile' THEN RAISE EXCEPTION 'FAIL: the pipeline row is "%"', v_txt; END IF;
    EXECUTE 'RESET ROLE';
    RAISE NOTICE 'PASS: the requirement page shows its own organisation''s candidates with stage and latest comment';

    -- 8. the search document follows the profile
    UPDATE profile.candidate_profile SET headline = 'Wibblefrotz principal' WHERE id = v_pB;
    SELECT count(*) INTO v_n FROM profile.candidate_search_document WHERE candidate_profile_id = v_pB AND document @@ plainto_tsquery('english', 'wibblefrotz');
    IF v_n <> 1 THEN RAISE EXCEPTION 'FAIL: a headline change did not reach the search document'; END IF;
    UPDATE profile.candidate_profile SET deleted_at = now() WHERE id = v_pB;
    IF EXISTS (SELECT 1 FROM profile.candidate_search_document WHERE candidate_profile_id = v_pB) THEN RAISE EXCEPTION 'FAIL: a deleted profile kept its search document'; END IF;
    RAISE NOTICE 'PASS: the search document follows edits and disappears with the profile';
END $$;

ROLLBACK;
