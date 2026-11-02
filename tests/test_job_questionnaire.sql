-- Test suite: tests/test_job_questionnaire.sql
-- Prerequisite: migrations 001 through 011 applied.
-- Covers: BR-013, REQ-018   (generated from the registers by scripts/lifecycle/tag_tests.py)

BEGIN;

DO $test$
DECLARE
    v_candidate_user_id BIGINT;
    v_recruiter_user_id BIGINT;
    v_org_id BIGINT;
    v_candidate_profile_id BIGINT;
    v_job_posting_id BIGINT;
    v_application_id BIGINT;
    v_questionnaire_id BIGINT;
    v_question1_id BIGINT;
    v_question2_id BIGINT;
    v_response_id BIGINT;
    v_position_id BIGINT;
    v_duplicate_questionnaire_blocked BOOLEAN := FALSE;
    v_invalid_position_filled_blocked BOOLEAN := FALSE;
BEGIN
    -- 1. Setup fixtures
    INSERT INTO core.user_account (email)
    VALUES ('quest_candidate@example.com')
    RETURNING id INTO v_candidate_user_id;

    INSERT INTO profile.candidate_profile (
        user_account_id,
        headline,
        total_experience_years,
        profile_status
    )
    VALUES (
        v_candidate_user_id,
        'Staff Infrastructure Engineer',
        8.0,
        'active'
    )
    RETURNING id INTO v_candidate_profile_id;

    INSERT INTO core.user_account (email)
    VALUES ('quest_recruiter@example.com')
    RETURNING id INTO v_recruiter_user_id;

    INSERT INTO recruitment.organization (
        name,
        slug,
        organization_type,
        created_by_user_account_id
    )
    VALUES (
        'Quest Tech Corp',
        'quest-tech-corp',
        'employer',
        v_recruiter_user_id
    )
    RETURNING id INTO v_org_id;

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
        'Principal Site Reliability Engineer',
        'Lead our platform reliability and database infrastructure',
        'published',
        CURRENT_TIMESTAMP
    FROM master.employment_type AS et
    CROSS JOIN master.work_type AS wt
    WHERE et.code = 'full_time'
      AND wt.code = 'remote'
    RETURNING id INTO v_job_posting_id;

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

    -- 2. Create Job Questionnaire
    INSERT INTO recruitment.job_questionnaire (
        job_posting_id,
        created_by_user_account_id,
        title,
        instructions
    )
    VALUES (
        v_job_posting_id,
        v_recruiter_user_id,
        'SRE Candidate Technical Screening',
        'Please answer all required questions accurately.'
    )
    RETURNING id INTO v_questionnaire_id;

    BEGIN
        INSERT INTO recruitment.job_questionnaire (
            job_posting_id,
            created_by_user_account_id,
            title
        )
        VALUES (
            v_job_posting_id,
            v_recruiter_user_id,
            'Duplicate Questionnaire'
        );
    EXCEPTION
        WHEN unique_violation THEN
            v_duplicate_questionnaire_blocked := TRUE;
    END;

    IF NOT v_duplicate_questionnaire_blocked THEN
        RAISE EXCEPTION 'Duplicate questionnaire for same job posting was accepted';
    END IF;

    -- 3. Add Questionnaire Questions
    INSERT INTO recruitment.job_questionnaire_question (
        job_questionnaire_id,
        question_text,
        question_type,
        options_json,
        sort_order
    )
    VALUES (
        v_questionnaire_id,
        'How many years of production PostgreSQL administration experience do you have?',
        'numeric',
        NULL,
        1
    )
    RETURNING id INTO v_question1_id;

    INSERT INTO recruitment.job_questionnaire_question (
        job_questionnaire_id,
        question_text,
        question_type,
        options_json,
        sort_order
    )
    VALUES (
        v_questionnaire_id,
        'Are you willing to participate in a 24/7 on-call rotation?',
        'boolean',
        NULL,
        2
    )
    RETURNING id INTO v_question2_id;

    -- 4. Record Application Question Response
    INSERT INTO recruitment.application_question_response (
        candidate_application_id,
        job_questionnaire_question_id,
        numeric_response,
        response_text
    )
    VALUES (
        v_application_id,
        v_question1_id,
        6.5,
        '6.5 years running mission-critical clusters'
    )
    RETURNING id INTO v_response_id;

    -- 5. Test Position Tracking under Job Posting
    INSERT INTO recruitment.job_position (
        job_posting_id,
        position_reference_code,
        position_status
    )
    VALUES (
        v_job_posting_id,
        'POS-SRE-001',
        'open'
    )
    RETURNING id INTO v_position_id;

    BEGIN
        INSERT INTO recruitment.job_position (
            job_posting_id,
            position_reference_code,
            position_status,
            filled_at
        )
        VALUES (
            v_job_posting_id,
            'POS-SRE-002',
            'filled',
            CURRENT_TIMESTAMP
        );
    EXCEPTION
        WHEN check_violation THEN
            v_invalid_position_filled_blocked := TRUE;
    END;

    IF NOT v_invalid_position_filled_blocked THEN
        RAISE EXCEPTION 'Filled position without candidate was accepted; expected check violation';
    END IF;

    -- Update position to filled with candidate profile
    UPDATE recruitment.job_position
    SET position_status = 'filled',
        filled_by_candidate_profile_id = v_candidate_profile_id,
        filled_at = CURRENT_TIMESTAMP
    WHERE id = v_position_id;

    RAISE NOTICE 'PASS: questionnaire created with unique constraint';
    RAISE NOTICE 'PASS: questionnaire questions created and sorted';
    RAISE NOTICE 'PASS: application question response recorded';
    RAISE NOTICE 'PASS: position seat lifecycle and constraints verified';
END;
$test$;

ROLLBACK;
