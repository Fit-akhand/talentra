-- Test suite: tests/test_job_posting_extras.sql
-- Covers: REQ-017, REQ-018, REQ-025, BR-012, BR-041, BR-042 (migration 040: department, locations, perks, qualifications, assigned recruiters, show-salary flag)
-- Isolation: runs in a transaction that is rolled back.

BEGIN;

DO $$
DECLARE
    v_admin BIGINT; v_org BIGINT; v_org2 BIGINT; v_rec BIGINT; v_billing BIGINT; v_agency BIGINT; v_cand BIGINT; v_job BIGINT; v_draft BIGINT;
    v_dept BIGINT; v_city1 BIGINT; v_city2 BIGINT; v_perk BIGINT; v_qual BIGINT; v_n INTEGER; v_caught BOOLEAN; v_emp BIGINT; v_wt BIGINT;
BEGIN
    SELECT id INTO v_admin FROM core.user_account ORDER BY id LIMIT 1;
    SELECT id INTO v_dept FROM master.department ORDER BY id LIMIT 1;
    SELECT id INTO v_city1 FROM master.city ORDER BY id LIMIT 1;
    SELECT id INTO v_city2 FROM master.city ORDER BY id OFFSET 1 LIMIT 1;
    SELECT id INTO v_perk FROM master.job_perk WHERE code = 'relocation_benefits';
    SELECT id INTO v_qual FROM master.qualification ORDER BY id OFFSET 4 LIMIT 1;
    SELECT id INTO v_emp FROM master.employment_type ORDER BY id LIMIT 1;
    SELECT id INTO v_wt FROM master.work_type ORDER BY id LIMIT 1;
    INSERT INTO core.user_account (email, account_status) VALUES ('p40_rec@example.com', 'active') RETURNING id INTO v_rec;
    INSERT INTO core.user_account (email, account_status) VALUES ('p40_bill@example.com', 'active') RETURNING id INTO v_billing;
    INSERT INTO core.user_account (email, account_status) VALUES ('p40_agency@example.com', 'active') RETURNING id INTO v_agency;
    INSERT INTO core.user_account (email, account_status) VALUES ('p40_cand@example.com', 'active') RETURNING id INTO v_cand;
    INSERT INTO recruitment.organization (name, slug, organization_type, created_by_user_account_id) VALUES ('P40 Org', 'p40-org', 'employer', v_admin) RETURNING id INTO v_org;
    INSERT INTO recruitment.organization (name, slug, organization_type, created_by_user_account_id) VALUES ('P40 Other', 'p40-other', 'employer', v_admin) RETURNING id INTO v_org2;
    INSERT INTO recruitment.organization_member (organization_id, user_account_id, organization_role, membership_status, joined_at) VALUES
        (v_org, v_rec, 'recruiter', 'active', now()), (v_org, v_billing, 'billing_manager', 'active', now());
    INSERT INTO recruitment.job_posting (organization_id, created_by_user_account_id, employment_type_id, work_type_id, title, description, job_status, published_at, salary_min, salary_max, currency_code, salary_period)
    VALUES (v_org, v_rec, v_emp, v_wt, 'P40 published', 'd', 'published', now(), 800000, 1000000, 'INR', 'year') RETURNING id INTO v_job;
    INSERT INTO recruitment.job_posting (organization_id, created_by_user_account_id, employment_type_id, work_type_id, title, description, job_status)
    VALUES (v_org, v_rec, v_emp, v_wt, 'P40 draft', 'd', 'draft') RETURNING id INTO v_draft;

    -- 1. show_salary needs a salary; the default keeps it private
    IF (SELECT show_salary FROM recruitment.job_posting WHERE id = v_job) THEN RAISE EXCEPTION 'FAIL: show_salary should default to FALSE'; END IF;
    v_caught := FALSE;
    BEGIN UPDATE recruitment.job_posting SET show_salary = TRUE WHERE id = v_draft; EXCEPTION WHEN check_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: show_salary was set on a job with no salary'; END IF;
    UPDATE recruitment.job_posting SET show_salary = TRUE, department_id = v_dept, has_variable_pay = TRUE WHERE id = v_job;
    RAISE NOTICE 'PASS: salary is private by default, and cannot be shown when there is none';

    -- 2. locations, perks, qualifications: one of each per job, duplicates refused
    INSERT INTO recruitment.job_posting_location (job_posting_id, city_id) VALUES (v_job, v_city1), (v_job, v_city2);
    INSERT INTO recruitment.job_posting_perk (job_posting_id, job_perk_id) VALUES (v_job, v_perk);
    INSERT INTO recruitment.job_qualification_requirement (job_posting_id, qualification_id, field_of_study) VALUES (v_job, v_qual, 'Computer Science');
    v_caught := FALSE;
    BEGIN INSERT INTO recruitment.job_posting_location (job_posting_id, city_id) VALUES (v_job, v_city1); EXCEPTION WHEN unique_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: the same city was added twice to one job'; END IF;
    v_caught := FALSE;
    BEGIN INSERT INTO recruitment.job_qualification_requirement (job_posting_id, qualification_id, field_of_study) VALUES (v_job, v_qual, ' computer science '); EXCEPTION WHEN unique_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: the same qualification and field was added twice (case and spaces ignored)'; END IF;
    RAISE NOTICE 'PASS: locations, perks and qualification requirements are unique per job';

    -- 3. recruiter assignment: only recruiters of the organisation, or an agency recruiter mapped to it as a client
    INSERT INTO recruitment.job_recruiter_assignment (job_posting_id, recruiter_user_account_id, assigned_by_user_account_id) VALUES (v_job, v_rec, v_rec);
    v_caught := FALSE;
    BEGIN INSERT INTO recruitment.job_recruiter_assignment (job_posting_id, recruiter_user_account_id) VALUES (v_job, v_billing); EXCEPTION WHEN check_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: a billing manager was assigned as recruiter'; END IF;
    v_caught := FALSE;
    BEGIN INSERT INTO recruitment.job_recruiter_assignment (job_posting_id, recruiter_user_account_id) VALUES (v_job, v_agency); EXCEPTION WHEN check_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: an unrelated agency recruiter was assigned'; END IF;
    INSERT INTO recruitment.recruiter_client_mapping (recruiter_user_account_id, client_organization_id, effective_from, is_active) VALUES (v_agency, v_org, CURRENT_DATE - 5, TRUE);
    INSERT INTO recruitment.job_recruiter_assignment (job_posting_id, recruiter_user_account_id) VALUES (v_job, v_agency);
    RAISE NOTICE 'PASS: assigned recruiters must belong to the organisation or be mapped to it as a client';

    -- 4. row-level security: a published job's perks are public; a draft's are the organisation's
    INSERT INTO recruitment.job_posting_perk (job_posting_id, job_perk_id) VALUES (v_draft, v_perk);
    INSERT INTO core.user_account (email, account_status) VALUES ('p40_outsider@example.com', 'active') RETURNING id INTO v_n;
    EXECUTE 'SET LOCAL ROLE talentra_app';
    PERFORM set_config('app.current_user_id', v_cand::TEXT, true);
    PERFORM set_config('app.current_org_id', '', true);
    SELECT count(*) INTO v_n FROM recruitment.job_posting_perk WHERE job_posting_id IN (v_job, v_draft);
    IF v_n <> 1 THEN RAISE EXCEPTION 'FAIL: an outsider sees % perk rows, expected only the published job''s', v_n; END IF;
    v_caught := FALSE;
    BEGIN INSERT INTO recruitment.job_posting_perk (job_posting_id, job_perk_id) VALUES (v_job, (SELECT id FROM master.job_perk WHERE code = 'cafeteria')); EXCEPTION WHEN insufficient_privilege OR others THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: an outsider added a perk to someone else''s job'; END IF;
    SELECT count(*) INTO v_n FROM recruitment.job_recruiter_assignment WHERE job_posting_id = v_job;
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL: an outsider sees % recruiter assignments', v_n; END IF;
    EXECUTE 'RESET ROLE';
    RAISE NOTICE 'PASS: a job''s children follow the job''s visibility, and only its organisation writes them';
END $$;

ROLLBACK;
