-- Test: test_constraints.sql
-- Domain: All Schemas / Rule Group 3 & 4
-- Covers: DATA-001, DATA-004   (generated from the registers by scripts/lifecycle/tag_tests.py)
-- Purpose: Verify domain standard check constraints, regexes, temporal ranges, and uniqueness rules.
-- Engine: PostgreSQL 17

BEGIN;

DO $$
DECLARE
    v_user_id BIGINT;
    v_cand_id BIGINT;
    v_city_id BIGINT;
    v_emp_id BIGINT;
    v_work_id BIGINT;
    v_org_id BIGINT;
    v_err_caught BOOLEAN := FALSE;
    v_country_id BIGINT;
    v_state_id BIGINT;
BEGIN
    RAISE NOTICE '=== Running Domain Standard Constraints Tests ===';

    SELECT id INTO v_city_id FROM master.city LIMIT 1;
    SELECT id INTO v_emp_id FROM master.employment_type LIMIT 1;
    SELECT id INTO v_work_id FROM master.work_type LIMIT 1;

    IF v_city_id IS NULL THEN
        INSERT INTO master.country (iso_alpha2, iso_alpha3, name)
        VALUES ('TC', 'TCC', 'Test Constraint Country')
        ON CONFLICT (iso_alpha2) DO UPDATE SET name = EXCLUDED.name
        RETURNING id INTO v_country_id;

        IF v_country_id IS NULL THEN
            SELECT id INTO v_country_id FROM master.country WHERE iso_alpha2 = 'TC';
        END IF;

        INSERT INTO master.state (country_id, name, subdivision_code)
        VALUES (v_country_id, 'Test Constraint State', 'TC-01')
        RETURNING id INTO v_state_id;

        IF v_state_id IS NULL THEN
            SELECT id INTO v_state_id FROM master.state WHERE country_id = v_country_id LIMIT 1;
        END IF;

        INSERT INTO master.city (state_id, name)
        VALUES (v_state_id, 'Test Constraint City')
        RETURNING id INTO v_city_id;

        IF v_city_id IS NULL THEN
            SELECT id INTO v_city_id FROM master.city WHERE state_id = v_state_id LIMIT 1;
        END IF;
    END IF;

    IF v_emp_id IS NULL THEN
        INSERT INTO master.employment_type (code, name)
        VALUES ('test_full_time', 'Test Full-Time')
        ON CONFLICT (code) DO NOTHING;
        SELECT id INTO v_emp_id FROM master.employment_type WHERE code = 'test_full_time';
    END IF;

    IF v_work_id IS NULL THEN
        INSERT INTO master.work_type (code, name)
        VALUES ('test_remote', 'Test Remote')
        ON CONFLICT (code) DO NOTHING;
        SELECT id INTO v_work_id FROM master.work_type WHERE code = 'test_remote';
    END IF;

    -- 1. Test Email Format Constraint (RFC check, reject invalid or uppercase)
    v_err_caught := FALSE;
    BEGIN
        INSERT INTO core.user_account (email, account_status)
        VALUES ('INVALID_UPPERCASE_EMAIL@EXAMPLE.COM', 'active');
    EXCEPTION WHEN OTHERS THEN
        v_err_caught := TRUE;
    END;
    ASSERT v_err_caught = TRUE, 'FAILED: Uppercase email should violate ck_user_account_email_format';
    RAISE NOTICE 'PASS: ck_user_account_email_format correctly rejected uppercase email';

    v_err_caught := FALSE;
    BEGIN
        INSERT INTO core.user_account (email, account_status)
        VALUES ('not-an-email-string', 'active');
    EXCEPTION WHEN OTHERS THEN
        v_err_caught := TRUE;
    END;
    ASSERT v_err_caught = TRUE, 'FAILED: Malformed email should violate ck_user_account_email_format';
    RAISE NOTICE 'PASS: ck_user_account_email_format correctly rejected malformed email';

    -- 2. Test E.164 Phone Format Constraint (^\+[1-9]\d{1,14}$)
    v_err_caught := FALSE;
    BEGIN
        INSERT INTO core.user_account (email, phone_e164, account_status)
        VALUES ('test_phone_bad@example.com', '1234567890', 'active'); -- missing leading +
    EXCEPTION WHEN OTHERS THEN
        v_err_caught := TRUE;
    END;
    ASSERT v_err_caught = TRUE, 'FAILED: Missing + prefix on phone should violate ck_user_account_phone_e164';
    RAISE NOTICE 'PASS: ck_user_account_phone_e164 correctly rejected phone lacking + prefix';

    -- Create valid user and candidate profile for subsequent constraint tests
    INSERT INTO core.user_account (email, phone_e164, phone_country_code, account_status)
    VALUES ('valid_constraints_user@example.com', '+14155552671', 'US', 'active')
    RETURNING id INTO v_user_id;

    INSERT INTO profile.candidate_profile (user_account_id, headline, visibility)
    VALUES (v_user_id, 'Lead Database Architect', 'public')
    RETURNING id INTO v_cand_id;

    INSERT INTO recruitment.organization (name, slug, organization_type, created_by_user_account_id)
    VALUES ('Constraint Test Org', 'constraint-test-org-unique', 'employer', v_user_id)
    RETURNING id INTO v_org_id;

    -- 3. Test Candidate Location Partial Unique Index: at most ONE current city per candidate
    INSERT INTO profile.candidate_location (candidate_profile_id, city_id, location_type)
    VALUES (v_cand_id, v_city_id, 'current');

    v_err_caught := FALSE;
    BEGIN
        -- Attempt to insert a second current city for the same candidate
        INSERT INTO profile.candidate_location (candidate_profile_id, city_id, location_type)
        VALUES (v_cand_id, v_city_id, 'current');
    EXCEPTION WHEN OTHERS THEN
        v_err_caught := TRUE;
    END;
    ASSERT v_err_caught = TRUE, 'FAILED: Multiple current cities should violate uq_candidate_location_current';
    RAISE NOTICE 'PASS: uq_candidate_location_current correctly prevented duplicate current city';

    -- 4. Test Temporal Chronology on Candidate Experience (end_date >= start_date)
    v_err_caught := FALSE;
    BEGIN
        INSERT INTO profile.candidate_work_experience (
            candidate_profile_id, company_name, job_title, start_date, end_date
        ) VALUES (
            v_cand_id, 'Old Tech Corp', 'Senior Engineer', '2025-06-01', '2024-01-01' -- Inverted dates
        );
    EXCEPTION WHEN OTHERS THEN
        v_err_caught := TRUE;
    END;
    ASSERT v_err_caught = TRUE, 'FAILED: Inverted experience dates should violate ck_candidate_work_experience_dates';
    RAISE NOTICE 'PASS: ck_candidate_work_experience_dates correctly rejected inverted dates';

    -- 5. Test Job Posting Salary Constraints (salary_max >= salary_min and salary_min >= 0)
    v_err_caught := FALSE;
    BEGIN
        INSERT INTO recruitment.job_posting (
            organization_id, created_by_user_account_id, employment_type_id, work_type_id,
            title, description, salary_min, salary_max, currency_code
        ) VALUES (
            v_org_id, v_user_id, v_emp_id, v_work_id,
            'Inverted Salary Role', 'Desc', 150000, 100000, 'USD' -- max < min
        );
    EXCEPTION WHEN OTHERS THEN
        v_err_caught := TRUE;
    END;
    ASSERT v_err_caught = TRUE, 'FAILED: salary_max < salary_min should violate ck_job_posting_salary_range';
    RAISE NOTICE 'PASS: ck_job_posting_salary_range correctly rejected salary_max < salary_min';

    -- 6. Test ISO Currency Code Constraint (must be exactly 3 uppercase letters)
    v_err_caught := FALSE;
    BEGIN
        INSERT INTO recruitment.job_posting (
            organization_id, created_by_user_account_id, employment_type_id, work_type_id,
            title, description, salary_min, salary_max, currency_code
        ) VALUES (
            v_org_id, v_user_id, v_emp_id, v_work_id,
            'Invalid Currency Role', 'Desc', 80000, 120000, 'usd' -- lowercase currency
        );
    EXCEPTION WHEN OTHERS THEN
        v_err_caught := TRUE;
    END;
    ASSERT v_err_caught = TRUE, 'FAILED: Lowercase currency should violate ck_job_posting_currency';
    RAISE NOTICE 'PASS: ck_job_posting_currency correctly rejected lowercase currency';

    -- 7. Test Gig Request Budget & Date Constraints
    v_err_caught := FALSE;
    BEGIN
        INSERT INTO gig.gig_request (
            organization_id, created_by_user_account_id, title, description,
            pricing_type, budget_amount, currency_code, start_date, end_date
        ) VALUES (
            v_org_id, v_user_id, 'Negative Budget Gig', 'Desc',
            'fixed', -500.00, 'USD', '2026-11-01', '2026-11-30'
        );
    EXCEPTION WHEN OTHERS THEN
        v_err_caught := TRUE;
    END;
    ASSERT v_err_caught = TRUE, 'FAILED: Negative budget should violate ck_gig_request_budget';
    RAISE NOTICE 'PASS: ck_gig_request_budget correctly rejected negative budget';

    RAISE NOTICE '=== All Domain Standard Constraints Tests Passed Successfully ===';
END;
$$;

ROLLBACK;
