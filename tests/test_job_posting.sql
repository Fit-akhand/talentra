
-- Covers: BR-012, REQ-017   (generated from the registers by scripts/lifecycle/tag_tests.py)
BEGIN;

DO $$
DECLARE
    v_user_id BIGINT;
    v_organization_id BIGINT;
    v_job_id BIGINT;
    v_employment_type_id BIGINT;
    v_work_type_id BIGINT;
    v_skill_id BIGINT;
    v_second_skill_id BIGINT;
BEGIN
    SELECT id INTO v_employment_type_id
    FROM master.employment_type
    WHERE code = 'full_time';

    SELECT id INTO v_second_skill_id
    FROM master.skill
    WHERE normalized_name = 'javascript';

    SELECT id INTO v_work_type_id
    FROM master.work_type
    WHERE code = 'remote';

    SELECT id INTO v_skill_id
    FROM master.skill
    WHERE normalized_name = 'postgresql';

    IF v_employment_type_id IS NULL
       OR v_work_type_id IS NULL
       OR v_skill_id IS NULL THEN
        RAISE EXCEPTION
            'Prerequisite master data missing; apply Migration 004 first';
    END IF;

    INSERT INTO core.user_account (email)
    VALUES ('migration008-test@example.invalid')
    RETURNING id INTO v_user_id;

    INSERT INTO recruitment.organization (
        name,
        slug,
        created_by_user_account_id,
        organization_status
    )
    VALUES (
        'Migration 008 Test Organization',
        'migration-008-test-organization',
        v_user_id,
        'active'
    )
    RETURNING id INTO v_organization_id;

    INSERT INTO recruitment.job_posting (
        organization_id,
        created_by_user_account_id,
        employment_type_id,
        work_type_id,
        title,
        description
    )
    VALUES (
        v_organization_id,
        v_user_id,
        v_employment_type_id,
        v_work_type_id,
        'Database Engineer',
        'Design and optimize relational databases.'
    )
    RETURNING id INTO v_job_id;

    RAISE NOTICE 'PASS: valid draft job created';

    -- Invalid salary range must fail.
    BEGIN
        INSERT INTO recruitment.job_posting (
            organization_id,
            created_by_user_account_id,
            employment_type_id,
            work_type_id,
            title,
            description,
            currency_code,
            salary_min,
            salary_max,
            salary_period
        )
        VALUES (
            v_organization_id,
            v_user_id,
            v_employment_type_id,
            v_work_type_id,
            'Invalid Salary Job',
            'Test invalid salary range.',
            'USD',
            100000,
            50000,
            'year'
        );

        RAISE EXCEPTION 'FAIL: invalid salary range accepted';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS: invalid salary range rejected';
    END;

    -- Salary values without a currency and period must fail.
    BEGIN
        INSERT INTO recruitment.job_posting (
            organization_id,
            created_by_user_account_id,
            employment_type_id,
            work_type_id,
            title,
            description,
            salary_min
        )
        VALUES (
            v_organization_id,
            v_user_id,
            v_employment_type_id,
            v_work_type_id,
            'Missing Currency Job',
            'Test missing salary metadata.',
            50000
        );

        RAISE EXCEPTION 'FAIL: salary without currency accepted';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS: incomplete salary metadata rejected';
    END;

    -- Published jobs must have a publication timestamp.
    BEGIN
        INSERT INTO recruitment.job_posting (
            organization_id,
            created_by_user_account_id,
            employment_type_id,
            work_type_id,
            title,
            description,
            job_status
        )
        VALUES (
            v_organization_id,
            v_user_id,
            v_employment_type_id,
            v_work_type_id,
            'Missing Publication Timestamp',
            'Test publication constraint.',
            'published'
        );

        RAISE EXCEPTION 'FAIL: published job without timestamp accepted';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS: publication timestamp enforced';
    END;

    -- Closed jobs must have a closure timestamp.
    BEGIN
        INSERT INTO recruitment.job_posting (
            organization_id,
            created_by_user_account_id,
            employment_type_id,
            work_type_id,
            title,
            description,
            job_status
        )
        VALUES (
            v_organization_id,
            v_user_id,
            v_employment_type_id,
            v_work_type_id,
            'Missing Closure Timestamp',
            'Test closure constraint.',
            'closed'
        );

        RAISE EXCEPTION 'FAIL: closed job without timestamp accepted';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS: closure timestamp enforced';
    END;

    INSERT INTO recruitment.job_skill_requirement (
        job_posting_id,
        skill_id,
        is_required,
        minimum_proficiency_level,
        minimum_experience_years
    )
    VALUES (
        v_job_id,
        v_skill_id,
        TRUE,
        'advanced',
        2.0
    );

    RAISE NOTICE 'PASS: job skill requirement created';

    -- The same skill cannot be attached twice to one job.
    BEGIN
        INSERT INTO recruitment.job_skill_requirement (
            job_posting_id,
            skill_id
        )
        VALUES (v_job_id, v_skill_id);

        RAISE EXCEPTION 'FAIL: duplicate job skill accepted';
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE 'PASS: duplicate job skill rejected';
    END;

    -- Invalid proficiency must fail.
    BEGIN
        INSERT INTO recruitment.job_skill_requirement (
            job_posting_id,
            skill_id,
            minimum_proficiency_level
        )
        VALUES (
            v_job_id,
            v_skill_id + 999999,
            'master'
        );

        RAISE EXCEPTION 'FAIL: invalid proficiency accepted';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS: invalid proficiency rejected';
    END;

    RAISE NOTICE 'PASS: job posting constraint suite completed';
END
$$;

ROLLBACK;
