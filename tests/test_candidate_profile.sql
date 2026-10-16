
BEGIN;

DO $$
DECLARE
    v_user_id BIGINT;
    v_candidate_id BIGINT;
    v_skill_id BIGINT;
    v_qualification_id BIGINT;
    v_employment_type_id BIGINT;
    v_country_id BIGINT;
    v_state_id BIGINT;
    v_city_id BIGINT;
BEGIN
    SELECT id INTO v_skill_id
    FROM master.skill
    WHERE normalized_name = 'postgresql';

    SELECT id INTO v_qualification_id
    FROM master.qualification
    WHERE qualification_level = 'undergraduate'
    ORDER BY id
    LIMIT 1;

    SELECT id INTO v_employment_type_id
    FROM master.employment_type
    WHERE code = 'full_time';

    IF v_skill_id IS NULL
       OR v_qualification_id IS NULL
       OR v_employment_type_id IS NULL THEN
        RAISE EXCEPTION
            'Prerequisite reference data missing; apply Migration 004 first';
    END IF;

    INSERT INTO core.user_account (email)
    VALUES ('migration005-test@example.invalid')
    RETURNING id INTO v_user_id;

    INSERT INTO profile.candidate_profile (
        user_account_id,
        headline,
        total_experience_years,
        profile_status
    )
    VALUES (
        v_user_id,
        'Database Engineer',
        3.5,
        'active'
    )
    RETURNING id INTO v_candidate_id;

    RAISE NOTICE 'PASS: candidate profile created';

    -- Enforce one profile per account.
    BEGIN
        INSERT INTO profile.candidate_profile (user_account_id)
        VALUES (v_user_id);

        RAISE EXCEPTION 'FAIL: duplicate candidate profile accepted';
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE 'PASS: duplicate profile rejected';
    END;

    -- Invalid experience must fail.
    BEGIN
        INSERT INTO profile.candidate_profile (
            user_account_id, total_experience_years
        )
        VALUES (v_user_id + 999999, -1);

        RAISE EXCEPTION 'FAIL: negative experience accepted';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS: invalid experience rejected';
    END;

    INSERT INTO profile.candidate_skill (
        candidate_profile_id,
        skill_id,
        proficiency_level,
        experience_years,
        is_primary
    )
    VALUES (
        v_candidate_id,
        v_skill_id,
        'advanced',
        3.0,
        TRUE
    );

    -- Duplicate skill for the same candidate must fail.
    BEGIN
        INSERT INTO profile.candidate_skill (
            candidate_profile_id, skill_id
        )
        VALUES (v_candidate_id, v_skill_id);

        RAISE EXCEPTION 'FAIL: duplicate candidate skill accepted';
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE 'PASS: duplicate candidate skill rejected';
    END;

    -- Education end date before start date must fail.
    BEGIN
        INSERT INTO profile.candidate_education (
            candidate_profile_id,
            qualification_id,
            institution_name,
            start_date,
            end_date
        )
        VALUES (
            v_candidate_id,
            v_qualification_id,
            'Test University',
            DATE '2024-01-01',
            DATE '2023-01-01'
        );

        RAISE EXCEPTION 'FAIL: invalid education dates accepted';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS: invalid education dates rejected';
    END;

    INSERT INTO profile.candidate_education (
        candidate_profile_id,
        qualification_id,
        institution_name,
        field_of_study,
        start_date,
        end_date
    )
    VALUES (
        v_candidate_id,
        v_qualification_id,
        'Test University',
        'Computer Science',
        DATE '2022-08-01',
        DATE '2026-06-30'
    );

    INSERT INTO profile.candidate_work_experience (
        candidate_profile_id,
        employer_name,
        job_title,
        employment_type_id,
        start_date,
        is_current
    )
    VALUES (
        v_candidate_id,
        'Test Employer',
        'Software Engineer',
        v_employment_type_id,
        DATE '2025-01-01',
        TRUE
    );

    -- Create a temporary geographic hierarchy.
    INSERT INTO master.country (iso_alpha2, iso_alpha3, name)
    VALUES ('TX', 'TXX', 'Migration Test Country')
    RETURNING id INTO v_country_id;

    INSERT INTO master.state (country_id, name)
    VALUES (v_country_id, 'Migration Test State')
    RETURNING id INTO v_state_id;

    INSERT INTO master.city (state_id, name)
    VALUES (v_state_id, 'Migration Test City')
    RETURNING id INTO v_city_id;

    INSERT INTO profile.candidate_location (
        candidate_profile_id, city_id, location_type
    )
    VALUES (v_candidate_id, v_city_id, 'current');

    -- A second current city must fail.
    BEGIN
        INSERT INTO profile.candidate_location (
            candidate_profile_id, city_id, location_type
        )
        VALUES (v_candidate_id, v_city_id, 'current');

        RAISE EXCEPTION 'FAIL: duplicate current location accepted';
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE 'PASS: duplicate current location rejected';
    END;

    RAISE NOTICE 'PASS: education and work experience created';
    RAISE NOTICE 'PASS: current location constraint verified';
END
$$;

ROLLBACK;
