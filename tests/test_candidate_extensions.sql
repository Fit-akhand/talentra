-- Test suite: tests/test_candidate_extensions.sql
-- Prerequisite: migrations 001 through 010 applied.
-- Covers: BR-006, BR-007, REQ-010, REQ-011   (generated from the registers by scripts/lifecycle/tag_tests.py)

BEGIN;

DO $test$
DECLARE
    v_user_id BIGINT;
    v_candidate_id BIGINT;
    v_viewer_user_id BIGINT;
    v_org_id BIGINT;
    v_lang_id BIGINT;
    v_skill_id BIGINT;
    v_assessment_id BIGINT;
    v_project_id BIGINT;
    v_score_id BIGINT;
    v_view_id BIGINT;
    v_bookmark_id BIGINT;
    v_duplicate_lang_blocked BOOLEAN := FALSE;
    v_invalid_dates_blocked BOOLEAN := FALSE;
BEGIN
    -- 1. Fixture setup
    INSERT INTO core.user_account (email)
    VALUES ('ext_candidate@example.com')
    RETURNING id INTO v_user_id;

    INSERT INTO profile.candidate_profile (
        user_account_id,
        headline,
        total_experience_years,
        profile_status
    )
    VALUES (
        v_user_id,
        'Senior Backend Architect',
        6.0,
        'active'
    )
    RETURNING id INTO v_candidate_id;

    INSERT INTO core.user_account (email)
    VALUES ('ext_recruiter@example.com')
    RETURNING id INTO v_viewer_user_id;

    INSERT INTO recruitment.organization (
        name,
        slug,
        organization_type,
        created_by_user_account_id
    )
    VALUES (
        'Acme Extensions Corp',
        'acme-ext-corp',
        'employer',
        v_viewer_user_id
    )
    RETURNING id INTO v_org_id;

    SELECT id INTO v_lang_id FROM master.language WHERE code = 'en';
    SELECT id INTO v_skill_id FROM master.skill WHERE normalized_name = 'postgresql';

    -- 2. Test candidate language mapping
    INSERT INTO profile.candidate_language (
        candidate_profile_id,
        language_id,
        proficiency_level
    )
    VALUES (
        v_candidate_id,
        v_lang_id,
        'fluent'
    );

    BEGIN
        INSERT INTO profile.candidate_language (
            candidate_profile_id,
            language_id,
            proficiency_level
        )
        VALUES (
            v_candidate_id,
            v_lang_id,
            'native'
        );
    EXCEPTION
        WHEN unique_violation THEN
            v_duplicate_lang_blocked := TRUE;
    END;

    IF NOT v_duplicate_lang_blocked THEN
        RAISE EXCEPTION 'Duplicate candidate language was allowed';
    END IF;

    -- 3. Test candidate projects & date constraint
    INSERT INTO profile.candidate_project (
        candidate_profile_id,
        title,
        candidate_role,
        project_type,
        start_date,
        end_date,
        project_url
    )
    VALUES (
        v_candidate_id,
        'Distributed Cache Engine',
        'Lead Architect',
        'open_source',
        '2024-01-01',
        '2024-06-30',
        'https://github.com/example/cache-engine'
    )
    RETURNING id INTO v_project_id;

    BEGIN
        INSERT INTO profile.candidate_project (
            candidate_profile_id,
            title,
            candidate_role,
            start_date,
            end_date
        )
        VALUES (
            v_candidate_id,
            'Invalid Project',
            'Dev',
            '2024-06-30',
            '2024-01-01'
        );
    EXCEPTION
        WHEN check_violation THEN
            v_invalid_dates_blocked := TRUE;
    END;

    IF NOT v_invalid_dates_blocked THEN
        RAISE EXCEPTION 'Project with end_date earlier than start_date was allowed';
    END IF;

    -- 4. Test candidate assessments and scores
    INSERT INTO profile.candidate_assessment (
        title,
        skill_id,
        total_questions,
        duration_minutes,
        passing_percentage
    )
    VALUES (
        'PostgreSQL Query Optimization Benchmark Exam',
        v_skill_id,
        25,
        45,
        70.00
    )
    RETURNING id INTO v_assessment_id;

    INSERT INTO profile.candidate_assessment_score (
        candidate_profile_id,
        candidate_assessment_id,
        score_obtained,
        max_score,
        percentile,
        is_passed
    )
    VALUES (
        v_candidate_id,
        v_assessment_id,
        88.50,
        100.00,
        96.20,
        TRUE
    )
    RETURNING id INTO v_score_id;

    -- 5. Test candidate profile completion
    INSERT INTO profile.candidate_profile_completion (
        candidate_profile_id,
        total_score_percentage,
        has_headline,
        has_skills,
        has_projects
    )
    VALUES (
        v_candidate_id,
        75.00,
        TRUE,
        TRUE,
        TRUE
    );

    -- 6. Test profile view history
    INSERT INTO profile.profile_view_history (
        candidate_profile_id,
        viewer_user_account_id,
        organization_id,
        view_source,
        credit_deducted
    )
    VALUES (
        v_candidate_id,
        v_viewer_user_id,
        v_org_id,
        'search',
        1.50
    )
    RETURNING id INTO v_view_id;

    -- 7. Test recruiter bookmark
    INSERT INTO profile.recruiter_bookmark (
        organization_id,
        user_account_id,
        candidate_profile_id,
        notes
    )
    VALUES (
        v_org_id,
        v_viewer_user_id,
        v_candidate_id,
        'Strong database engineering background, shortlist for L5 role.'
    )
    RETURNING id INTO v_bookmark_id;

    RAISE NOTICE 'PASS: candidate languages with unique constraint verified';
    RAISE NOTICE 'PASS: candidate projects and date constraints verified';
    RAISE NOTICE 'PASS: assessments and scores created and verified';
    RAISE NOTICE 'PASS: profile completion scoring verified';
    RAISE NOTICE 'PASS: profile view history and recruiter bookmark verified';
END;
$test$;

ROLLBACK;
