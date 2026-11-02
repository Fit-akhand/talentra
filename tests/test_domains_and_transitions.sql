-- Test suite: tests/test_domains_and_transitions.sql
-- Covers: REQ-020, REQ-021, BR-015, BR-016; docket Rule Group 10 (append-only history), section 3 (recruiters
--         cannot register candidates), Tier 2 domains (activity log, search history, courses, resume templates)
-- Prerequisite: migrations 001-022 have been applied.
-- Isolation: one transaction, rolled back.

BEGIN;

DO $$
DECLARE
    v_emp_type BIGINT; v_work_type BIGINT;
    v_admin BIGINT; v_recruiter BIGINT; v_cand BIGINT; v_other BIGINT; v_org BIGINT;
    v_prof BIGINT; v_job BIGINT; v_appl BIGINT; v_course BIGINT; v_doc BIGINT; v_tpl BIGINT;
    v_caught BOOLEAN; v_bad TEXT; v_n INTEGER;
BEGIN
    RAISE NOTICE '=== Domains, append-only history and state transitions ===';
    SELECT id INTO v_emp_type FROM master.employment_type WHERE code = 'full_time';
    SELECT id INTO v_work_type FROM master.work_type WHERE code = 'remote';

    INSERT INTO core.user_account (email) VALUES ('dt-admin@example.com')     RETURNING id INTO v_admin;
    INSERT INTO core.user_account (email) VALUES ('dt-recruiter@example.com') RETURNING id INTO v_recruiter;
    INSERT INTO core.user_account (email) VALUES ('dt-candidate@example.com') RETURNING id INTO v_cand;
    INSERT INTO core.user_account (email) VALUES ('dt-other@example.com')     RETURNING id INTO v_other;
    INSERT INTO core.user_role (user_account_id, role_id) SELECT v_admin, id FROM core.role WHERE name = 'admin';
    INSERT INTO core.user_role (user_account_id, role_id) SELECT v_recruiter, id FROM core.role WHERE name = 'recruiter';

    -- ------------------------------------------------------------ recruiters cannot register candidates
    v_caught := FALSE;
    BEGIN
        INSERT INTO profile.candidate_profile (user_account_id, created_by_user_account_id) VALUES (v_cand, v_recruiter);
    EXCEPTION WHEN insufficient_privilege THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: a recruiter created a candidate profile for someone else'; END IF;

    PERFORM set_config('app.current_user_id', v_recruiter::TEXT, true);
    v_caught := FALSE;
    BEGIN
        INSERT INTO profile.candidate_profile (user_account_id) VALUES (v_cand);
    EXCEPTION WHEN insufficient_privilege THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: the acting recruiter (from app.current_user_id) registered a candidate'; END IF;

    PERFORM set_config('app.current_user_id', v_cand::TEXT, true);
    INSERT INTO profile.candidate_profile (user_account_id) VALUES (v_cand) RETURNING id INTO v_prof;        -- self: allowed
    PERFORM set_config('app.current_user_id', v_admin::TEXT, true);
    INSERT INTO profile.candidate_profile (user_account_id) VALUES (v_other);                                -- admin: allowed
    PERFORM set_config('app.current_user_id', '', true);
    RAISE NOTICE 'PASS: only the candidate or a platform admin can create a candidate profile';

    -- ------------------------------------------------------------ append-only history
    INSERT INTO profile.candidate_activity_log (user_account_id, candidate_profile_id, activity_type, detail_json)
    VALUES (v_cand, v_prof, 'resume_download', '{"document": 1}');
    INSERT INTO profile.profile_view_history (candidate_profile_id, viewer_user_account_id, view_source)
    VALUES (v_prof, v_recruiter, 'search');
    INSERT INTO audit.system_error_log (error_code, error_message) VALUES ('TEST', 'x');

    -- ------------------------------------------------------------ search history
    INSERT INTO profile.candidate_search_history (candidate_profile_id, query_text, result_count) VALUES (v_prof, 'dba', 12);
    v_caught := FALSE;
    BEGIN INSERT INTO profile.candidate_search_history (candidate_profile_id, result_count) VALUES (v_prof, 0);
    EXCEPTION WHEN check_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: an empty search (no text, no filters) was stored'; END IF;
    v_caught := FALSE;
    BEGIN INSERT INTO profile.candidate_search_history (candidate_profile_id, query_text, result_count) VALUES (v_prof, 'x', -1);
    EXCEPTION WHEN check_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: a negative result count was stored'; END IF;
    RAISE NOTICE 'PASS: search history rejects empty searches and negative counts';

    -- ------------------------------------------------------------ courses
    INSERT INTO profile.course (code, title, duration_hours) VALUES ('sql-101', 'SQL foundations', 12.5) RETURNING id INTO v_course;
    INSERT INTO profile.course_enrolment (candidate_profile_id, course_id) VALUES (v_prof, v_course);
    v_caught := FALSE;
    BEGIN INSERT INTO profile.course_enrolment (candidate_profile_id, course_id) VALUES (v_prof, v_course);
    EXCEPTION WHEN unique_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: a candidate enrolled twice in the same course'; END IF;
    v_caught := FALSE;
    BEGIN UPDATE profile.course_enrolment SET enrolment_status = 'completed' WHERE candidate_profile_id = v_prof;
    EXCEPTION WHEN check_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: completed without completed_at was accepted'; END IF;
    v_caught := FALSE;
    BEGIN UPDATE profile.course_enrolment SET score_percent = 101 WHERE candidate_profile_id = v_prof;
    EXCEPTION WHEN check_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: a score above 100 was accepted'; END IF;
    UPDATE profile.course_enrolment SET enrolment_status = 'completed', completed_at = now() + interval '1 day', score_percent = 88.5
     WHERE candidate_profile_id = v_prof;
    RAISE NOTICE 'PASS: course enrolment is unique per candidate and course; completion and score are consistent';

    -- ------------------------------------------------------------ resume templates
    SELECT id INTO v_tpl FROM profile.resume_template WHERE code = 'modern';
    INSERT INTO profile.candidate_document (candidate_profile_id, document_type, original_filename, storage_provider, storage_key,
                                            mime_type, file_size_bytes, checksum_sha256, resume_template_id)
    VALUES (v_prof, 'resume', 'cv.pdf', 's3', 'k/1', 'application/pdf', 1000, repeat('a', 64), v_tpl) RETURNING id INTO v_doc;
    v_caught := FALSE;
    BEGIN INSERT INTO profile.candidate_document (candidate_profile_id, document_type, original_filename, storage_provider, storage_key,
                                                  mime_type, file_size_bytes, checksum_sha256, resume_template_id)
          VALUES (v_prof, 'certificate', 'c.pdf', 's3', 'k/2', 'application/pdf', 1000, repeat('b', 64), v_tpl);
    EXCEPTION WHEN check_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: a template was attached to a non-resume document'; END IF;
    RAISE NOTICE 'PASS: only resumes may reference a resume template';

    -- ------------------------------------------------------------ state transitions
    INSERT INTO recruitment.organization (name, slug, created_by_user_account_id, organization_status)
    VALUES ('DT Org', 'dt-org', v_recruiter, 'active') RETURNING id INTO v_org;
    INSERT INTO recruitment.job_posting (organization_id, created_by_user_account_id, employment_type_id, work_type_id, title, description)
    VALUES (v_org, v_recruiter, v_emp_type, v_work_type, 'DT job', 'd') RETURNING id INTO v_job;

    -- job: draft -> filled is illegal; draft -> published -> paused -> published -> closed is legal
    v_caught := FALSE;
    BEGIN UPDATE recruitment.job_posting SET job_status = 'filled' WHERE id = v_job;
    EXCEPTION WHEN check_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: draft -> filled was accepted for a job'; END IF;
    UPDATE recruitment.job_posting SET job_status = 'published', published_at = now() WHERE id = v_job;
    UPDATE recruitment.job_posting SET job_status = 'paused' WHERE id = v_job;
    UPDATE recruitment.job_posting SET job_status = 'published' WHERE id = v_job;
    UPDATE recruitment.job_posting SET job_status = 'filled', closed_at = now() WHERE id = v_job;
    v_caught := FALSE;
    BEGIN UPDATE recruitment.job_posting SET job_status = 'published' WHERE id = v_job;
    EXCEPTION WHEN check_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: a filled job was reopened (filled is final)'; END IF;

    -- application pipeline
    INSERT INTO recruitment.candidate_application (candidate_profile_id, job_posting_id, application_status, created_by_user_account_id)
    VALUES (v_prof, v_job, 'applied', v_cand) RETURNING id INTO v_appl;
    v_caught := FALSE;
    BEGIN UPDATE recruitment.candidate_application SET application_status = 'offered' WHERE id = v_appl;
    EXCEPTION WHEN check_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: applied -> offered skipped the pipeline'; END IF;
    UPDATE recruitment.candidate_application SET application_status = 'shortlisted' WHERE id = v_appl;
    UPDATE recruitment.candidate_application SET application_status = 'interviewed' WHERE id = v_appl;
    UPDATE recruitment.candidate_application SET application_status = 'offered' WHERE id = v_appl;
    UPDATE recruitment.candidate_application SET application_status = 'joined' WHERE id = v_appl;
    v_caught := FALSE;
    BEGIN UPDATE recruitment.candidate_application SET application_status = 'applied' WHERE id = v_appl;
    EXCEPTION WHEN check_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: a joined application moved back to applied'; END IF;
    IF (SELECT count(*) FROM recruitment.application_status_history WHERE candidate_application_id = v_appl) < 4 THEN
        RAISE EXCEPTION 'FAIL: legal transitions were not recorded in the status history';
    END IF;

    -- account: deactivated is final
    UPDATE core.user_account SET account_status = 'active' WHERE id = v_other;
    UPDATE core.user_account SET account_status = 'deactivated' WHERE id = v_other;
    v_caught := FALSE;
    BEGIN UPDATE core.user_account SET account_status = 'active' WHERE id = v_other;
    EXCEPTION WHEN check_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: a deactivated account was reactivated'; END IF;

    -- setting a status to its current value is not a transition
    UPDATE core.user_account SET account_status = 'deactivated' WHERE id = v_other;
    RAISE NOTICE 'PASS: illegal transitions are rejected, legal ones succeed, final states hold';

    -- every status named in a transition exists in the table's own CHECK (typo guard)
    SELECT string_agg(DISTINCT st.entity_code || ':' || st.s, ', ') INTO v_bad
      FROM (SELECT entity_code, from_status AS s FROM master.status_transition
            UNION SELECT entity_code, to_status FROM master.status_transition) st
      JOIN pg_trigger tg ON tg.tgname = 'trg_' || split_part(st.entity_code, '.', 2) || '_status_transition'
     WHERE NOT EXISTS (
            SELECT 1 FROM pg_constraint c2
             WHERE c2.conrelid = tg.tgrelid AND c2.contype = 'c'
               AND pg_get_constraintdef(c2.oid) LIKE '%''' || st.s || '''%');
    IF v_bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL: transition statuses not allowed by the table CHECK: %', v_bad; END IF;
    IF (SELECT count(DISTINCT entity_code) FROM master.status_transition) <>
       (SELECT count(*) FROM pg_trigger WHERE tgname LIKE 'trg\_%\_status\_transition') THEN
        RAISE EXCEPTION 'FAIL: every entity in master.status_transition must have its trigger, and vice versa';
    END IF;
    RAISE NOTICE 'PASS: transition statuses match each table''s CHECK list; one trigger per entity';

    -- ------------------------------------------------------------ money has a currency; user-entered text names its language
    v_caught := FALSE;
    BEGIN INSERT INTO messaging.referral_event (referrer_user_account_id, referred_email, referral_code, status, reward_amount)
          VALUES (v_cand, 'friend@example.com', 'REF-DT-1', 'invited', 25.00);
    EXCEPTION WHEN check_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: a reward amount with no currency was accepted'; END IF;
    v_caught := FALSE;
    BEGIN INSERT INTO messaging.job_alert_preference (user_account_id, alert_name, minimum_salary) VALUES (v_cand, 'dt-alert', 50000);
    EXCEPTION WHEN check_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: a minimum salary with no currency was accepted'; END IF;
    v_caught := FALSE;
    BEGIN UPDATE recruitment.job_posting SET description_language_code = 'xx' WHERE id = v_job;
    EXCEPTION WHEN foreign_key_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: an unknown language code was accepted'; END IF;
    UPDATE recruitment.job_posting SET description_language_code = 'hi' WHERE id = v_job;
    RAISE NOTICE 'PASS: amounts require a currency; content language must be a known language';

    -- append-only history: every one of these tables now holds a row; none may be changed or removed
    FOR v_bad IN SELECT unnest(ARRAY['profile.candidate_activity_log', 'profile.profile_view_history',
                                     'recruitment.application_status_history', 'audit.system_error_log']) LOOP
        EXECUTE format('SELECT count(*) FROM %s', v_bad) INTO v_n;
        IF v_n = 0 THEN RAISE EXCEPTION 'FAIL: test fixture left % empty, so the guard is untested', v_bad; END IF;
        v_caught := FALSE;
        BEGIN EXECUTE format('UPDATE %s SET id = DEFAULT', v_bad);
        EXCEPTION WHEN restrict_violation THEN v_caught := TRUE; END;
        IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: % can be updated', v_bad; END IF;
        v_caught := FALSE;
        BEGIN EXECUTE format('DELETE FROM %s', v_bad);
        EXCEPTION WHEN restrict_violation THEN v_caught := TRUE; END;
        IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: % can be deleted from', v_bad; END IF;
        v_caught := FALSE;
        BEGIN EXECUTE format('TRUNCATE %s', v_bad);
        EXCEPTION WHEN restrict_violation THEN v_caught := TRUE; END;
        IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: TRUNCATE allowed on %', v_bad; END IF;
    END LOOP;
    RAISE NOTICE 'PASS: activity, view, status and error history reject UPDATE, DELETE and TRUNCATE';

    RAISE NOTICE '=== Domain and transition tests passed ===';
END
$$;

ROLLBACK;
