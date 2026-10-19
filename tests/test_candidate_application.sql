-- Test suite: tests/test_candidate_application.sql
-- Prerequisite: migrations 001 through 009 have been applied.

BEGIN;

DO $test$
DECLARE
    v_candidate_user_id BIGINT;
    v_recruiter_user_id BIGINT;
    v_org_id BIGINT;
    v_candidate_profile_id BIGINT;
    v_job_posting_id BIGINT;
    v_application_id BIGINT;
    v_duplicate_blocked BOOLEAN := FALSE;
    v_history_count INTEGER := 0;
BEGIN
    ---------------------------------------------------------------------------
    -- 1. Setup test fixtures: candidate user & profile, recruiter user & org,
    --    and a job posting.
    ---------------------------------------------------------------------------
    INSERT INTO core.user_account (email)
    VALUES ('candidate_app_test@example.com')
    RETURNING id INTO v_candidate_user_id;

    INSERT INTO profile.candidate_profile (
        user_account_id,
        headline,
        total_experience_years,
        profile_status
    )
    VALUES (
        v_candidate_user_id,
        'Full Stack Engineer',
        4.0,
        'active'
    )
    RETURNING id INTO v_candidate_profile_id;

    INSERT INTO core.user_account (email)
    VALUES ('recruiter_app_test@example.com')
    RETURNING id INTO v_recruiter_user_id;

    INSERT INTO recruitment.organization (
        name,
        slug,
        organization_type,
        created_by_user_account_id
    )
    VALUES (
        'App Test Org',
        'app-test-org',
        'employer',
        v_recruiter_user_id
    )
    RETURNING id INTO v_org_id;

    INSERT INTO recruitment.organization_member (
        organization_id,
        user_account_id,
        organization_role,
        membership_status,
        joined_at
    )
    VALUES (
        v_org_id,
        v_recruiter_user_id,
        'recruiter',
        'active',
        CURRENT_TIMESTAMP
    );

    INSERT INTO recruitment.job_posting (
        organization_id,
        created_by_user_account_id,
        employment_type_id,
        work_type_id,
        title,
        description,
        job_status,
        published_at
    )
    SELECT
        v_org_id,
        v_recruiter_user_id,
        et.id,
        wt.id,
        'Senior Software Engineer',
        'Responsible for platform architecture and data engineering',
        'published',
        CURRENT_TIMESTAMP
    FROM master.employment_type AS et
    CROSS JOIN master.work_type AS wt
    WHERE et.code = 'full_time'
      AND wt.code = 'remote'
    RETURNING id INTO v_job_posting_id;

    IF v_job_posting_id IS NULL THEN
        RAISE EXCEPTION
            'Required master data not found: employment_type=full_time and work_type=remote';
    END IF;

    ---------------------------------------------------------------------------
    -- 2. Create an application and verify the generated identifier.
    ---------------------------------------------------------------------------
    INSERT INTO recruitment.candidate_application (
        candidate_profile_id,
        job_posting_id,
        application_status,
        application_source,
        created_by_user_account_id,
        updated_by_user_account_id
    )
    VALUES (
        v_candidate_profile_id,
        v_job_posting_id,
        'applied',
        'direct',
        v_candidate_user_id,
        v_candidate_user_id
    )
    RETURNING id INTO v_application_id;

    IF v_application_id IS NULL THEN
        RAISE EXCEPTION 'Application insert did not return an ID';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM recruitment.candidate_application
        WHERE id = v_application_id
          AND candidate_profile_id = v_candidate_profile_id
          AND job_posting_id = v_job_posting_id
          AND application_status = 'applied'
    ) THEN
        RAISE EXCEPTION 'Application was not persisted with expected values';
    END IF;

    ---------------------------------------------------------------------------
    -- 3. Duplicate application for the same candidate/job pair must be blocked.
    ---------------------------------------------------------------------------
    BEGIN
        INSERT INTO recruitment.candidate_application (
            candidate_profile_id,
            job_posting_id,
            application_status,
            application_source,
            created_by_user_account_id,
            updated_by_user_account_id
        )
        VALUES (
            v_candidate_profile_id,
            v_job_posting_id,
            'applied',
            'direct',
            v_candidate_user_id,
            v_candidate_user_id
        );
    EXCEPTION
        WHEN unique_violation THEN
            v_duplicate_blocked := TRUE;
    END;

    IF NOT v_duplicate_blocked THEN
        RAISE EXCEPTION
            'Duplicate application was accepted; expected unique candidate/job constraint';
    END IF;

    ---------------------------------------------------------------------------
    -- 4. Change status and verify the application row is updated.
    -- The migration''s status-history trigger should record this transition.
    ---------------------------------------------------------------------------
    UPDATE recruitment.candidate_application
    SET application_status = 'shortlisted',
        updated_by_user_account_id = v_recruiter_user_id,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = v_application_id;

    IF NOT EXISTS (
        SELECT 1
        FROM recruitment.candidate_application
        WHERE id = v_application_id
          AND application_status = 'shortlisted'
    ) THEN
        RAISE EXCEPTION 'Application status did not update to shortlisted';
    END IF;

    SELECT COUNT(*)
    INTO v_history_count
    FROM recruitment.application_status_history
    WHERE candidate_application_id = v_application_id;

    IF v_history_count < 2 THEN
        RAISE EXCEPTION
            'Expected initial application status plus status transition in history; found % row(s)',
            v_history_count;
    END IF;

    RAISE NOTICE 'PASS: fixture setup and application creation';
    RAISE NOTICE 'PASS: duplicate candidate/job application rejected';
    RAISE NOTICE 'PASS: application status update and history tracking';
END;
$test$;

-- Keep the database unchanged after the test run.
ROLLBACK;
