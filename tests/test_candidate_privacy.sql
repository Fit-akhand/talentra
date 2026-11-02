-- Test suite: tests/test_candidate_privacy.sql
-- Covers: NFR-013, SEC-002, SEC-010, BR-010, docket section 3 ("a blocked party must not see that candidate")
-- Prerequisite: migrations 001-030 have been applied.
-- Isolation: one transaction, rolled back.
--
-- Every table that hangs off a candidate must obey the same rule as the profile itself. The first block asserts that from the
-- catalog (no table with a candidate_profile_id is left unprotected); the rest acts as the application role.

BEGIN;

DO $$
DECLARE
    v_missing TEXT; v_n INTEGER; v_caught BOOLEAN;
    v_emp BIGINT; v_work BIGINT; v_qual BIGINT; v_lang BIGINT; v_skill BIGINT; v_city BIGINT;
    v_ra BIGINT; v_rb BIGINT; v_cand BIGINT; v_cand2 BIGINT; v_orgA BIGINT; v_orgB BIGINT; v_prof BIGINT;
    v_tbl TEXT; v_sql TEXT;
    v_tables TEXT[] := ARRAY['profile.candidate_education', 'profile.candidate_language', 'profile.candidate_location', 'profile.candidate_skill',
                             'profile.candidate_work_experience', 'profile.candidate_project', 'profile.candidate_document', 'profile.candidate_profile_completion'];
BEGIN
    RAISE NOTICE '=== Candidate privacy: block and visibility on every candidate-keyed table ===';

    -- 1. Catalog: every base table with a foreign key to candidate_profile has row-level security, except the one that holds no personal data
    SELECT string_agg(DISTINCT cl.oid::regclass::TEXT, ', ') INTO v_missing
      FROM pg_constraint k JOIN pg_class cl ON cl.oid = k.conrelid
     WHERE k.contype = 'f' AND k.confrelid = 'profile.candidate_profile'::regclass
       AND cl.relkind IN ('r', 'p') AND NOT cl.relispartition AND NOT cl.relrowsecurity
       AND cl.oid::regclass::TEXT NOT IN ('recruitment.job_position');          -- a vacancy slot names who filled it; no personal column
    IF v_missing IS NOT NULL THEN RAISE EXCEPTION 'FAIL: candidate-keyed tables without row-level security: %', v_missing; END IF;
    RAISE NOTICE 'PASS: every table keyed to a candidate has row-level security (NFR-013)';

    -- fixtures
    SELECT id INTO v_emp FROM master.employment_type LIMIT 1;  SELECT id INTO v_qual FROM master.qualification LIMIT 1;
    SELECT id INTO v_lang FROM master.language WHERE code = 'en'; SELECT id INTO v_skill FROM master.skill LIMIT 1; SELECT id INTO v_city FROM master.city LIMIT 1;
    IF v_city IS NULL THEN          -- an empty database has no geography yet; the generator seeds it, the migrations do not
        INSERT INTO master.country (iso_alpha2, iso_alpha3, name) VALUES ('CQ', 'CQC', 'Privacy Test Country') ON CONFLICT DO NOTHING;
        INSERT INTO master.state (country_id, name, subdivision_code) SELECT id, 'Privacy Test State', 'CQ-01' FROM master.country WHERE iso_alpha2 = 'CQ';
        INSERT INTO master.city (state_id, name) SELECT id, 'Privacy Test City' FROM master.state WHERE subdivision_code = 'CQ-01' RETURNING id INTO v_city;
    END IF;
    INSERT INTO core.user_account (email) VALUES ('cp-recruiter-a@example.com') RETURNING id INTO v_ra;
    INSERT INTO core.user_account (email) VALUES ('cp-recruiter-b@example.com') RETURNING id INTO v_rb;
    INSERT INTO core.user_account (email) VALUES ('cp-candidate@example.com')   RETURNING id INTO v_cand;
    INSERT INTO core.user_account (email) VALUES ('cp-candidate2@example.com')  RETURNING id INTO v_cand2;
    INSERT INTO recruitment.organization (name, slug, created_by_user_account_id, organization_status) VALUES ('CP Org A', 'cp-org-a', v_ra, 'active') RETURNING id INTO v_orgA;
    INSERT INTO recruitment.organization (name, slug, created_by_user_account_id, organization_status) VALUES ('CP Org B', 'cp-org-b', v_rb, 'active') RETURNING id INTO v_orgB;
    INSERT INTO recruitment.organization_member (organization_id, user_account_id, organization_role, membership_status, joined_at)
    VALUES (v_orgA, v_ra, 'recruiter', 'active', now()), (v_orgB, v_rb, 'recruiter', 'active', now());
    INSERT INTO profile.candidate_profile (user_account_id, headline, visibility) VALUES (v_cand, 'Private person', 'recruiters') RETURNING id INTO v_prof;
    INSERT INTO profile.candidate_education (candidate_profile_id, qualification_id, institution_name) VALUES (v_prof, v_qual, 'Test University');
    INSERT INTO profile.candidate_language (candidate_profile_id, language_id) VALUES (v_prof, v_lang);
    INSERT INTO profile.candidate_location (candidate_profile_id, city_id, location_type) VALUES (v_prof, v_city, 'current');
    INSERT INTO profile.candidate_skill (candidate_profile_id, skill_id, proficiency_level) VALUES (v_prof, v_skill, 'advanced');
    INSERT INTO profile.candidate_work_experience (candidate_profile_id, employer_name, job_title, start_date) VALUES (v_prof, 'Acme', 'Engineer', '2020-01-01');
    INSERT INTO profile.candidate_project (candidate_profile_id, title, candidate_role) VALUES (v_prof, 'Side project', 'Author');
    INSERT INTO profile.candidate_document (candidate_profile_id, document_type, original_filename, storage_provider, storage_key, mime_type, file_size_bytes, checksum_sha256)
    VALUES (v_prof, 'resume', 'cv.pdf', 's3', 'k/cp', 'application/pdf', 1000, repeat('c', 64));
    INSERT INTO profile.candidate_profile_completion (candidate_profile_id, total_score_percentage) VALUES (v_prof, 50);

    -- helper: how many of the candidate's rows are visible across all eight child tables
    CREATE TEMP TABLE _visible AS SELECT 0::INT AS n;

    -- 2. A recruiter of an unblocked organisation sees every child row
    EXECUTE 'SET LOCAL ROLE talentra_app';
    PERFORM set_config('app.current_user_id', v_ra::TEXT, true); PERFORM set_config('app.current_org_id', v_orgA::TEXT, true);
    FOREACH v_tbl IN ARRAY v_tables LOOP
        EXECUTE format('SELECT count(*) FROM %s WHERE candidate_profile_id = %s', v_tbl, v_prof) INTO v_n;
        IF v_n <> 1 THEN RAISE EXCEPTION 'FAIL: an unblocked recruiter sees % rows in %, expected 1', v_n, v_tbl; END IF;
    END LOOP;
    RAISE NOTICE 'PASS: an unblocked recruiter reads the candidate''s rows in all % child tables', array_length(v_tables, 1);

    -- 3. A candidate (no organisation) cannot read another candidate whose profile is recruiters-only
    PERFORM set_config('app.current_user_id', v_cand2::TEXT, true); PERFORM set_config('app.current_org_id', '', true);
    FOREACH v_tbl IN ARRAY v_tables LOOP
        EXECUTE format('SELECT count(*) FROM %s WHERE candidate_profile_id = %s', v_tbl, v_prof) INTO v_n;
        IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL: another candidate reads % rows of a recruiters-only profile in %', v_n, v_tbl; END IF;
    END LOOP;
    RAISE NOTICE 'PASS: another candidate cannot read a recruiters-only profile, in any table';

    -- 4. The candidate blocks organisation A: A loses every row, B keeps them
    EXECUTE 'RESET ROLE';
    INSERT INTO core.user_block (blocker_user_account_id, blocked_organization_id) VALUES (v_cand, v_orgA);
    EXECUTE 'SET LOCAL ROLE talentra_app';
    PERFORM set_config('app.current_user_id', v_ra::TEXT, true); PERFORM set_config('app.current_org_id', v_orgA::TEXT, true);
    FOREACH v_tbl IN ARRAY v_tables LOOP
        EXECUTE format('SELECT count(*) FROM %s WHERE candidate_profile_id = %s', v_tbl, v_prof) INTO v_n;
        IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL: a blocked organisation still reads % rows in %', v_n, v_tbl; END IF;
    END LOOP;
    IF EXISTS (SELECT 1 FROM profile.candidate_profile WHERE id = v_prof) THEN RAISE EXCEPTION 'FAIL: a blocked organisation still reads the profile'; END IF;
    PERFORM set_config('app.current_user_id', v_rb::TEXT, true); PERFORM set_config('app.current_org_id', v_orgB::TEXT, true);
    FOREACH v_tbl IN ARRAY v_tables LOOP
        EXECUTE format('SELECT count(*) FROM %s WHERE candidate_profile_id = %s', v_tbl, v_prof) INTO v_n;
        IF v_n <> 1 THEN RAISE EXCEPTION 'FAIL: an organisation that was not blocked lost its access to %', v_tbl; END IF;
    END LOOP;
    RAISE NOTICE 'PASS: blocking an organisation hides the profile and all % child tables from it, and only from it', array_length(v_tables, 1);

    -- 5. The owner always sees everything; a private profile is invisible to recruiters
    PERFORM set_config('app.current_user_id', v_cand::TEXT, true); PERFORM set_config('app.current_org_id', '', true);
    FOREACH v_tbl IN ARRAY v_tables LOOP
        EXECUTE format('SELECT count(*) FROM %s WHERE candidate_profile_id = %s', v_tbl, v_prof) INTO v_n;
        IF v_n <> 1 THEN RAISE EXCEPTION 'FAIL: the owner cannot read their own rows in %', v_tbl; END IF;
    END LOOP;
    UPDATE profile.candidate_profile SET visibility = 'private' WHERE id = v_prof;
    PERFORM set_config('app.current_user_id', v_rb::TEXT, true); PERFORM set_config('app.current_org_id', v_orgB::TEXT, true);
    FOREACH v_tbl IN ARRAY v_tables LOOP
        EXECUTE format('SELECT count(*) FROM %s WHERE candidate_profile_id = %s', v_tbl, v_prof) INTO v_n;
        IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL: a private profile''s rows are readable by a recruiter in %', v_tbl; END IF;
    END LOOP;
    RAISE NOTICE 'PASS: the owner reads everything; a private profile hides all of it from recruiters';

    -- 6. Only the owner writes
    PERFORM set_config('app.current_user_id', v_cand::TEXT, true); PERFORM set_config('app.current_org_id', '', true);
    UPDATE profile.candidate_profile SET visibility = 'public' WHERE id = v_prof;
    PERFORM set_config('app.current_user_id', v_rb::TEXT, true); PERFORM set_config('app.current_org_id', v_orgB::TEXT, true);
    v_caught := FALSE;
    BEGIN INSERT INTO profile.candidate_education (candidate_profile_id, qualification_id, institution_name) VALUES (v_prof, v_qual, 'Planted degree');
    EXCEPTION WHEN insufficient_privilege THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: a recruiter added an education row to someone else''s profile'; END IF;
    DELETE FROM profile.candidate_skill WHERE candidate_profile_id = v_prof;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL: a recruiter deleted % skill rows of someone else''s profile', v_n; END IF;
    RAISE NOTICE 'PASS: a recruiter can read a public profile but cannot add to it or delete from it';

    -- 7. The candidate sees who looked at them; an organisation sees only its own bookmarks
    EXECUTE 'RESET ROLE';
    INSERT INTO profile.profile_view_history (candidate_profile_id, viewer_user_account_id, organization_id, view_source) VALUES (v_prof, v_rb, v_orgB, 'search');
    INSERT INTO profile.recruiter_bookmark (organization_id, user_account_id, candidate_profile_id, notes) VALUES (v_orgB, v_rb, v_prof, 'follow up');
    EXECUTE 'SET LOCAL ROLE talentra_app';
    PERFORM set_config('app.current_user_id', v_cand::TEXT, true); PERFORM set_config('app.current_org_id', '', true);
    IF (SELECT count(*) FROM profile.profile_view_history WHERE candidate_profile_id = v_prof) <> 1 THEN RAISE EXCEPTION 'FAIL: the candidate cannot see who viewed their profile'; END IF;
    IF (SELECT count(*) FROM profile.recruiter_bookmark WHERE candidate_profile_id = v_prof) <> 0 THEN RAISE EXCEPTION 'FAIL: the candidate can read a recruiter''s private bookmark'; END IF;
    PERFORM set_config('app.current_user_id', v_ra::TEXT, true); PERFORM set_config('app.current_org_id', v_orgA::TEXT, true);
    IF (SELECT count(*) FROM profile.profile_view_history WHERE candidate_profile_id = v_prof) <> 0 THEN RAISE EXCEPTION 'FAIL: another organisation reads who viewed the profile'; END IF;
    IF (SELECT count(*) FROM profile.recruiter_bookmark) <> 0 THEN RAISE EXCEPTION 'FAIL: another organisation reads bookmarks'; END IF;
    EXECUTE 'RESET ROLE';
    RAISE NOTICE 'PASS: view history is shared with the candidate; bookmarks stay inside the organisation';

    -- 8. User-owned data: a user reads only their own preferences, tickets and consent
    INSERT INTO messaging.support_ticket (ticket_number, requester_user_account_id, category, subject, priority) VALUES ('TCK-CP-1', v_cand, 'account', 'help', 'low');
    INSERT INTO core.consent_record (user_account_id, consent_type, consent_version, is_granted) VALUES (v_cand, 'privacy_policy', 'v1', TRUE);
    EXECUTE 'SET LOCAL ROLE talentra_app';
    PERFORM set_config('app.current_user_id', v_cand2::TEXT, true);
    IF (SELECT count(*) FROM messaging.support_ticket WHERE ticket_number = 'TCK-CP-1') <> 0 OR (SELECT count(*) FROM core.consent_record WHERE user_account_id = v_cand) <> 0 THEN
        RAISE EXCEPTION 'FAIL: a user reads another user''s ticket or consent'; END IF;
    PERFORM set_config('app.current_user_id', v_cand::TEXT, true);
    IF (SELECT count(*) FROM messaging.support_ticket WHERE ticket_number = 'TCK-CP-1') <> 1 OR (SELECT count(*) FROM core.consent_record WHERE user_account_id = v_cand) <> 1 THEN
        RAISE EXCEPTION 'FAIL: a user cannot read their own ticket or consent'; END IF;
    EXECUTE 'RESET ROLE';
    RAISE NOTICE 'PASS: tickets and consent are visible to their owner only';

    DROP TABLE _visible;
    RAISE NOTICE '=== Candidate privacy tests passed ===';
END
$$;

ROLLBACK;
